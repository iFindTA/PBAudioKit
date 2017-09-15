//
//  FLKAudioRecProfile.m
//  AudioKit
//
//  Created by nanhujiaju on 2017/3/1.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import "FLKAudioRecProfile.h"
#import <PBKits/PBKits.h>
#import <EZAudio/EZAudio.h>
#define MAS_SHORTHAND
#define MAS_SHORTHAND_GLOBALS
#import <Masonry/Masonry.h>
#import "FLKAudioMeter.h"
#import <SVProgressHUD/SVProgressHUD.h>

//audio record profile custom height
CGFloat const FLK_AUDIO_REC_HEIGHT                                    =   200;

typedef NS_ENUM(NSUInteger, FLKAudioRecState) {
    FLKAudioRecStateNone                                =   1   <<  0,
    FLKAudioRecStatePreStart                            =   1   <<  1,
    FLKAudioRecStateRecording                           =   1   <<  2,
    FLKAudioRecStatePlaying                             =   1   <<  3,
};

typedef struct {
    CGPoint center;
    int radius;
}CircleData;

static CircleData findCircle( CGPoint pt1, CGPoint pt2, CGPoint pt3) {
    CGPoint midPt1, midPt2;
    midPt1.x = (pt2.x + pt1.x)/2;
    midPt1.y = (pt2.y + pt1.y)/2;
    
    midPt2.x = ( pt3.x + pt1.x)/2;
    midPt2.y = ( pt3.y + pt1.y)/2;
    
    float k1 = -(pt2.x - pt1.x)/(pt2.y - pt1.y);
    float k2 = -(pt3.x - pt1.x)/(pt3.y - pt1.y);
    
    CircleData CD;
    CD.center.x = (midPt2.y - midPt1.y- k2* midPt2.x + k1*midPt1.x)/(k1 - k2);
    CD.center.y = midPt1.y + k1*( midPt2.y - midPt1.y - k2*midPt2.x + k2*midPt1.x)/(k1-k2);
    CD.radius = sqrtf((CD.center.x - pt1.x)*(CD.center.x - pt1.x) + (CD.center.y - pt1.y)*(CD.center.y - pt1.y));
    return CD;
}

typedef void(^_Nullable showBlock)(BOOL dismiss);
static void showHUDWithInfo(NSString *info, showBlock block) {
    PBMAIN(^{
        [SVProgressHUD showWithStatus:info];
        PBMAINDelay(PBANIMATE_DURATION * 4, ^{
            if (block) {
                block(true);
            }
        });
    });
}

/**
 * iconfont assets
 */
static NSString * const FLK_AUDIO_ICONFONT                      =   @"iconfont";
static NSString * const FLK_AUDIO_FONTFILE                      =   @"audioIconfont";
static NSString * const FLK_AUDIO_FONTCOLOR                     =   @"#545454";
static NSString * const FLK_AUDIO_ICONCOLOR                     =   @"#919191";
static NSString * const FLK_AUDIO_LINECOLOR                     =   @"#DCDCDC";

@interface FLKAudioRecProfile () <EZMicrophoneDelegate, EZRecorderDelegate, CAAnimationDelegate>

@property (nonatomic, strong) NSArray *inputs;

#pragma mark -- average meters --
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) double runningSumSquares, lastSample;
@property (nonatomic, assign) NSUInteger numberSamples;
@property (nonatomic, strong) FLKAudioMeter *audioMeterRight;
@property (nonatomic, strong) FLKAudioMeter *audioMeterLeft;

#pragma mark -- recorder --
@property (nonatomic, strong) EZMicrophone *microphone;
@property (nonatomic, strong) EZRecorder *audioRecorder;

#pragma mark -- UI --
@property (nonatomic, assign) FLKAudioRecState state;
@property (nonatomic, assign) CGFloat prepareHUDWidth;// cause of autolayout
@property (nonatomic, strong) UIView *prepareHUD;
@property (nonatomic, strong) UILabel *recordLab;
@property (nonatomic, strong) UILabel *stateLab;

//播放 删除icon
@property (nonatomic, strong) UIImageView *playIcon;
@property (nonatomic, strong) UIImageView *deleteIcon;
@property (nonatomic, strong) UILabel *playBgLab;//why not layer? cause of autolayout
@property (nonatomic, strong) UILabel *deleteBgLab;

