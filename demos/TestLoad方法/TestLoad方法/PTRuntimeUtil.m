//
//  PTRuntimeUtil.m
//  RuntimeUtil
//
//  Created by pmst on 2020/3/15.
//  Copyright © 2020 pmst. All rights reserved.
//

#import "PTRuntimeUtil.h"
#import <objc/runtime.h>

@implementation PTRuntimeUtil

- (void)printMethods:(Class)cls {
    NSLog(@"==== OUTPUT:%@ Method ====",NSStringFromClass(cls));
    unsigned int count ;
    Method *methods = class_copyMethodList(cls, &count);
    
    for (int i = 0; i < count; i++) {
        Method method = methods[i];
        NSString *name = NSStringFromSelector(method_getName(method));
        NSLog(@"method name:%@\n",name);
    }
    free(methods);
}

- (void)printProperties:(Class)cls {
    NSLog(@"==== OUTPUT:%@ properties ====",NSStringFromClass(cls));
    
    unsigned int count ;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    
    for (int i = 0; i < count; i++) {
        objc_property_t prop = properties[i];
        const char *name = property_getName(prop);
        const char *attributes = property_getAttributes(prop);
        // TODO: attributes 转成 human read
        NSLog(@"property name：%s 属性：%s\n",name,attributes);
    }
    free(properties);
}

- (void)printIvars:(Class)cls {
    NSLog(@"==== OUTPUT:%@ Ivars ====",NSStringFromClass(cls));
    
    unsigned int count ;
    Ivar *ivars = class_copyIvarList(cls, &count);
    
    for (int i = 0; i < count; i++) {
        Ivar var = ivars[i];
        const char *name = ivar_getName(var);
        const char *encode = ivar_getTypeEncoding(var);
        // 类似 int32_t
        ptrdiff_t offset = ivar_getOffset(var);
        // TODO: attributes 转成 human read
        NSLog(@"ivar name：%s encode：%s 偏移量：%lu\n",name,encode,offset);
    }
    free(ivars);
}

- (void)printProtocols:(Class)cls {
    NSLog(@"==== OUTPUT:%@ Protocols ====",NSStringFromClass(cls));
    
    unsigned int count ;
    Protocol * __unsafe_unretained _Nonnull *protocols = class_copyProtocolList(cls, &count);
    
    for (int i = 0; i < count; i++) {
        Protocol * __unsafe_unretained _Nonnull protocol = protocols[i];
        const char *name = protocol_getName(protocol);
        NSLog(@"Protocol:%s 方法声明如下：",name);
        
        unsigned int methodcnt;
        struct objc_method_description * methodlist = protocol_copyMethodDescriptionList(protocol, YES, YES, &methodcnt);
        for (int j =0; j < methodcnt; j++) {
            struct objc_method_description desc = methodlist[j];
            NSLog(@"SEL %@ 类型：%s\n",NSStringFromSelector(desc.name), desc.types);
        }
        free(methodlist);
        
        NSLog(@"Protocol:%s 属性声明如下：",name);
        unsigned int protcnt;
        objc_property_t *properties = protocol_copyPropertyList(protocol, &protcnt);
        
        for (int i = 0; i < count; i++) {
            objc_property_t prop = properties[i];
            const char *name = property_getName(prop);
            const char *attributes = property_getAttributes(prop);
            // TODO: attributes 转成 human read
            NSLog(@"property name：%s 属性：%s\n",name,attributes);
        }
        free(properties);
        
    }
    free(protocols);
}

- (void)logClassInfo:(Class)cls {
    NSLog(@"LOG:(%@) INFO",NSStringFromClass(cls));
//    [self printProperties:cls];
    [self printIvars:cls];
//    [self printMethods:cls];
//    [self printProtocols:cls];
    NSLog(@"=========================\n");
}
@end
