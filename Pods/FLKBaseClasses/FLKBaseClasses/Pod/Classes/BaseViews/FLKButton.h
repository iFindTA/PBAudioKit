//
//  FLKButton.h
//  FLKBaseClasses
//
//  Created by nanhujiaju on 2017/3/31.
//  Copyright © 2017年 nanhu. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FLKButton : UIButton


/**
 factory class method to create a button

 @param buttonType as system
 @return the button
 */
+ (instancetype)buttonWithType:(UIButtonType)buttonType;

@end