//开始计时 每隔0.1秒加一 逢10的整数倍加一
@property (nonatomic, assign) NSUInteger sumSamples;
@property (nonatomic, strong) UILabel *timeLab;

@end

@implementation FLKAudioRecProfile

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self __initSetupProfile];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self __initSetupProfile];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self __initSetupProfile];
}

#pragma mark -- register font --

- (BOOL)registerCustomFontWithName:(NSString *)fontname {
    
    NSString *fontPath = [[NSBundle mainBundle] pathForResource:fontname ofType:@"ttf"];
    NSData *data = [NSData dataWithContentsOfFile:fontPath];
    if (data == nil) {
        NSLog(@"Failed to load font. Data at path %@ is null", fontname);
        return false;
    }
    CFErrorRef errorRef;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGFontRef font = CGFontCreateWithDataProvider(provider);
    //NSString *realFontName = (__bridge NSString *)CGFontCopyPostScriptName(font);
    BOOL ret = CTFontManagerRegisterGraphicsFont(font, &errorRef);
    if (!CTFontManagerRegisterGraphicsFont(font, &errorRef)) {
        NSError *error = (__bridge NSError *)errorRef;
        if (error.code != kCTFontManagerErrorAlreadyRegistered) {
            NSLog(@"Failed to load font: %@", error);
        }
    }
    CFRelease(font);
    CFRelease(provider);
    return ret;
}

#pragma mark -- getter --

- (FLKAudioMeter *)audioMeterRight {
    if (!_audioMeterRight) {
        _audioMeterRight = [[FLKAudioMeter alloc] initWithFrame:CGRectZero];
        _audioMeterRight.backgroundColor = [UIColor pb_randomColor];
    }
    return _audioMeterRight;
}

- (FLKAudioMeter *)audioMeterLeft {
    if (!_audioMeterLeft) {
        _audioMeterLeft = [[FLKAudioMeter alloc] initWithFrame:CGRectZero];
        _audioMeterLeft.backgroundColor = [UIColor pb_randomColor];
    }
    return _audioMeterLeft;
}

- (UILabel *)timeLab {
    if (!_timeLab) {
        _timeLab = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLab.font = PBSysFont(PBFontSubSize);
        _timeLab.textColor = [UIColor pb_colorWithHexString:FLK_AUDIO_FONTCOLOR];
        _timeLab.textAlignment = NSTextAlignmentCenter;
        _timeLab.text = @"0\"";
    }
    return _timeLab;
}

- (CADisplayLink *)displayLink {
    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleTimerFired)];
        _displayLink.paused = true;
        if (PBSysHighThan(@"10.0")) {
            _displayLink.preferredFramesPerSecond = 10;
        } else {
            _displayLink.frameInterval = 6;
        }
        [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    return _displayLink;
}

- (UILabel *)stateLab {
    if (!_stateLab) {
        _stateLab = [[UILabel alloc] initWithFrame:CGRectZero];
        _stateLab.font = PBSysFont(PBFontTitleSize);
        _stateLab.textColor = [UIColor pb_colorWithHexString:FLK_AUDIO_FONTCOLOR];
        _stateLab.textAlignment = NSTextAlignmentCenter;
        _stateLab.text = @"按住说话，最长60秒";
    }
    return _stateLab;
}

- (UIView *)prepareHUD {
    if (!_prepareHUD) {
        NSString *string = @"准备中...";
        UIFont *font = PBSysFont(PBFontTitleSize);
        CGSize strSize = [string pb_sizeThatFitsWithFont:font width:PBSCREEN_WIDTH];
        UIActivityIndicatorView *hud = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        CGFloat hudWidth = CGRectGetWidth(hud.bounds);
        hud.hidesWhenStopped = true;
        hud.frame = CGRectMake(0, 0, hudWidth, PB_CUSTOM_LAB_HEIGHT);
        CGRect bounds = CGRectMake(0, 0, strSize.width + hudWidth, PB_CUSTOM_LAB_HEIGHT);
        _prepareHUDWidth = CGRectGetWidth(bounds);
        _prepareHUD = [[UIView alloc] initWithFrame:bounds];
        [_prepareHUD addSubview:hud];
        [hud startAnimating];
        
        bounds = CGRectMake(hudWidth, 0, strSize.width, PB_CUSTOM_LAB_HEIGHT);
        UILabel *info = [[UILabel alloc] initWithFrame:bounds];
        //info.backgroundColor = [UIColor pb_randomColor];
        info.font = font;
        info.textColor = [UIColor pb_colorWithHexString:FLK_AUDIO_FONTCOLOR];
        info.text = string;
        [_prepareHUD addSubview:info];
    }
    return _prepareHUD;
}

