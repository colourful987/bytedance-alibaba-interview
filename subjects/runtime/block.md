# Block 底层原理和 `_block` 关键字作用和原理
## 1 Block 基础知识

### 1.1 `block`的内部实现，结构体是什么样的

block 也是一个对象，一个捕获了上下文以及函数指针的结构体，数据结构上表现为 Imp 结构体 和 Desc 结构体（比如 block 入参类型），两个结构体之后跟着捕获的变量，用 `clang -rewrite-objc` 命令将 oc 代码重写成 c++：

```c++
struct __block_impl {
  void *isa;
  int Flags;
  int Reserved;
  void *FuncPtr;
};

struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int flags=0) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};
```

> 实际上 runtime 源码定义的 block 数据类型和上面还是有一定出路的，建议以下面的数据结构为准，另外强烈建议看下文中的《Block 原理探究代码篇》

```c
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
  	// Block 捕获的实例变量都在次
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
```

### 1.2 block是类吗，有哪些类型

block 有三种类型：`_NSConcreteGlobalBlock`、`_NSConcreteStackBlock`、`_NSConcreteMallocBlock`，根据Block对象创建时所处数据区不同而进行区别。

1. 栈上 Block，引用了栈上变量，生命周期由系统控制的，一旦所属作用域结束，就被系统销毁了，ARC 下由于默认是 `_strong` 属性，所以打印的可能都是 `_NSConcreteMallocBlock`，**这里使用 unretained** 关键字去修饰下就行了，或者 MRC 下去验证
2. 堆上 Block，使用 copy 或者 strong（ARC）下就从栈Block 拷贝到堆上；
3. 全局 Block，未引用任何栈上变量时就是全局Block；

### 1.3 一个`int`变量被 `__block` 修饰与否的区别？block的变量截获

> 关于 `__block` 建议看 《Block 原理探究代码篇》

值拷贝和指针拷贝，`__block` 修饰的话允许在 block 内部修改变量，因为传入的是 int变量的指针。

外部变量有四种类型：自动变量、静态变量、静态全局变量、全局变量。（**ps: 面试常问**）

全局变量和静态全局变量在 block 中是直接引用的，不需要通过结构去传入指针；

函数/方法中的 static 静态变量是直接在block中保存了指针，如下测试代码：

```c++
int a = 1;
static int b = 2;

int main(int argc, const char * argv[]) {

    int c = 3;
    static int d = 4;
    NSMutableString *str = [[NSMutableString alloc]initWithString:@"hello"];
    void (^blk)(void) = ^{
        a++;
        b++;
        d++;
        [str appendString:@"world"];
        NSLog(@"1----------- a = %d,b = %d,c = %d,d = %d,str = %@",a,b,c,d,str);
    };
    
    a++;
    b++;
    c++;
    d++;
str = [[NSMutableString alloc]initWithString:@"haha"];
    NSLog(@"2----------- a = %d,b = %d,c = %d,d = %d,str = %@",a,b,c,d,str);
    blk();
    
    return 0;
}
```

转成  c++ 代码：

```objective-c
struct __block_impl {
  void *isa;
  int Flags;
  int Reserved;
  void *FuncPtr;
};

int a = 1; // <------------------- NOTE
static int b = 2; // <------------------- NOTE
struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  int *d;						// <------------------- NOTE
  NSMutableString *str;				// <------------------- NOTE
  int c; // <------------------- NOTE
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int *_d, NSMutableString *_str, int _c, int flags=0) : d(_d), str(_str), c(_c) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};

static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
  int *d = __cself->d; // bound by copy
  NSMutableString *str = __cself->str; // bound by copy
  int c = __cself->c; // bound by copy

        a++;
        b++;
        (*d)++;
        ((void (*)(id, SEL, NSString *))(void *)objc_msgSend)((id)str, sel_registerName("appendString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_1);
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_2,a,b,c,(*d),str);
    }
static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) {_Block_object_assign((void*)&dst->str, (void*)src->str, 3/*BLOCK_FIELD_IS_OBJECT*/);}

static void __main_block_dispose_0(struct __main_block_impl_0*src) {_Block_object_dispose((void*)src->str, 3/*BLOCK_FIELD_IS_OBJECT*/);}

static struct __main_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
  void (*dispose)(struct __main_block_impl_0*);
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0), __main_block_copy_0, __main_block_dispose_0};

int main(int argc, const char * argv[]) {
    int c = 3;
    static int d = 4;
    NSMutableString *str = ((NSMutableString *(*)(id, SEL, NSString *))(void *)objc_msgSend)((id)((NSMutableString *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableString"), sel_registerName("alloc")), sel_registerName("initWithString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_0);
    void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, &d, str, c, 570425344));

    a++;
    b++;
    c++;
    d++;
    str = ((NSMutableString *(*)(id, SEL, NSString *))(void *)objc_msgSend)((id)((NSMutableString *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableString"), sel_registerName("alloc")), sel_registerName("initWithString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_3);
    NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_4,a,b,c,d,str);
    ((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);

    return 0;
}
```

