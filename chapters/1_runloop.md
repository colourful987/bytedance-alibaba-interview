# Runloop

`runloop`对于一个标准的iOS开发来说都不陌生，应该说熟悉`runloop`是标配，下面就随便列几个典型问题吧

### app如何接收到触摸事件的

> [iOS Touch Event from the inside out](https://www.jianshu.com/p/70ba981317b6)

#### 1 Touch Event 的生命周期

##### 1.1 物理层面事件的生成

iPhone 采用电容触摸传感器，利用人体的电流感应工作，由一块四层复合玻璃屏的内表面和夹层各涂有一层导电层，最外层是一层矽土玻璃保护层。当我们手指触摸感应屏的时候，人体的电场让手指和触摸屏之间形成一个耦合电容，对高频电流来说电容是直接导体。于是手指从接触点吸走一个很小的电流，这个电流分从触摸屏的四脚上的电极流出，并且流经这四个电极的电流和手指到四个电极的距离成正比。控制器通过对这四个电流的比例做精确的计算，得出触摸点的距离。

> 更多文献：
> * [OLED发光原理、面板结构及OLED关键技术深度解析](https://www.hangjianet.com/v5/topicDetail?id=15422809007930000)
> * [光学触摸屏原理](http://www.51touch.com/technology/principle/201308/29-24678.html)
> * [电容触摸屏原理](http://www.51touch.com/technology/principle/201308/14-24323.html)
> * [电阻式触摸屏原理(FLASH演示版)](http://www.51touch.com/technology/principle/201309/04-24800.html)
> * [iPhone这十年在传感器上的演进](https://zhuanlan.zhihu.com/p/22677100)

##### 1.2 iOS 操作系统下封装和分发事件

iOS 操作系统看做是一个处理复杂逻辑的程序，不同进程之间彼此通信采用消息发送方式，即 IPC (Inter-Process Communication)。现在继续说上面电容触摸传感器产生的 Touch Event，它将交由 IOKit.framework 处理封装成 IOHIDEvent 对象；下一步很自然想到通过消息发送方式将事件传递出去，至于发送给谁，何时发送等一系列的判断逻辑又该交由谁处理呢？

答案是 **SpringBoard.app**，它接收到封装好的 **IOHIDEvent** 对象，经过逻辑判断后做进一步的调度分发。例如，它会判断前台是否运行有应用程序，有则将封装好的事件采用 mach port 机制传递给该应用的主线程。

Port 机制在 IPC 中的应用是 Mach 与其他传统内核的区别之一，在 Mach 中，用户进程调用内核交由 IPC 系统。与直接系统调用不同，用户进程首先向内核申请一个 port 的访问许可；然后利用 IPC 机制向这个 port 发送消息，本质还是系统调用，而处理是交由其他进程完成的。

##### 1.3 IOHIDEvent -> UIEvent

应用程序主线程的 runloop 申请了一个 mach port 用于监听 `IOHIDEvent` 的 `Source1` 事件，回调方法是 `__IOHIDEventSystemClientQueueCallback()`，内部又进一步分发 `Source0` 事件，而 `Source0`事件都是自定义的，非基于端口 port，包括触摸，滚动，selector选择器事件，它的回调方法是 `__UIApplicationHandleEventQueue()`，将接收到的 `IOHIDEvent` 事件对象封装成我们熟悉的 `UIEvent` 事件；然后调用 `UIApplication` 实例对象的 `sendEvent:` 方法，将 `UIEvent` 传递给 `UIWindow` 做一些逻辑判断工作：比如触摸事件产生于哪些视图上，有可能有多个，那又要确定哪个是最佳选项呢？ 等等一系列操作。这里先按下不表。

##### 1.4 Hit-Testing 寻找最佳响应者

`Source0` 回调中将封装好的触摸事件 UIEvent（里面有多个UITouch 即手势点击对象），传递给视图 `UIWindow`，其目的在于找到最佳响应者，这个过程称之为 `Hit-Testing`，字面上理解：hit 即触碰了屏幕某块区域，这个区域可能有多个视图叠加而成，那么这个触摸讲道理响应者有多个喽，那么“最佳”又该如何评判？这里要牢记几个规则：

1. 事件是自下而上传递，即 `UIApplication -> UIWindow -> 子视图 -> ...->子视图中的子视图`;
2. 后加的视图响应程度更高，即更靠近我们的视图;
3. 如果某个视图不想响应，则传递给比它响应程度稍低一级的视图，若能响应，你还得继续往下传递，若某个视图能响应了，但是没有子视图 它就是最佳响应者。
4. 寻找最佳响应者的过程中， UIEvent 中的 UITouch 会不断打上标签：比如 `HitTest View` 是哪个，`superview` 是哪个？关联了什么 `Gesture Recognizer`?

那么如何判定视图为响应者？由于 OC 中的类都继承自 `NSObject` ，因此默认判断逻辑已经在`hitTest:withEvent`方法中实现，它有两个作用： 1.询问当前视图是否能够响应事件 2.事件传递的桥梁。若当前视图无法响应事件，返回 nil 。代码如下：

```swift
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{ 
  // 1. 前置条件要满足       
  if (self.userInteractionEnabled == NO || 
  self.hidden == YES ||  
  self.alpha <= 0.01) return nil;
  
  // 2. 判断点是否在视图内部 这是最起码的 note point 是在当前视图坐标系的点位置
    if ([self pointInside:point withEvent:event] == NO) return nil;

  // 3. 现在起码能确定当前视图能够是响应者 接下去询问子视图
    int count = (int)self.subviews.count;
    for (int i = count - 1; i >= 0; i--)
    {
      // 子视图
        UIView *childView = self.subviews[i];
    
    // 点需要先转换坐标系        
        CGPoint childP = [self convertPoint:point toView:childView];  
        // 子视图开始询问
        UIView *fitView = [childView hitTest:childP withEvent:event]; 
        if (fitView)
        {
      return fitView;
    }
    }
                         
    return self;
}
```

1. 首先满足几个前置条件，可交互`userInteractionEnabled=YES`；没有隐藏`self.hidden == NO`；非透明 `self.alpha <= 0.01` ———— 注意一旦不满足上述三个条件，当前视图及其子视图都不能作为响应者，Hit-Testing 判定也止步于此
2. 接着判断触摸点是否在视图内部 ———— 这个是最基本，无可厚非的判定规则
3. 此时已经能够说当前视图为响应者，但是不是**最佳**还不能下定论，因此需要进一步传递给子视图判定；注意 `pointInside` 也是默认实现的。

##### 1.5 UIResponder Chain 响应链

`Hit-Testing` 过程中我们无法确定当前视图是否为“最佳”响应者，此时自然还不能处理事件。因此处理机制应该是找到所有响应者以及最佳响应者(**自下而上**)，由它们构成了一条响应链；接着将事件沿着响应链**自上而下**传递下去 ——最顶端自然是最佳响应者，事件除了被响应者消耗，还能被手势识别器或是 `target-action` 模式捕获并消耗。有时候，最佳响应者可能对处理 `Event` “毫无兴趣”，它们不会重写 `touchBegan` `touchesMove`..等四个方法；也不会添加任何手势；但如果是 `control(控件)` 比如 UIButton ，那么事件还是会被消耗掉的。

##### 1.6 UITouch 、 UIEvent 、UIResponder

IOHIDEvent 前面说到是在 IOKit.framwork 中生成的然后经过一系列的分别才到达前台应用，然后应用主线程runloop处理source1回调中又进行source0事件分发，这里有个封装UIEvent的过程，那么 UITouch 呢？ 是不是也是那时候呢？换种思路：一个手指一次触摸屏幕 生成一个 UITouch 对象，内部应该开始进行识别了，因为可能是多个 Touch，并且触摸的先后顺序也不同，这样识别出来的 UIEvent 也不同。所以 UIEvent 对象中包含了触发该事件的触摸对象的集合，通过 allTouches 属性获取。

每个响应者都派生自 UIResponder 类，本身具有相应事件的能力，响应者默认实现 `touchesBegin` `touchesMove` `touchesEnded` `touchesCancelled`四个方法。

事件在未截断的情况下沿着响应链传递给最佳响应者，伪代码如下：

```swift
0 - [AView touchesBegan:withEvent
1 - [UIWindow _sendTouchesForEvent]
2 - [UIWindow sendEvent]           
3 - [UIApplication sendEvent]      
4 __dispatchPreprocessEventFromEventQueue
5 __handleEventQueueInternal
6 _CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION_
7 _CFRunLOOPDoSource0
8 _CFRunLOOPDoSources0
9 _CFRunLoopRun
10 _CFRunLoopRunSpecific
11 GSEventRunModal
12 UIApplication
13 main
14 start

// UIApplication.m
- (void)sendEvent {
  [window sendEvent];
}

// UIWindow.m
- (void)sendEvent{
  [self _sendTouchesForEvent];
}

- (void)_sendTouchesForEvent{
  //find AView Because we know hitTest View
  [AView touchesBegan:withEvent];
}
```

### 为什么只有主线程的`runloop`是开启的

> 这个问题很奇葩，要回答的会就是其他线程并没有调用 `NSRunLoop *runloop = [NSRunLoop currentRunLoop]`，其他还能说啥呢？更多源码分析见网上教程。

```c
CFRunLoopRef CFRunLoopGetCurrent(void) {
    CHECK_FOR_FORK();
    CFRunLoopRef rl = (CFRunLoopRef)_CFGetTSD(__CFTSDKeyRunLoop);
    if (rl) return rl;
    return _CFRunLoopGet0(pthread_self());
}
```

### 为什么只在主线程刷新UI

> 引用掘金文章[《iOS拾遗——为什么必须在主线程操作UI》](https://juejin.im/post/5c406d97e51d4552475fe178)。

UIKit并不是一个 **线程安全** 的类，UI操作涉及到渲染访问各种View对象的属性，如果异步操作下会存在读写问题，而为其加锁则会耗费大量资源并拖慢运行速度。另一方面因为整个程序的起点`UIApplication`是在主线程进行初始化，所有的用户事件都是在主线程上进行传递（如点击、拖动），所以 view 只能在主线程上才能对事件进行响应。而在渲染方面由于图像的渲染需要以60帧的刷新率在屏幕上 **同时** 更新，在非主线程异步化的情况下无法确定这个处理过程能够实现同步更新。

### `PerformSelector`和`runloop`的关系

perform 有几种方式，如 `[self performSelector:@selector(perform) withObject:nil]` 同步执行的，等同于 objc_msgSend 方法执行调用方法。

而`[self performSelector:@selector(perform) withObject:nil afterDelay:0]` 则是会在当前 runloop 中起一个 timer，如果当前线程没有起runloop(也就是上面说的没有调用 `[NSRunLoop currentRunLoop]` 方法的话)，则不会有输出

```objective-c
- (IBAction)test01:(id)sender {
    dispatch_async(self.concurrencyQueue2, ^{
        NSLog(@"[1] 线程：%@",[NSThread currentThread]);
        // 当前线程没有开启 runloop 所以改方法是没办法执行的
        [self performSelector:@selector(perform) withObject:nil afterDelay:0];
        NSLog(@"[3]");
    });
}

- (void)perform {
    NSLog(@"[2] 线程：%@",[NSThread currentThread]);
}
```

> This method sets up a timer to perform the `aSelector` message on the current thread’s run loop. The timer is configured to run in the default mode (`NSDefaultRunLoopMode`). When the timer fires, the thread attempts to dequeue the message from the run loop and perform the selector. It succeeds if the run loop is running and in the default mode; otherwise, the timer waits until the run loop is in the default mode. 
>
> If you want the message to be dequeued when the run loop is in a mode other than the default mode, use the [performSelector:withObject:afterDelay:inModes:](apple-reference-documentation://hcVXEPtYGA)method instead. If you are not sure whether the current thread is the main thread, you can use the [performSelectorOnMainThread:withObject:waitUntilDone:](apple-reference-documentation://hcChQUeJuZ) or [performSelectorOnMainThread:withObject:waitUntilDone:modes:](apple-reference-documentation://hcNxrNoLOP) method to guarantee that your selector executes on the main thread. To cancel a queued message, use the [cancelPreviousPerformRequestsWithTarget:](apple-reference-documentation://hcVCAfekYt) or [cancelPreviousPerformRequestsWithTarget:selector:object:](apple-reference-documentation://hc3jvcW4n6) method.

修改代码：

```objective-c
- (IBAction)test01:(id)sender {
    dispatch_async(self.concurrencyQueue2, ^{
        NSLog(@"[1] 线程：%@",[NSThread currentThread]);
        // 当前线程没有开启 runloop 所以改方法是没办法执行的
        NSRunLoop *runloop = [NSRunLoop currentRunLoop]; 
        [self performSelector:@selector(perform) withObject:nil afterDelay:0];// 这里打断点，po runloop ，查看执行这条语句后runloop添加了啥
        [runloop run];
        NSLog(@"[3]");
    });
}
```

输出如下内容，注意 `[3]` 被输出了，所以说 runloop 并没有被起来，至于原因见下。

```objective-c
2020-04-07 00:16:43.146357+0800 04-06-performSelector-RunLoop[15486:585028] [1] 线程：<NSThread: 0x6000000cdd00>{number = 6, name = (null)}
2020-04-07 00:16:43.146722+0800 04-06-performSelector-RunLoop[15486:585028] [2] 线程：<NSThread: 0x6000000cdd00>{number = 6, name = (null)}
2020-04-07 00:16:43.146932+0800 04-06-performSelector-RunLoop[15486:585028] [3]
```

所以为了保活可以加个定时器，repeat=YES 的那种。(ps: repeat=NO 的那种复习下 timer 的循环引用会自动打破！)

```objective-c
- (IBAction)test01:(id)sender {
    dispatch_async(self.concurrencyQueue2, ^{
        NSLog(@"[1] 线程：%@",[NSThread currentThread]);
        NSTimer *timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            NSLog(@"timer 定时任务");
        }];
        
        // 当前线程没有开启 runloop 所以改方法是没办法执行的
        NSRunLoop *runloop = [NSRunLoop currentRunLoop];
        [runloop addTimer:timer forMode:NSDefaultRunLoopMode];
        [self performSelector:@selector(perform) withObject:nil afterDelay:0];
        [runloop run];
        NSLog(@"[3]");
    });
}
```

RunLoop 添加观察者代码：

```objective-c
/*
 kCFRunLoopEntry = (1UL << 0),1
 kCFRunLoopBeforeTimers = (1UL << 1),2
 kCFRunLoopBeforeSources = (1UL << 2), 4
 kCFRunLoopBeforeWaiting = (1UL << 5), 32
 kCFRunLoopAfterWaiting = (1UL << 6), 64
 kCFRunLoopExit = (1UL << 7),128
 kCFRunLoopAllActivities = 0x0FFFFFFFU
 */
static void addRunLoopObserver() {
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(CFAllocatorGetDefault(), kCFRunLoopAllActivities, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        switch (activity) {
            case kCFRunLoopEntry: {
                NSLog(@"即将进入 runloop");
            }
                break;
            case kCFRunLoopBeforeTimers: {
                NSLog(@"定时器 timers 之前");
            }
                break;
            case kCFRunLoopBeforeSources: {
                NSLog(@"Sources 事件前");
            }
                break;
            case kCFRunLoopBeforeWaiting: {
                NSLog(@"RunLoop 即将进入休眠");
            }
                break;
            case kCFRunLoopAfterWaiting: {
                NSLog(@"RunLoop 唤醒后");
            }
                break;
            case kCFRunLoopExit: {
                NSLog(@"退出");
            }
                break;
            default:
                break;
        }
    });
  	// 这里 CFRunLoopGetCurrent 创建了当前线程的 runloop 对象
    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, kCFRunLoopCommonModes);
    CFRelease(observer);
}

- (IBAction)test01:(id)sender {
    dispatch_async(self.concurrencyQueue2, ^{
        NSLog(@"[1] 线程：%@",[NSThread currentThread]);
        NSTimer *timer = [NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer * _Nonnull timer) {
            NSLog(@"timer 定时任务");
        }];
        addRunLoopObserver();
        // 当前线程没有开启 runloop 所以改方法是没办法执行的
        NSRunLoop *runloop = [NSRunLoop currentRunLoop];
        [runloop addTimer:timer forMode:NSDefaultRunLoopMode];
        [self performSelector:@selector(perform) withObject:nil afterDelay:0];
        [runloop run];
        NSLog(@"[3]");
    });
}
```

>  参考文献：
>
> * [Runloop与performSelector](https://juejin.im/post/5c70b391e51d451646267db1)

### 如何使线程保活

> 线程保活就是不让线程退出，所以往简单说就是搞个 “while(1)” 自己实现一套处理流程，事件派发就可以了；但 iOS 中有 runloop，所以我们就无须大费周章。 TODO： C 语言嵌入式如何实现线程池和保活。

runloop 线程保活前提就是有事情要处理，这里指 timer，source0，source1 事件。

所以有如下几种方式，方式一：

```objective-c
NSTimer *timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
   NSLog(@"timer 定时任务");
}];
NSRunLoop *runloop = [NSRunLoop currentRunLoop];
[runloop addTimer:timer forMode:NSDefaultRunLoopMode];
[runloop run];
```

方式二：

```objective-c
NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
[runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
[runLoop run];
```

方式三：

```objectivec
- (IBAction)testRunLoopKeepAlive:(id)sender {
    self.myThread = [[NSThread alloc] initWithTarget:self selector:@selector(start) object:nil];
    [self.myThread start];
}

- (void)start {
    self.finished = NO;
    do {
      	// Runs the loop until the specified date, during which time it processes data from all attached input sources.
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    } while (!self.finished);
}
- (IBAction)closeRunloop:(id)sender {
    self.finished = YES;
}

- (IBAction)executeTask:(id)sender {
    [self performSelector:@selector(doTask) onThread:self.myThread withObject:nil waitUntilDone:NO];
}

- (void)doTask {
    NSLog(@"执行任务在线程：%@",[NSThread currentThread]);
}
```

> If no input sources or timers are attached to the run loop, this method exits immediately and returns `NO`; otherwise, it returns after either the first input source is processed or `limitDate` is reached. Manually removing all known input sources and timers from the run loop does not guarantee that the run loop will exit immediately. macOS may install and remove additional input sources as needed to process requests targeted at the receiver’s thread. Those sources could therefore prevent the run loop from exiting.

所以上面的方式并非完美，只要没有源，runloop 直接就被退出了，但是因为包了一个while (!self.finished)，所以相当于退出->起->退出-> 起。

> Note:  如果runloop中没有处理事件，这里一直会退出然后起runloop，就算设置了 `[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];` 也没用，但是执行过一次 `[self performSelector:@selector(doTask) onThread:self.myThread withObject:nil waitUntilDone:NO]`，那么程序就卡在 `[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]` 这一行了。
>
> TODO: 看下源码实现。