- (UILabel *)recordLab {
    if (!_recordLab) {
        CGFloat iconSize = [self calculateRecordSize];
        _recordLab = [[UILabel alloc] init];
        _recordLab.backgroundColor = [UIColor pb_colorWithHexString:@"#1CA4E8"];
        _recordLab.font = PBFont(FLK_AUDIO_ICONFONT, iconSize*0.75);
        _recordLab.textAlignment = NSTextAlignmentCenter;
        _recordLab.textColor = [UIColor whiteColor];
        _recordLab.text = @"\U0000e608";
        _recordLab.layer.cornerRadius = iconSize * 0.5;
        _recordLab.layer.masksToBounds = true;
    }
    return _recordLab;
}

- (UIImageView *)playIcon {
    if (!_playIcon) {
        _playIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
        //_playIcon.backgroundColor = [UIColor whiteColor];
        _playIcon.contentMode = UIViewContentModeScaleAspectFit;
        CGFloat iconSize = [self calculateRecordSize] * 0.5;
        UIColor *iconColor = [UIColor pb_colorWithHexString:FLK_AUDIO_FONTCOLOR];
        UIImage *img = [UIImage pb_iconFont:nil withName:@"\U0000e61b" withSize:iconSize withColor:iconColor];
        _playIcon.image = img;
    }
    return _playIcon;
}

- (UILabel *)playBgLab {
    if (!_playBgLab) {
        CGFloat iconSize = [self calculateRecordSize] * 0.5;
        UIColor *lineColor = [UIColor pb_colorWithHexString:FLK_AUDIO_LINECOLOR];
        _playBgLab = [[UILabel alloc] initWithFrame:CGRectZero];
        _playBgLab.backgroundColor = [UIColor whiteColor];
        _playBgLab.layer.cornerRadius = iconSize * 0.5;
        _playBgLab.layer.masksToBounds = true;
        _playBgLab.layer.borderWidth = 1.f;
        _playBgLab.layer.borderColor = [lineColor CGColor];
    }
    return _playBgLab;
}

- (UIImageView *)deleteIcon {
    if (!_deleteIcon) {
        _deleteIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
        //_deleteIcon.backgroundColor = [UIColor whiteColor];
        _deleteIcon.contentMode = UIViewContentModeScaleAspectFit;
        CGFloat iconSize = [self calculateRecordSize] * 0.5;
        UIColor *iconColor = [UIColor pb_colorWithHexString:FLK_AUDIO_FONTCOLOR];
        UIImage *img = [UIImage pb_iconFont:nil withName:@"\U0000e604" withSize:iconSize withColor:iconColor];
        _deleteIcon.image = img;
    }
    return _deleteIcon;
}

- (UILabel *)deleteBgLab {
    if (!_deleteBgLab) {
        CGFloat iconSize = [self calculateRecordSize] * 0.5;
        UIColor *lineColor = [UIColor pb_colorWithHexString:FLK_AUDIO_LINECOLOR];
        _deleteBgLab = [[UILabel alloc] initWithFrame:CGRectZero];
        _deleteBgLab.backgroundColor = [UIColor whiteColor];
        _deleteBgLab.layer.cornerRadius = iconSize * 0.5;
        _deleteBgLab.layer.masksToBounds = true;
        _deleteBgLab.layer.borderWidth = 1.f;
        _deleteBgLab.layer.borderColor = [lineColor CGColor];
    }
    return _deleteBgLab;
}

- (EZMicrophone *)microphone {
    if (!_microphone) {
        //
        // Create the microphone
        //
        _microphone = [EZMicrophone microphoneWithDelegate:self];
    }
    return _microphone;
}

