//
//  ViewController.m
//  AudioKit
//
//  Created by nanhujiaju on 2017/3/1.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import "ViewController.h"
#import "FLKAudioRecProfile.h"
#define MAS_SHORTHAND
#define MAS_SHORTHAND_GLOBALS
#import <Masonry/Masonry.h>

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIButton *recordBtn;
@property (strong, nonatomic) FLKAudioRecProfile *audioRecView;
@property (strong, nonatomic) MASConstraint *recordTopConstraint;
@property (nonatomic, assign) BOOL whetherLayoutSubviews;

@end

@implementation ViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //init back navigation bar item
    //left
    //UIBarButtonItem *spacer = [self barSpacer];
    //UIBarButtonItem *backBarItem = [self backBarButtonItem:nil];
    //[self.navigationBar pushNavigationItem:leftItem animated:true];
    UINavigationItem *title = [[UINavigationItem alloc] initWithTitle:@"Chat session"];
    //title.leftBarButtonItems = @[spacer, backBarItem];
    [self.navigationBar pushNavigationItem:title animated:true];
    
    //set title
    [self.recordBtn setTitle:@"start record" forState:UIControlStateNormal];
    [self.recordBtn setTitle:@"stop record" forState:UIControlStateSelected];
    
    self.view.backgroundColor = [UIColor pb_randomColor];
    
    FLKAudioRecProfile *profile = [[FLKAudioRecProfile alloc] initWithFrame:CGRectZero];
    //profile.backgroundColor = [UIColor pb_randomColor];
    [self.view addSubview:profile];
    self.audioRecView = profile;
    
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (self.whetherLayoutSubviews) {
        return;
    }
    NSLog(@"___%s", __FUNCTION__);
    weakify(self)
    [self.audioRecView mas_remakeConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self.view.mas_bottom).priority(UILayoutPriorityDefaultHigh);
        make.left.equalTo(self.view);
        make.right.equalTo(self.view);
        make.height.equalTo(@(FLK_AUDIO_REC_HEIGHT));
        if (!self.recordTopConstraint) {
            self.recordTopConstraint = make.top.equalTo(self.view.mas_bottom).offset(@(-FLK_AUDIO_REC_HEIGHT)).priority(UILayoutPriorityRequired);
        }
    }];
    [self.recordTopConstraint deactivate];
    self.whetherLayoutSubviews = true;
}

- (IBAction)recordPrepareEvent:(UIButton *)sender {
    sender.selected = !sender.selected;
    
    BOOL hidden = !sender.selected;
    //CGFloat pickerHeight = CGRectGetHeight(self.audioRecView.bounds);
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.55
                          delay:0.0
         usingSpringWithDamping:0.6
          initialSpringVelocity:0.5
                        options:(UIViewAnimationOptionBeginFromCurrentState|
                                 UIViewAnimationOptionCurveEaseInOut|
                                 UIViewAnimationOptionLayoutSubviews)
                     animations:^{
                         //weakSelf.recordTopConstraint.constant = hidden ? 0.f : -pickerHeight;
                         hidden?[weakSelf.recordTopConstraint deactivate]:[weakSelf.recordTopConstraint activate];
                         [weakSelf.view layoutSubviews];
                     } completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
