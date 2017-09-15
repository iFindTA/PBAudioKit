//
//  FLKButton.m
//  FLKBaseClasses
//
//  Created by nanhujiaju on 2017/3/31.
//  Copyright © 2017年 nanhu. All rights reserved.
//

#import "FLKButton.h"

@implementation FLKButton

+ (instancetype)buttonWithType:(UIButtonType)buttonType {
    FLKButton *btn = [super buttonWithType:buttonType];
    if (btn) {
        btn.exclusiveTouch = true;
    }
    return btn;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