- (EZRecorder *)audioRecorder {
    if (!_audioRecorder) {
        NSURL *filePath = [self fetchRandomRecordFilePath];
        _audioRecorder = [EZRecorder recorderWithURL:filePath clientFormat:[self.microphone audioStreamBasicDescription] fileType:EZRecorderFileTypeWAV];
    }
    return _audioRecorder;
}

- (NSURL *)fetchRandomRecordFilePath {
    NSString *tmpPath = NSTemporaryDirectory();
    NSTimeInterval interval = [[NSDate date] timeIntervalSince1970];
    NSString *destPath = PBFormat(@"%@/%lf.wav", tmpPath, interval);
    return [NSURL fileURLWithPath:destPath];
}

#pragma mark -- setter --

- (void)setState:(FLKAudioRecState)state {
//    if (state == _state) {
//        return;
//    }
    
    if (state & FLKAudioRecStateNone) {
        //
        self.stateLab.hidden = false;
        self.prepareHUD.hidden = true;
        
        self.audioMeterLeft.hidden = true;
        self.audioMeterRight.hidden = true;
        self.timeLab.hidden = true;
        
        [self.playBgLab.layer removeAllAnimations];
        
    } else if (state & FLKAudioRecStatePreStart) {
        self.stateLab.hidden = true;
        self.prepareHUD.hidden = false;
        
        self.audioMeterLeft.hidden = true;
        self.audioMeterRight.hidden = true;
        self.timeLab.hidden = true;
        
    } else if (state & FLKAudioRecStateRecording) {
        self.stateLab.hidden = true;
        self.prepareHUD.hidden = true;
        
        self.audioMeterLeft.hidden = false;
        self.audioMeterRight.hidden = false;
        self.timeLab.hidden = false;
    }
    _state = state;
    
}

- (void)__initSetupProfile {
    //register font
    [self registerCustomFontWithName:FLK_AUDIO_FONTFILE];
    
    //
    // Setup the AVAudioSession. EZMicrophone will not work properly on iOS
    // if you don't do this!
    //
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error) {
        NSLog(@"Error setting up audio session category: %@", error.localizedDescription);
    }
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"Error setting up audio session active: %@", error.localizedDescription);
    }
    
    //
    // Customizing the audio plot's look
    //
    [self addSubview:self.audioMeterRight];
    [self addSubview:self.audioMeterLeft];
    CGAffineTransform transform = CGAffineTransformMakeRotation(M_PI);
    self.audioMeterLeft.transform = transform;
    [self addSubview:self.timeLab];
    
    //
    // Set up the microphone input UIPickerView items to select
    // between different microphone inputs. Here what we're doing behind the hood
    // is enumerating the available inputs provided by the AVAudioSession.
    //
    self.inputs = [EZAudioDevice inputDevices];
    
    // Start with sensible values
    self.runningSumSquares = 0;
    self.numberSamples = 0;
    
    //setup state lab
    [self addSubview:self.stateLab];
    
    //set prepare info
    [self addSubview:self.prepareHUD];
    self.prepareHUD.backgroundColor = [UIColor pb_randomColor];
    
    //setup play icon
    [self addSubview:self.playBgLab];
    [self addSubview:self.playIcon];
    
    //setup delete icon
    [self addSubview:self.deleteBgLab];
    [self addSubview:self.deleteIcon];
    
    //setup record btn
    [self addSubview:self.recordLab];
   
    
    //setup init mode for state
    [self setState:FLKAudioRecStateNone];
    
}

#pragma mark -- layout --

