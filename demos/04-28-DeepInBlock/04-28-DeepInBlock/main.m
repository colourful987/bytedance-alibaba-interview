//
//  main.m
//  04-28-DeepInBlock
//
//  Created by pmst on 2020/4/28.
//  Copyright © 2020 pmst. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(int,PTBlockFlags) {
    PTBlockFlagsHasCopyDisposeHelpers = (1 << 25),
    PTBlockFlagsHasSignature          = (1 << 30)
};
typedef struct PTBlock {
    __unused Class isa;
    PTBlockFlags flags;
    __unused int reserved;
    void (__unused *invoke)(struct PTBlock *block, ...);
    struct {
        unsigned long int reserved;
        unsigned long int size;
        // requires PTBlockFlagsHasCopyDisposeHelpers
        void (*copy)(void *dst, const void *src);
        void (*dispose)(const void *);
        // requires PTBlockFlagsHasSignature
        const char *signature;
        const char *layout;
    } *descriptor;
    // imported variables
} *PTBlockRef;

typedef struct PTBlock_byref {
    void *isa;
    struct PTBlock_byref *forwarding;
    volatile int flags; // contains ref count
    unsigned int size;
    // 下面两个函数指针是不定的 要根据flags来
//    void (*byref_keep)(struct PTBlock_byref *dst, struct PTBlock_byref *src);
//    void (*byref_destroy)(struct PTBlock_byref *);
    // long shared[0];
} *PTBlock_byref_Ref;

#define DEMO 6

int main(int argc, const char * argv[]) {
    @autoreleasepool {
#if DEMO == 1
        void (^blk)(void) = ^{
            NSLog(@"hello world");
        };
        PTBlockRef block = (__bridge PTBlockRef)blk;
        block->invoke(block);
#elif DEMO == 2
        void (^blk)(int, short, NSString *) = ^(int a, short b, NSString *str){
            NSLog(@"a:%d b:%d str:%@",a,b,str);
        };
        PTBlockRef block = (__bridge PTBlockRef)blk;
        if (block->flags & PTBlockFlagsHasSignature) {
            void *desc = block->descriptor;
            desc += 2 * sizeof(unsigned long int);
            if (block->flags & PTBlockFlagsHasCopyDisposeHelpers) {
                desc += 2 * sizeof(void *);
            }

            const char *signature = (*(const char **)desc);
            NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:signature];
            NSLog(@"方法 signature:%s",signature);
        }
#elif DEMO == 3
        int a = 0x11223344;
        int b = 0x55667788;
        NSString *str = @"pmst";
        void (^blk)(void) = ^{
            NSLog(@"a:%d b:%d str:%@",a,b, str);
        };
        PTBlockRef block = (__bridge PTBlockRef)blk;
        void *pt = (void *)block + sizeof(struct PTBlock);
        long long *ppt = pt;
        NSString *str_ref = (__bridge id)((void *)(*ppt));
        int *a_ref = pt + sizeof(NSString *);
        int *b_ref = pt + sizeof(NSString *) + sizeof(int);
        
        NSLog(@"a:0x%x b:0x%x str:%@",*a_ref, *b_ref, str_ref);
#elif DEMO == 4
        __block int a = 0x99887766;
        __unsafe_unretained void (^blk)(void) = ^{
            NSLog(@"__block a :%d",a);
        };
        NSLog(@"Block 类型 %@",[blk class]);
        PTBlockRef block = (__bridge PTBlockRef)blk;
        void *pt = (void *)block + sizeof(struct PTBlock);
        long long *ppt = pt;
        void *ref = (PTBlock_byref_Ref)(*ppt);
        void *shared = ref + sizeof(struct PTBlock_byref);
        int *a_ref = (int *)shared;
        NSLog(@"a 指针：%p block a 指针:%p block a value:0x%x",&a, a_ref,*a_ref);
        NSLog(@"PTBlock_byref 指针：%p",ref);
        NSLog(@"PTBlock_byref forwarding 指针：%p",((PTBlock_byref_Ref)ref)->forwarding);
#elif DEMO == 5
        __block int a = 0x99887766;
        __unsafe_unretained void (^blk)(NSString *) = ^(NSString *flag){
            NSLog(@"[%@] 中 a 地址:%p",flag, &a);
        };
        NSLog(@"blk 类型 %@",[blk class]);
        blk(@"origin block");
        void (^copyblk)(NSString *) = [blk copy];
        NSLog(@"copyblk 类型 %@",[copyblk class]);
        copyblk(@"copy block");
        blk(@"origin block 二次打印");

//        int *a_ref = (int *)shared;
//        NSLog(@"a 指针：%p block a 指针:%p block a value:0x%x",&a, a_ref,*a_ref);
//        NSLog(@"PTBlock_byref 指针：%p",ref);
//        NSLog(@"PTBlock_byref forwarding 指针：%p",((PTBlock_byref_Ref)ref)->forwarding);
#elif DEMO == 6
        __block int a = 0x99887766;
        __unsafe_unretained void (^blk)(NSString *,id) = ^(NSString *flag, id bblk){
            NSLog(@"[%@] a address:%p",flag, &a); // a 取值都是 ->forwarding->a 方式
            PTBlockRef block = (__bridge PTBlockRef)bblk;
            void *pt = (void *)block + sizeof(struct PTBlock);
            long long *ppt = pt;
            void *ref = (PTBlock_byref_Ref)(*ppt);
            NSLog(@"[%@] PTBlock_byref_Ref 指针：%p",flag,ref);
            NSLog(@"[%@] PTBlock_byref_Ref forwarding 指针：%p",flag,((PTBlock_byref_Ref)ref)->forwarding);
            void *shared = ref + sizeof(struct PTBlock_byref);
            int *a_ref = (int *)shared;
            NSLog(@"[%@] a value : 0x%x a adress:%p", flag, *a_ref, a_ref);
            
        };
        NSLog(@"blk 类型 %@",[blk class]);
        blk(@"origin block", blk);
        void (^copyblk)(NSString *,id) = [blk copy];
        NSLog(@"copy之后 a address:%p", &a); 
        NSLog(@"copyblk 类型 %@",[copyblk class]);
        copyblk(@"copy block",copyblk);
        blk(@"origin block after copy", blk);
#endif

        

        
        
    }
    return 0;
}
