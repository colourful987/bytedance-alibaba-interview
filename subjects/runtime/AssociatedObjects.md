## 1. 关联对象需要手动处理生命周期吗？释放时机是什么时候？

> 出现频率：1

不需要，在 dealloc 方法中会进行关联对象的释放。

> 知识点一：关联对象是如何管理的?

底层通过 `AssociationsManager` 全局维护一个哈希表，当前对象指针通过取反操作作为取值的 KEY，然后从哈希表中找到对应的 `ObjectAssociationMap`，当前对象所有的关联对象都存储在这个 Map 中，键是我们方法中设定的，值是通过 `ObjcAssociation` 二次封装，数据结构包括了 `id value` 和 `uintptr_t _policy`。

底层关联对象的getter和setter实现代码如下：

```objective-c
void _object_set_associative_reference(id object, void *key, id value, uintptr_t policy) {
    // retain the new value (if any) outside the lock.
    ObjcAssociation old_association(0, nil);
    // 如果value对象存在，则进行retain or copy 操作
    id new_value = value ? acquireValue(value, policy) : nil;
    {
        AssociationsManager manager;
        // manager.associations() 返回的是一个 `AssociationsHashMap` 对象(*_map)
        // 所以这里 `&associations` 中用了 `&`
        AssociationsHashMap &associations(manager.associations());
        // intptr_t 是为了兼容平台，在64位的机器上，intptr_t和uintptr_t分别是long int、unsigned long int的别名；在32位的机器上，intptr_t和uintptr_t分别是int、unsigned int的别名
        // DISGUISE 内部对指针做了 ~ 取反操作，“伪装”
        disguised_ptr_t disguised_object = DISGUISE(object);
        if (new_value) {
            // break any existing association.
            /*
             AssociationsHashMap 继承自 unordered_map，存储 key-value 的组合
             iterator find ( const key_type& key )，如果 key 存在，则返回key对象的迭代器，
             如果key不存在，则find返回 unordered_map::end；因此可以通过 `map.find(key) == map.end()`
             判断 key 是否存在于当前 map 中。
             */
            AssociationsHashMap::iterator i = associations.find(disguised_object);
            // 这里和get操作不同，set操作时如果查询到对象没有关联对象，那么这一次设值是第一次，
            // 所以会创建一个新的 ObjectAssociationMap 用来存储实例对象的所有关联属性
            if (i != associations.end()) {
                // secondary table exists
                /*
                    unordered_map 的键值分别是迭代器的first和second属性。
                    所以说上面先通过 object 对象(实例对象or类对象) 找到其所有关联对象
                    i->second 取到又是一个 ObjectAssociationMap
                    此刻再通过我们自己设定的 key 来查找对应的关联属性值，不过使用
                    `ObjcAssociation` 封装的
                 */
                ObjectAssociationMap *refs = i->second;
                ObjectAssociationMap::iterator j = refs->find(key);
                // 关联属性用 ObjcAssociation 结构体封装
                if (j != refs->end()) {
                    old_association = j->second;
                    j->second = ObjcAssociation(policy, new_value);
                } else {
                    (*refs)[key] = ObjcAssociation(policy, new_value);
                }
            } else {
                // create the new association (first time).
                ObjectAssociationMap *refs = new ObjectAssociationMap;
                associations[disguised_object] = refs;
                (*refs)[key] = ObjcAssociation(policy, new_value);
                // 知识点是：newisa.has_assoc = true;
                object->setHasAssociatedObjects();
            }
        } else {
            // setting the association to nil breaks the association.
            AssociationsHashMap::iterator i = associations.find(disguised_object);
            if (i !=  associations.end()) {
                ObjectAssociationMap *refs = i->second;
                ObjectAssociationMap::iterator j = refs->find(key);
                if (j != refs->end()) {
                    old_association = j->second;
                    refs->erase(j);
                }
            }
        }
    }
    // release the old value (outside of the lock).
    if (old_association.hasValue()) ReleaseValue()(old_association);
}
```

getter 实现：

```objective-c

id _object_get_associative_reference(id object, void *key) {
    id value = nil;
    uintptr_t policy = OBJC_ASSOCIATION_ASSIGN;
    {
        AssociationsManager manager;
        // manager.associations() 返回的是一个 `AssociationsHashMap` 对象(*_map)
        // 所以这里 `&associations` 中用了 `&`
        AssociationsHashMap &associations(manager.associations());
        // intptr_t 是为了兼容平台，在64位的机器上，intptr_t和uintptr_t分别是long int、unsigned long int的别名；在32位的机器上，intptr_t和uintptr_t分别是int、unsigned int的别名
        // DISGUISE 内部对指针做了 ~ 取反操作，“伪装”？
        disguised_ptr_t disguised_object = DISGUISE(object);
        /*
         AssociationsHashMap 继承自 unordered_map，存储 key-value 的组合
         iterator find ( const key_type& key )，如果 key 存在，则返回key对象的迭代器，
         如果key不存在，则find返回 unordered_map::end；因此可以通过 `map.find(key) == map.end()`
         判断 key 是否存在于当前 map 中。
         */
        AssociationsHashMap::iterator i = associations.find(disguised_object);
        if (i != associations.end()) {
            /*
                unordered_map 的键值分别是迭代器的first和second属性。
                所以说上面先通过 object 对象(实例对象or类对象) 找到其所有关联对象
                i->second 取到又是一个 ObjectAssociationMap
                此刻再通过我们自己设定的 key 来查找对应的关联属性值，不过使用
                `ObjcAssociation` 封装的
             */
            ObjectAssociationMap *refs = i->second;
            ObjectAssociationMap::iterator j = refs->find(key);
            if (j != refs->end()) {
                ObjcAssociation &entry = j->second;
                value = entry.value();
                policy = entry.policy();
                // 如果策略是 getter retain ，注意这里留个坑
                // 平常 OBJC_ASSOCIATION_RETAIN = 01401
                // OBJC_ASSOCIATION_GETTER_RETAIN = (1 << 8)
                if (policy & OBJC_ASSOCIATION_GETTER_RETAIN) {
                    // TODO: 有学问
                    objc_retain(value);
                }
            }
        }
    }
    if (value && (policy & OBJC_ASSOCIATION_GETTER_AUTORELEASE)) {
        objc_autorelease(value);
    }
    return value;
}
```

> 知识点二：关联对象dealloc释放过程

```objective-c
void *objc_destructInstance(id obj) 
{
    if (obj) {
        // Read all of the flags at once for performance.
        bool cxx = obj->hasCxxDtor();
        bool assoc = obj->hasAssociatedObjects();

        // This order is important.
        if (cxx) object_cxxDestruct(obj);
        if (assoc) _object_remove_assocations(obj);
        obj->clearDeallocating();
    }

    return obj;
}

void _object_remove_assocations(id object) {
    vector< ObjcAssociation,ObjcAllocator<ObjcAssociation> > elements;
    {
        AssociationsManager manager;
        AssociationsHashMap &associations(manager.associations());
        if (associations.size() == 0) return;
        disguised_ptr_t disguised_object = DISGUISE(object);
        AssociationsHashMap::iterator i = associations.find(disguised_object);
        if (i != associations.end()) {
            // copy all of the associations that need to be removed.
            ObjectAssociationMap *refs = i->second;
            for (ObjectAssociationMap::iterator j = refs->begin(), end = refs->end(); j != end; ++j) {
                elements.push_back(j->second);
            }
            // remove the secondary table.
            delete refs;
            associations.erase(i);
        }
    }
    // the calls to releaseValue() happen outside of the lock.
    for_each(elements.begin(), elements.end(), ReleaseValue());
}
```



