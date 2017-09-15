//
//  FLKBaseView.h
//  FLKBaseClasses
//
//  Created by nanhu on 2016/11/28.
//  Copyright © 2016年 nanhu. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FLKConstants.h"

@interface FLKBaseView : UIView

/**
 placeholder view
 */
@property (nonatomic, strong, nullable, readonly) UILabel *placeholder;

/**
 whether self is visible

 @return reulst
 */
- (BOOL)isVisible;

/**
 wether show the placeholder view

 @param show :hidden or show
 @param holder :show info
 */
- (void)showPlaceholder:(BOOL)show withInfo:(NSString * _Nullable)holder;

/**
 when touch error placeholder view
 */
- (void)didTouchErrorPlaceholder NS_REQUIRES_SUPER;

@end
