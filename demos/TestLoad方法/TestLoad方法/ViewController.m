//
//  ViewController.m
//  TestLoad方法
//
//  Created by pmst on 2020/4/21.
//  Copyright © 2020 pmst. All rights reserved.
//

#import "ViewController.h"
#import "Person.h"
#import "Teacher.h"
#import "Professor.h"
#import <objc/runtime.h>
#import "PTRuntimeUtil.h"
@interface ViewController ()
@property(nonatomic, strong)Person *person;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.person = [Person new];
    NSLog(@"NSObject实例对象的成员变量所占用的大小为：%zd",class_getInstanceSize([self.person class]));
    [[PTRuntimeUtil new] logClassInfo:[self.person class]];
//    self.person = [Person new];
//    self.person.array = [NSMutableArray array];
//
//    [self.person addObserver:self forKeyPath:@"array" options:NSKeyValueObservingOptionNew context:nil];
//
//    [[self.person mutableArrayValueForKey:@"array"] addObject:@"ff"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSNumber *kind = change[NSKeyValueChangeKindKey];
    NSArray *students = change[NSKeyValueChangeNewKey];
    NSArray *oldStudent = change[NSKeyValueChangeOldKey];
    NSIndexSet *changedIndexs = change[NSKeyValueChangeIndexesKey];

    NSLog(@"kind: %@, students: %@, oldStudent: %@, changedIndexs: %@", kind, students, oldStudent, changedIndexs);
}


@end
