## 1. +load 与 +initialize 区别，initialize 是否会覆盖父类方法，为什么？

* `load` 方法是在读取 image 镜像的时候调用；

  * 主类较之分类会先调用，会按照基类->父类->子类依次调用 `+load`  方法；分类是按照**编译顺序**决定的，也就是 BuildPhase 中的编译顺序，和类的继承关系无关；
  * 多个主类的 `+load` 会按照编译顺序调用；
  * `+load` 方法是系统自动调用，所以禁止在内部调用 `[super load]` 会引发未知、奇怪的现象（其实也是可以说的通的，`[super load]` 实际上还涉及到 category 方法覆盖问题，以及第一次类被调用时会调用 initialize 方法）；
  * `load` 方法在main函数之前执行，`initialize `在main函数之后且被用到的时候才会初始化；

* `+initialize` 方法只有当类第一次被使用到的时候才会去加载，且会触发父类调用；

  * runtime 底层会去调用父类的方法，如下图的 `_class_initialize(supercls)`：

    ```objective-c
    void _class_initialize(Class cls)
    {
        Class supercls;
        bool reallyInitialize = NO;
    
        // Make sure super is done initializing BEFORE beginning to initialize cls.
        // See note about deadlock above.
        supercls = cls->superclass;
        if (supercls  &&  !supercls->isInitialized()) {
            _class_initialize(supercls);
        }
    		// 省略.....
    }
    ```

  * `+initialize` 可以简单理解为方法调用，所以分类的方法会“覆盖”主类的方法，且后编译的分类方法会被调用；

  * `+initialize` 有且仅会被调用一次；

  *  `+initialize` 会覆盖父类方法，和普通的方法调用是一样的，且内部隐式地会判断super 是否被初始化过，如果没有则会去调用 super 的 initialize 方法，

* **Note**: 千万不要在 load 和 initialize 方法中调用 [super xxx]，除非你能理顺关系

## 2. 为什么有调用顺序的区别？

从方法名上来推测，`+load` 就是加载，不同的分类可能加载要处理的事情不同，`+initialize` 则是初始化，类初始化一次就够了。

## 完整源码

load 方法调用时机，而且只调用当前类本身，不会调用superClass 的 `+load` 方法，如果你使用 `[super load]` 那是在走消息发送，runtime 底层调用实现如下：

```c
void
load_images(const char *path __unused, const struct mach_header *mh)
{
    // Return without taking locks if there are no +load methods here.
    if (!hasLoadMethods((const headerType *)mh)) return;

    recursive_mutex_locker_t lock(loadMethodLock);

    // Discover load methods
    {
        mutex_locker_t lock2(runtimeLock);
        prepare_load_methods((const headerType *)mh);
    }

    // Call +load methods (without runtimeLock - re-entrant)
    call_load_methods();
}

void call_load_methods(void)
{
    static bool loading = NO;
    bool more_categories;

    loadMethodLock.assertLocked();

    // Re-entrant calls do nothing; the outermost call will finish the job.
    if (loading) return;
    loading = YES;

    void *pool = objc_autoreleasePoolPush();

    do {
        // 1. Repeatedly call class +loads until there aren't any more
        while (loadable_classes_used > 0) {
            call_class_loads();
        }

        // 2. Call category +loads ONCE
        more_categories = call_category_loads();

        // 3. Run more +loads if there are classes OR more untried categories
    } while (loadable_classes_used > 0  ||  more_categories);

    objc_autoreleasePoolPop(pool);

    loading = NO;
}
```

runtime 中对 `+initialize`  调用，判断父类是否 `isInitialized` ，

```c
void _class_initialize(Class cls)
{
    assert(!cls->isMetaClass());

    Class supercls;
    bool reallyInitialize = NO;

    // Make sure super is done initializing BEFORE beginning to initialize cls.
    // See note about deadlock above.
    supercls = cls->superclass;
    if (supercls  &&  !supercls->isInitialized()) {
        _class_initialize(supercls);
    }
    
    // Try to atomically set CLS_INITIALIZING.
    {
        monitor_locker_t lock(classInitLock);
        if (!cls->isInitialized() && !cls->isInitializing()) {
            cls->setInitializing();
            reallyInitialize = YES;
        }
    }
    
    if (reallyInitialize) {
        // We successfully set the CLS_INITIALIZING bit. Initialize the class.
        
        // Record that we're initializing this class so we can message it.
        _setThisThreadIsInitializingClass(cls);

        if (MultithreadedForkChild) {
            // LOL JK we don't really call +initialize methods after fork().
            performForkChildInitialize(cls, supercls);
            return;
        }
        
        // Send the +initialize message.
        // Note that +initialize is sent to the superclass (again) if 
        // this class doesn't implement +initialize. 2157218
        if (PrintInitializing) {
            _objc_inform("INITIALIZE: thread %p: calling +[%s initialize]",
                         pthread_self(), cls->nameForLogging());
        }

        // Exceptions: A +initialize call that throws an exception 
        // is deemed to be a complete and successful +initialize.
        //
        // Only __OBJC2__ adds these handlers. !__OBJC2__ has a
        // bootstrapping problem of this versus CF's call to
        // objc_exception_set_functions().
#if __OBJC2__
        @try
#endif
        {
            callInitialize(cls);

            if (PrintInitializing) {
                _objc_inform("INITIALIZE: thread %p: finished +[%s initialize]",
                             pthread_self(), cls->nameForLogging());
            }
        }
#if __OBJC2__
        @catch (...) {
            if (PrintInitializing) {
                _objc_inform("INITIALIZE: thread %p: +[%s initialize] "
                             "threw an exception",
                             pthread_self(), cls->nameForLogging());
            }
            @throw;
        }
        @finally
#endif
        {
            // Done initializing.
            lockAndFinishInitializing(cls, supercls);
        }
        return;
    }
    
    else if (cls->isInitializing()) {
        // We couldn't set INITIALIZING because INITIALIZING was already set.
        // If this thread set it earlier, continue normally.
        // If some other thread set it, block until initialize is done.
        // It's ok if INITIALIZING changes to INITIALIZED while we're here, 
        //   because we safely check for INITIALIZED inside the lock 
        //   before blocking.
        if (_thisThreadIsInitializingClass(cls)) {
            return;
        } else if (!MultithreadedForkChild) {
            waitForInitializeToComplete(cls);
            return;
        } else {
            // We're on the child side of fork(), facing a class that
            // was initializing by some other thread when fork() was called.
            _setThisThreadIsInitializingClass(cls);
            performForkChildInitialize(cls, supercls);
        }
    }
    
    else if (cls->isInitialized()) {
        // Set CLS_INITIALIZING failed because someone else already 
        //   initialized the class. Continue normally.
        // NOTE this check must come AFTER the ISINITIALIZING case.
        // Otherwise: Another thread is initializing this class. ISINITIALIZED 
        //   is false. Skip this clause. Then the other thread finishes 
        //   initialization and sets INITIALIZING=no and INITIALIZED=yes. 
        //   Skip the ISINITIALIZING clause. Die horribly.
        return;
    }
    
    else {
        // We shouldn't be here. 
        _objc_fatal("thread-safe class init in objc runtime is buggy!");
    }
}

void callInitialize(Class cls)
{
    ((void(*)(Class, SEL))objc_msgSend)(cls, SEL_initialize);
    asm("");
}
```