- (void)layoutSubviews {
    [super layoutSubviews];
    NSLog(@"___%s", __FUNCTION__);
    weakify(self)
    //*
    [self.audioMeterRight mas_makeConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self).offset(PB_CONTENT_MARGIN);
        make.left.equalTo(self.centerX).offset(PB_BOUNDARY_MARGIN);
        make.width.equalTo(@(FLK_AUDIO_METER_MIN_WIDTH));
        make.height.equalTo(@(PB_CUSTOM_LAB_HEIGHT));
    }];
    
    [self.audioMeterLeft mas_makeConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self).offset(PB_CONTENT_MARGIN);
        make.right.equalTo(self.centerX).offset(-PB_BOUNDARY_MARGIN);
        make.width.equalTo(@(FLK_AUDIO_METER_MIN_WIDTH));
        make.height.equalTo(@(PB_CUSTOM_LAB_HEIGHT));
    }];
    
    [self.timeLab mas_makeConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.centerY.equalTo(self.audioMeterLeft);
        make.left.equalTo(self.audioMeterLeft.mas_right);
        make.right.equalTo(self.audioMeterRight.mas_left);
        make.height.equalTo(@(PB_CUSTOM_LAB_HEIGHT));
    }];
    
    
    [self.stateLab mas_makeConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self).offset(PB_CONTENT_MARGIN);
        make.left.right.equalTo(self);
        make.height.equalTo(@(PB_CUSTOM_LAB_HEIGHT));
    }];
    
    //下边语句错误 因为不能在布局中再次获得其bounds
    //CGFloat hudWidth = CGRectGetWidth(self.prepareHUD.bounds);
    CGFloat boundsWidth = CGRectGetWidth(self.bounds);
    [self.prepareHUD mas_makeConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.left.equalTo(self).offset((boundsWidth-self.prepareHUDWidth) * 0.5);
        make.top.equalTo(self).offset(PB_CONTENT_MARGIN);
    }];
    
    CGFloat iconSize = [self calculateRecordSize];
    [self.recordLab mas_makeConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.centerX.equalTo(self);
        make.centerY.equalTo(self);
        make.width.equalTo(@(iconSize));
        make.height.equalTo(@(iconSize));
    }];
    
    [self relayoutPlayAndDeleteFuncIcons];
}

- (void)relayoutPlayAndDeleteFuncIcons {
    CGFloat iconSize = [self calculateRecordSize];
    //*play icon
    CGFloat playBgSize = iconSize * 0.5;
    CGFloat playSize = playBgSize * 0.5;
    CGPoint playCenter = [self fetchPlayZoneCenter];
    CGPoint recCenter = [self fetchRecordZoneCenter];
    BOOL expanded = false;
    if (self.state & FLKAudioRecStateRecording) {
        expanded = true;
    }
    CGFloat radius = playSize * 0.5;
    CGFloat bg_radius = playBgSize * 0.5;
    
    NSLog(@"center:%@===size:%f---expanded:%d--%f", NSStringFromCGPoint(playCenter), playSize, expanded, bg_radius);
    CGFloat outter_topOffset = ((expanded?playCenter.y:recCenter.y)-bg_radius);
    CGFloat outter_marginOffset = ((expanded?playCenter.x:recCenter.x)-bg_radius);
    CGFloat inner_topOffset = ((expanded?playCenter.y:recCenter.y)-radius);
    CGFloat inner_marginOffset = ((expanded?playCenter.x:recCenter.x)-radius);
    NSLog(@"outter top:%f----margin:%f-----%f", outter_topOffset, outter_marginOffset, ((expanded?playCenter.y:recCenter.y)-bg_radius));
    weakify(self)
    [self.playBgLab mas_updateConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self).offset(outter_topOffset);
        make.left.equalTo(self).offset(outter_marginOffset);
        make.size.equalTo(CGSizeMake(playBgSize, playBgSize));
    }];
    [self.playIcon mas_updateConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self).offset(inner_topOffset);
        make.left.equalTo(self).offset(inner_marginOffset);
        make.size.equalTo(CGSizeMake(playSize, playSize));
    }];
    [self.deleteBgLab mas_updateConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self).offset(outter_topOffset);
        make.right.equalTo(self).offset(-outter_marginOffset);
        make.size.equalTo(CGSizeMake(playBgSize, playBgSize));
    }];
    [self.deleteIcon mas_updateConstraints:^(MASConstraintMaker *make) {
        strongify(self)
        make.top.equalTo(self).offset(inner_topOffset);
        make.right.equalTo(self).offset(-inner_marginOffset);
        make.size.equalTo(CGSizeMake(playSize, playSize));
    }];
    //*/
    [self setNeedsDisplay];
}