### 1.4 `block`在修改`NSMutableArray`，需不需要添加`__block`

不需要，本身 block 内部就捕获了 NSMutableArray 指针，除非你要修改指针指向的对象，而这里明显只是修改内存数据，这个可以类比 NSMutableString。

### 1.5 怎么进行内存管理的

`static void *_Block_copy_internal(const void *arg, const int flags)` 和 `void _Block_release(void *arg) `

> 推荐[iOS Block原理探究以及循环引用的问题](https://www.jianshu.com/p/9ff40ea1cee5) 一文。

### 1.6 `block`可以用`strong`修饰吗

ARC 貌似是可以的， strong 和 copy 的操作都是将栈上block 拷贝到堆上。TODO：确认下。

### 1.7 解决循环引用时为什么要用`__strong、__weak`修饰

`__weak` 就是为了避免 retainCycle，而block 内部 `__strong` 则是在作用域 retain 持有当前对象做一些操作，结束后会释放掉它。

### 1.8 `block`发生`copy`时机

block 从栈上拷贝到堆上几种情况：

* 调用Block的copy方法

* 将Block作为函数返回值时

* 将Block赋值给__strong修饰的变量或Block类型成员变量时

* 向Cocoa框架含有usingBlock的方法或者GCD的API传递Block参数时

### 1.9 `Block`访问对象类型的`auto变量`时，在`ARC和MRC`下有什么区别

## 2 Block 原理探究代码篇

首先明确 Block 底层数据结构，之后所有的 demos 都基于此来学习知识点：

```c
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
  	// Block 捕获的实例变量都在次
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
```

### 2.1 调用 block

```c
void (^blk)(void) = ^{
  NSLog(@"hello world");
};
PTBlockRef block = (__bridge PTBlockRef)blk;
block->invoke(block);
```

### 2.2 block 函数签名

```c
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

// 打印内容如下:
// v24 @?0 i8 s12 @"NSString"16
// 其中 ? 是 An unknown type (among other things, this code is used for function pointers)
```

### 2.3 block 捕获栈上局部变量

捕获的变量都会按照顺序放置在 `PTBlock` 结构体后面，如此看来就是个变长结构体。

也就是说我们可以通过如下方式知道 block 捕获了哪些外部变量（全局变量除外）。

```c
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
```

> TODO：`NSString` layout 布局为何在第一位？

### 2.4 `__block` 变量（栈上）

```c
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
/*
输出如下：
Block 类型 __NSStackBlock__
a 指针：0x7ffeefbff528 block a 指针:0x7ffeefbff528 block a value:0x99887766
PTBlock_byref 指针：0x7ffeefbff510
PTBlock_byref forwarding 指针：0x7ffeefbff510
*/
```

可以看到 `__block int a` 已经变成了另外一个数据结构了，打印地址符合预期，此刻 block 以及其他的变量结构体都在栈上。

### 2.5  `__block` 变量，[block copy] 后的内存变化

```c
__block int a = 0x99887766;
__unsafe_unretained void (^blk)(NSString *) = ^(NSString *flag){
  NSLog(@"[%@] 中 a 地址:%p",flag, &a);
};
NSLog(@"blk 类型 %@",[blk class]);
blk(@"origin block");
void (^copyblk)(NSString *) = [blk copy];
copyblk(@"copy block");
blk(@"origin block 二次调用");
/**
	输出如下：
blk 类型 __NSStackBlock__
[origin block] 中 a 地址:0x7ffeefbff528
copyblk 类型 __NSMallocBlock__
[copy block] 中 a 地址:0x102212468
[origin block 二次调用] 中 a 地址:0x102212468
*/
```

很明显对 blk 进行 copy 操作后，copyblk 已经“移驾”到堆上，随着拷贝的还有 `__block` 修饰的a变量（`PTBlock_byref_Ref `类型）；

### 2.6 `__block` 变量中 forwarding 指针

```c
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
NSLog(@"copyblk 类型 %@",[copyblk class]);
copyblk(@"copy block",copyblk);
blk(@"origin block after copy", blk);
/**
MRC 模式下输出：
blk 类型 __NSStackBlock__
[origin block] a address:0x7ffeefbff528
[origin block] PTBlock_byref_Ref 指针：0x7ffeefbff510
[origin block] PTBlock_byref_Ref forwarding 指针：0x7ffeefbff510
[origin block] a value : 0x99887766 a adress:0x7ffeefbff528
copyblk 类型 __NSMallocBlock__
[copy block] a address:0x1032041d8
[copy block] PTBlock_byref_Ref 指针：0x1032041c0
[copy block] PTBlock_byref_Ref forwarding 指针：0x1032041c0
[copy block] a value : 0x99887766 a adress:0x1032041d8
[origin block after copy] a address:0x1032041d8
[origin block after copy] PTBlock_byref_Ref 指针：0x7ffeefbff510
[origin block after copy] PTBlock_byref_Ref forwarding 指针：0x1032041c0
[origin block after copy] a value : 0x99887766 a adress:0x7ffeefbff528

ARC 模式下输出（这个稍有出路）：
blk 类型 __NSStackBlock__
[origin block] a address:0x100604cc8
[origin block] PTBlock_byref_Ref 指针：0x100604cb0
[origin block] PTBlock_byref_Ref forwarding 指针：0x100604cb0
[origin block] a value : 0x99887766 a adress:0x100604cc8
copyblk 类型 __NSMallocBlock__
[copy block] a address:0x100604cc8
[copy block] PTBlock_byref_Ref 指针：0x100604cb0
[copy block] PTBlock_byref_Ref forwarding 指针：0x100604cb0
[copy block] a value : 0x99887766 a adress:0x100604cc8
*/
```

这里可以看到 forwarding 指针确实指向了结构体本身，随着 copy 行为确实进行了一次栈->堆的赋值——`block`和 `__block` 变量。

> 建议用 lldb 命令去看内存布局。

## 3. `_block` 关键字修饰底层实现

《Block原理研究代码篇》中见 2.3 - 2.6 小节对其代码验证。

`__block` 关键字修饰的变量最终都会变成如下结构体，内容是存储在 `long shared[0]` ，即仅跟结构体后面的内存中。

```objective-c
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
```

如下简单的调用：

```objective-c
__block int a = 0x99887766;
__unsafe_unretained void (^blk)(NSString *) = ^(NSString *flag){
  a = 0x11223344;
};
a = 0x55667788;
blk();
```

一旦用 `__block` 修饰后， a 就已经变成了上面的 `PTBlock_byref` 结构体了（**ps:PT是我加的前缀，但是数据结构和底层保持一致**），因此所有对变量的 a 的修改实际上都是使用 `a_block_byref_Ref->forwarding->a  ` 进行修改的，由于此刻 block 对象还在栈上，因此其捕获的 `__block` 修饰的变量（`PTBlock_byref` 的结构体）也同样是在栈上，且 `forwarding` 指针是指向该结构体本身。

上面的代码实际上应该是这样的：

```objective-c
PTBlock_byref a_block_byref_Ref = PTBlock_byref(0x99887766); // 伪代码

__unsafe_unretained void (^blk)(NSString *) = ^(NSString *flag){
  a_block_byref_Ref->forwarding->a = 0x11223344;
};

a_block_byref_Ref->forwarding->a = 0x55667788;

blk();
```

一旦 Block 发生了从栈到堆的拷贝操作，那么拷贝的同时，也会将 `__block` 修饰的所有变量（ `PTBlock_byref` 类型）拷贝到堆上，然后将`forwarding` 指针指向自身头部；而栈上的 `a_block_byref_Ref->forwarding` 修正为指向堆上的变量头部，所以保证了数据在 block 拷贝后修改一致性：

```objective-c
PTBlock_byref a_block_byref_Ref = PTBlock_byref(0x99887766); // 伪代码

__unsafe_unretained void (^blk)(NSString *) = ^(NSString *flag){
  a_block_byref_Ref->forwarding->a = 0x11223344;
};

// 此刻 forwarding 还是指向栈上的自身，也就是 a_block_byref_Ref
a_block_byref_Ref->forwarding->a = 0x55667788;

void (^copyblk)(NSString *) = [blk copy];

// 此刻 forwarding 已经指向一个堆上新的 PTBlock_byref a 变量了，修改的也是堆上的数据
a_block_byref_Ref->forwarding->a = 0x99887766;

blk();
```



