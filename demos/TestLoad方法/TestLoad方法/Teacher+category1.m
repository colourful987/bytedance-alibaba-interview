//
//  Teacher+category1.m
//  TestLoad方法
//
//  Created by pmst on 2020/4/21.
//  Copyright © 2020 pmst. All rights reserved.
//

#import "Teacher+category1.h"

@implementation Teacher (category1)
+ (void)load {
    NSLog(@"%s",__FUNCTION__);
}

+ (void)initialize {
    NSLog(@"%s",__FUNCTION__);
}
@end