- (void)handleTimerFired {
    // Calculate this period's value and push it back on the main thread
    double mean = self.runningSumSquares / self.numberSamples;
    double rms  = sqrt(mean);
    
    // Convert the value to a dB (logarithmic) scale
    float dBValue = 10 * log10(rms);
    // 阶跃判断
    if (isnan(dBValue)) {
        dBValue = self.lastSample;
    }
    self.lastSample = dBValue;
    //NSLog(@"average meter :%lff", dBValue);
    [self.audioMeterRight updateMeter:[NSNumber numberWithFloat:ABS(dBValue)]];
    [self.audioMeterLeft updateMeter:[NSNumber numberWithFloat:ABS(dBValue)]];
    // Reset for the next period
    self.runningSumSquares = 0;
    self.numberSamples = 0;
    
    self.sumSamples++;
    [self updateAudioRecordTime];
}

- (void)updateAudioRecordTime {
    self.timeLab.text = PBFormat(@"%zd\"", self.sumSamples / 10);
}

#pragma mark -- calculate some area size --

- (CGFloat)distanceFromPoint:(CGPoint)starPoint to:(CGPoint)endPoint {
    CGFloat deltaX = endPoint.x - starPoint.x;
    CGFloat deltaY = endPoint.y - starPoint.y;
    return sqrt(deltaX*deltaX + deltaY*deltaY );
}

- (CGFloat)calculateRecordSize {
    return FLK_AUDIO_REC_HEIGHT - PB_CONTENT_MARGIN*4 - PB_CUSTOM_LAB_HEIGHT *4;
}

/**
 中心按钮center
 */
- (CGPoint)fetchRecordZoneCenter {
    return self.recordLab.center;
}

- (CGPoint)fetchPlayZoneCenter {
    CGPoint center = [self fetchRecordZoneCenter];
    CGFloat centerRadius = [self calculateRecordSize] * 0.5;
    CGFloat pt_x = centerRadius;
    CGFloat pt_y = center.y - centerRadius * 0.5;
    return CGPointMake(pt_x, pt_y);
}

- (CGPoint)fetchDeleteZoneCenter {
    CGFloat width = CGRectGetWidth(self.bounds);
    CGPoint center = [self fetchRecordZoneCenter];
    CGFloat centerRadius = [self calculateRecordSize] * 0.5;
    CGFloat pt_x = width - centerRadius;
    CGFloat pt_y = center.y - centerRadius * 0.5;
    return CGPointMake(pt_x, pt_y);
}

- (CGPoint)convertPointFromTouch:(NSSet<UITouch *> *)touches {
    if (PBIsEmpty(touches)) {
        return CGPointZero;
    }
    
    return [[touches anyObject] locationInView:self];
}

- (BOOL)whetherRecordInnerInclude4Touches:(NSSet <UITouch *> *)touch {
    CGPoint touchPoint = [self convertPointFromTouch:touch];
    if (CGPointEqualToPoint(touchPoint, CGPointZero)) {
        return false;
    }
    CGFloat size = [self calculateRecordSize];
    CGFloat radius = size * 0.5;
    CGPoint center = [self fetchRecordZoneCenter];
    CGFloat distance = [self distanceFromPoint:touchPoint to:center];
    return distance < radius;
}

#pragma mark == User InterfaseAction ==

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    
    BOOL whetherContain = [self whetherRecordInnerInclude4Touches:touches];
    [self animateRecordLayer2RecState:whetherContain];
    
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    [self didFingerMovedWithTouch:touches];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self animateRecordLayer2RecState:false];
    /*
    NSTimeInterval duration = self.audioRecorder.duration;
    if (duration < 1.f) {
        self.userInteractionEnabled = false;
        showHUDWithInfo(@"录音时间太短了！", ^(BOOL dismiss) {
            self.userInteractionEnabled = true;
        });
    }
    //*/
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self animateRecordLayer2RecState:false];
}


#pragma mark -- animate with layers --

- (void)animateRecordLayer2RecState:(BOOL)rec {
    UIColor *bgColor;
    if (rec) {
        CGFloat animteDuration = (PBANIMATE_DURATION * 2);
        NSValue *value1 = @1;
        NSValue *value2 = @1.12;
        NSValue *value3 = @1;
        NSNumber *time1 = @0;
        NSNumber *time2 = @(animteDuration*0.5);
        NSNumber *time3 = @(animteDuration);
        CAKeyframeAnimation *keyAnimate = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        keyAnimate.values = @[value1, value2, value3];
        keyAnimate.keyTimes = @[time1, time2, time3];
        keyAnimate.duration = animteDuration;
        keyAnimate.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        keyAnimate.removedOnCompletion = true;
        keyAnimate.delegate = self;
        [self.recordLab.layer addAnimation:keyAnimate forKey:@"animate.scale"];
        bgColor = [UIColor pb_colorWithHexString:@"#1180CD"];
    } else {
        bgColor = [UIColor pb_colorWithHexString:@"#1CA4E8"];
    }
    [self setState:rec?FLKAudioRecStatePreStart:FLKAudioRecStateNone];
    self.recordLab.backgroundColor = bgColor;
    [self relayoutPlayAndDeleteFuncIcons];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag {
    //动画结束视为录音的真正开始 前(PBANIMATE_DURATION * 2)秒为准备阶段
    if (self.state == FLKAudioRecStatePreStart) {
        [self startFetchingAudioStream];
    }
}

- (BOOL)whetherPoint:(CGPoint)pt containedInArcForCenter:(CGPoint)center andRadius:(CGFloat)radius {
    if (CGPointEqualToPoint(pt, CGPointZero)) {
        return false;
    }
    CGFloat distance = [self distanceFromPoint:pt to:center];
    return distance < radius;
}

- (void)didFingerMovedWithTouch:(NSSet<UITouch *> *)touchs {
    
    CGPoint curPt = [self convertPointFromTouch:touchs];
    [self calculateMoveStepPoint:curPt callBackScale:^(CGFloat s) {
        if (s > 0 && s <= 1) {
            PBMAIN(^{
                CGFloat animteDuration = 0.1;
                //NSValue *value1 = @1;
                //NSValue *value2 = @1.12;
                NSValue *value3 = @(1+s);
                //NSNumber *time1 = @0;
                //NSNumber *time2 = @(animteDuration*0.5);
                NSNumber *time3 = @(animteDuration);
                CAKeyframeAnimation *keyAnimate = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
                keyAnimate.values = @[/*value1, value2,*/ value3];
                keyAnimate.keyTimes = @[/*time1, time2,*/ time3];
                keyAnimate.duration = animteDuration;
                keyAnimate.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                keyAnimate.removedOnCompletion = false;
                keyAnimate.delegate = self;
                //[self.playBgLab.layer addAnimation:keyAnimate forKey:@"animate.scale"];
                
                CGAffineTransform scaleTransform = CGAffineTransformMakeScale(1 + s, 1 + s);
                [UIView animateWithDuration:animteDuration animations:^{
                    self.playBgLab.transform = scaleTransform;
                }];
            });
        }
    }];
}

- (void)calculateMoveStepPoint:(CGPoint)pt callBackScale:(void(^)(CGFloat s))scaleBlock {
    PBBACK(^{
        CGPoint curPt = pt;
        CGPoint rec_center = [self fetchRecordZoneCenter];
        CGPoint playPt = [self fetchPlayZoneCenter];
        CGFloat iconSize = [self calculateRecordSize];
        
        //方向不对也不响应
        if (curPt.y < playPt.y || curPt.y > rec_center.y) {
            NSLog(@"方向不对");
            return;
        }
        
        //已滑动距离
        CGFloat slide_distance = [self distanceFromPoint:curPt to:rec_center];
        if (slide_distance < iconSize * 0.5) {
            //还没有滑出录音圆圈
            NSLog(@"还未滑出大圆...");
            return;
        }
        
        
        //*play icon
        CGFloat playBgSize = iconSize * 0.5;
        CGFloat trans_scale = 1.5;
        CGFloat abs_distance = [self distanceFromPoint:playPt to:rec_center];
        
        CGFloat avaliable_distance = abs_distance - playBgSize * 0.5 * trans_scale - iconSize * 0.5;
        
        //当前距离play center距离比
        CGFloat scale = (slide_distance - iconSize * 0.5)/avaliable_distance;
        NSLog(@"scale is :%f", scale);
        if (scaleBlock) {
            scaleBlock(scale);
        }
    });
}

/**
 真实开始录音
 */
- (void)startFetchingAudioStream {
    [self setState:FLKAudioRecStateRecording];
    [self relayoutPlayAndDeleteFuncIcons];
    //
    // Start the microphone
    //
    // Start with sensible values
    self.runningSumSquares = 0;
    self.numberSamples = 0;
    self.sumSamples = 0;
    [self.displayLink setPaused:false];
    [self.microphone startFetchingAudio];
}

#pragma mark -- Discrete the audio signal

- (void)discreteAudioMeters {
    //self.microphone.
}

#pragma mark - EZMicrophoneDelegate
//
// Note that any callback that provides streamed audio data (like streaming
// microphone input) happens on a separate audio thread that should not be
// blocked. When we feed audio data into any of the UI components we need to
// explicity create a GCD block on the main thread to properly get the UI
// to work.
//
- (void)microphone:(EZMicrophone *)microphone hasAudioReceived:(float **)buffer withBufferSize:(UInt32)bufferSize withNumberOfChannels:(UInt32)numberOfChannels {
    //
    // Getting audio data as an array of float buffer arrays. What does that mean?
    // Because the audio is coming in as a stereo signal the data is split into
    // a left and right channel. So buffer[0] corresponds to the float* data
    // for the left channel while buffer[1] corresponds to the float* data
    // for the right channel.
    //
    //NSLog(@"bufferSize:%tu", bufferSize);
    //just the first channel buffer
    // We'll just use the first channel
    float *dataPoints = buffer[0];
    // Calculate sum of squares
    double sumSquares = 0;
    float *currentDP = dataPoints;
    for (UInt32 i=0; i<bufferSize; i++) {
        sumSquares += *currentDP * *currentDP;
        currentDP++;
    }
    self.runningSumSquares += sumSquares;
    self.numberSamples += bufferSize;
    
    /*
     // See the Thread Safety warning above, but in a nutshell these callbacks
     // happen on a separate audio thread. We wrap any UI updating in a GCD block
     // on the main thread to avoid blocking that audio flow.
     //
     __weak typeof (self) weakSelf = self;
     dispatch_async(dispatch_get_main_queue(), ^{
     //
     // All the audio plot needs is the buffer data (float*) and the size.
     // Internally the audio plot will handle all the drawing related code,
     // history management, and freeing its own resources.
     // Hence, one badass line of code gets you a pretty plot :)
     //
     [weakSelf.audioPlot updateBuffer:buffer[0] withBufferSize:bufferSize];
     });
     //*/
}

- (void)microphone:(EZMicrophone *)microphone hasAudioStreamBasicDescription:(AudioStreamBasicDescription)audioStreamBasicDescription {
    //
    // The AudioStreamBasicDescription of the microphone stream. This is useful
    // when configuring the EZRecorder or telling another component what
    // audio format type to expect.
    //
    [EZAudioUtilities printASBD:audioStreamBasicDescription];
}

//------------------------------------------------------------------------------

- (void)microphone:(EZMicrophone *)microphone
     hasBufferList:(AudioBufferList *)bufferList
    withBufferSize:(UInt32)bufferSize
withNumberOfChannels:(UInt32)numberOfChannels {
    //
    // Getting audio data as a buffer list that can be directly fed into the
    // EZRecorder or EZOutput. Say whattt...
    //
}

//------------------------------------------------------------------------------

- (void)microphone:(EZMicrophone *)microphone changedDevice:(EZAudioDevice *)device {
    NSLog(@"Microphone changed device: %@", device.name);
}

//*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
    
    [[UIColor whiteColor] setFill];
    UIRectFill(rect);
    
    if (self.state & FLKAudioRecStateRecording) {
        CGPoint center = [self fetchRecordZoneCenter];
        CGPoint leftPt = [self fetchPlayZoneCenter];
        CGPoint rightPt = [self fetchDeleteZoneCenter];
        //find circle infos
        CircleData info = findCircle(center, leftPt, rightPt);
        //calculate angle
        CGFloat q1 = ABS(info.center.y - leftPt.y);
        CGFloat q2 = ABS((rightPt.x-leftPt.x)*0.5);
        CGFloat angle_start = atan(q1 / q2);
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:info.center radius:info.radius startAngle:angle_start endAngle:M_PI-angle_start clockwise:true];
        UIColor *lineColor = [UIColor pb_colorWithHexString:FLK_AUDIO_LINECOLOR];
        [lineColor setStroke];
        [path stroke];
    }
    
}

//*/

@end
