//
//  FLKAudioMeter.m
//  AudioKit
//
//  Created by nanhujiaju on 2017/3/7.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import "FLKAudioMeter.h"

static CGFloat const FLK_AUDIO_METER_SIZEWIDTH                      =   1.5f;
static CGFloat const FLK_AUDIO_METER_ITEMCAP                        =   FLK_AUDIO_METER_SIZEWIDTH*1.5;
static unsigned int FLK_AUDIO_METER_MINNUM                          =   10;//最少显示item个数，要求：size_width*min_num <= self.width
CGFloat const FLK_AUDIO_METER_MIN_WIDTH                             =   ((FLK_AUDIO_METER_SIZEWIDTH+FLK_AUDIO_METER_ITEMCAP)*11);

typedef NS_ENUM(NSUInteger, FLKAudioMeterLevel) {
    FLKAudioMeterLevelLow                       =   1   <<  0,//0.15
    FLKAudioMeterLevelPreMid                    =   1   <<  1,//0.25
    FLKAudioMeterLevelMid                       =   1   <<  2,//0.45
    FLKAudioMeterLevelPreHigh                   =   1   <<  3,//0.75
    FLKAudioMeterLevelHigh                      =   1   <<  4,//1.0
};

@interface FLKMeterItem : NSObject

/**
 generate meter item

 @param value of meter 0~40
 @return the item
 */
+ (FLKMeterItem *)itemWithMeterValue:(NSNumber *)value;

@property (nonatomic, assign, readonly, getter=getLevel) FLKAudioMeterLevel level;

@property (nonatomic, assign, readonly, getter=getScale) CGFloat scale;

- (void)changeMeter2Level:(FLKAudioMeterLevel)level;

@end

@interface FLKMeterItem ()

@property (nonatomic, strong) NSNumber *value;

@end

@implementation FLKMeterItem

+ (FLKMeterItem *)itemWithMeterValue:(NSNumber *)value {
    return [[FLKMeterItem alloc] initWithMeterValue:value];
}

- (instancetype)initWithMeterValue:(NSNumber *)value {
    self = [super init];
    if (self) {
        self.value = value;
    }
    return self;
}
/**
 分贝分档次
 25～40      -> width*0.15
 15～25      -> width*0.25
 10～15      -> width*0.45
 5～10       -> width*0.75
 0～5        -> width*1.0
 */
static u_int16_t const FLK_AUDIO_DB_S1                      =   25;
static u_int16_t const FLK_AUDIO_DB_S2                      =   15;
static u_int16_t const FLK_AUDIO_DB_S3                      =   10;
static u_int16_t const FLK_AUDIO_DB_S4                      =   5;

static CGFloat const FLK_AUDIO_SCALE1                       =   0.15;
static CGFloat const FLK_AUDIO_SCALE2                       =   0.25;
static CGFloat const FLK_AUDIO_SCALE3                       =   0.45;
static CGFloat const FLK_AUDIO_SCALE4                       =   0.75;
- (FLKAudioMeterLevel)convertMeter2Level:(NSNumber *)meter {
    FLKAudioMeterLevel level;
    CGFloat mValue = [meter floatValue];
    if (mValue > FLK_AUDIO_DB_S1 /*&& meter <= 40*/) {
        level = FLKAudioMeterLevelLow;
    } else if (mValue > FLK_AUDIO_DB_S2 && mValue <= FLK_AUDIO_DB_S1) {
        level = FLKAudioMeterLevelPreMid;
    } else if (mValue > FLK_AUDIO_DB_S3 && mValue <= FLK_AUDIO_DB_S2) {
        level = FLKAudioMeterLevelMid;
    } else if (mValue > FLK_AUDIO_DB_S4 && mValue <= FLK_AUDIO_DB_S3) {
        level = FLKAudioMeterLevelPreHigh;
    } else if (/*meter > 0 &&*/ mValue <= FLK_AUDIO_DB_S4) {
        level = FLKAudioMeterLevelHigh;
    }
    return level;
}

- (FLKAudioMeterLevel)getLevel {
    return [self convertMeter2Level:self.value];
}

- (CGFloat)getScale {
    FLKAudioMeterLevel level = [self convertMeter2Level:self.value];
    CGFloat m_scale = 0;
    if (level & FLKAudioMeterLevelLow) {
        m_scale = FLK_AUDIO_SCALE1;
    } else if (level & FLKAudioMeterLevelPreMid) {
        m_scale = FLK_AUDIO_SCALE2;
    } else if (level & FLKAudioMeterLevelMid) {
        m_scale = FLK_AUDIO_SCALE3;
    } else if (level & FLKAudioMeterLevelPreHigh) {
        m_scale = FLK_AUDIO_SCALE4;
    } else if (level & FLKAudioMeterLevelHigh) {
        m_scale = 1.f;
    }
    return m_scale;
}

- (void)changeMeter2Level:(FLKAudioMeterLevel)level {
    CGFloat value = 40;
    if (level & FLKAudioMeterLevelHigh) {
        value = FLK_AUDIO_DB_S4;
    } else if (level & FLKAudioMeterLevelPreHigh) {
        value = FLK_AUDIO_DB_S3;
    } else if (level & FLKAudioMeterLevelMid) {
        value = FLK_AUDIO_DB_S2;
    } else if (level & FLKAudioMeterLevelPreMid) {
        value = FLK_AUDIO_DB_S1;
    }
    self.value = [NSNumber numberWithFloat:value];
}

@end

@interface FLKAudioMeter ()

/**
 audio meter level sample sets
 */
@property (nonatomic, strong) NSMutableArray <FLKMeterItem *>*meterSamples;

@property (nonatomic, assign) NSUInteger meterNums;

@property (nonatomic, assign) CGFloat meterItemHeight;

//统计静音
@property (nonatomic, assign) BOOL whetherSilenceStart;
@property (nonatomic, assign) u_int16_t silenceSampleNum;

@end

@implementation FLKAudioMeter

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self __initSetupMeter];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self __initSetupMeter];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self __initSetupMeter];
}

- (u_int16_t)randomFrom:(u_int16_t)min withMax:(u_int16_t)max {
    if (min >= max) {
        return 0;
    }
    return arc4random()%(max - min) + min;
}

- (BOOL)whetherSkip {
    u_int16_t random = [self randomFrom:0 withMax:10];
    return random%2 == 0;
}

#pragma mark -- init setup vars --

- (void)__initSetupMeter {
    
}

#pragma mark -- operate source sets --

- (NSMutableArray <FLKMeterItem *>*)meterSamples {
    if (!_meterSamples) {
        CGFloat maxWidth = CGRectGetWidth(self.bounds);
        CGFloat maxHeight = CGRectGetHeight(self.bounds);
        CGFloat itemWidth = FLK_AUDIO_METER_SIZEWIDTH+FLK_AUDIO_METER_ITEMCAP;
        NSAssert(FLK_AUDIO_METER_MINNUM*itemWidth <= maxWidth, @"meter bounds's width size was too short!");
        NSUInteger nums = floor(maxWidth/itemWidth);
        self.meterNums = nums;
        //NSLog(@"meter max num :%tu", nums);
        self.meterItemHeight = maxHeight;
        _meterSamples = [NSMutableArray arrayWithCapacity:nums];
        //TODO:generate random
//        for (int i = 0; i < nums; i ++) {
//            u_int16_t random = [self randomFrom:0 withMax:40];
//            [_meterSamples addObject:@(random)];
//        }
    }
    return _meterSamples;
}

- (void)removeLastSample {
    NSUInteger counts = self.meterSamples.count;
    if (counts <= self.meterNums) {
        return;
    }
    @synchronized (self.meterSamples) {
        [self.meterSamples removeLastObject];
    }
}

#pragma mark -- update meter source --

- (void)updateMeter:(NSNumber *)meter {
    //NSLog(@"add value meter :%@", meter);
    FLKMeterItem *item = [FLKMeterItem itemWithMeterValue:meter];
    //检测静音 超过3次则发射脉冲
    if ([item getLevel] & FLKAudioMeterLevelLow) {
        if (!self.whetherSilenceStart) {
            self.whetherSilenceStart = true;
        }
        if (self.silenceSampleNum > 3) {
            [item changeMeter2Level:FLKAudioMeterLevelPreMid];
            self.silenceSampleNum = 0;
        } else {
            self.silenceSampleNum++;
        }
    } else {
        self.whetherSilenceStart = false;
        self.silenceSampleNum = 0;
    }
    
    
    [self.meterSamples insertObject:item atIndex:0];
    
    [self removeLastSample];
    [self setNeedsDisplay];
}

- (u_int16_t)fetchMeter4Index:(u_int16_t)idx withSource:(NSArray *)array {
    NSUInteger counts = array.count;
    if (idx >= counts) {
        return 0;
    }
    NSNumber *meter = array[idx];
    return [meter unsignedIntValue];
}

- (CGFloat)fetchMeterScale4Index:(u_int16_t)idx {
    NSUInteger sampleNums = [self.meterSamples count];
    FLKMeterItem *meter;
    if (idx < sampleNums) {
        meter = self.meterSamples[idx];
    } else {
        CGFloat value = [self randomFrom:0 withMax:40];
        meter = [FLKMeterItem itemWithMeterValue:[NSNumber numberWithFloat:value]];
    }
    return [meter getScale];
}

//*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
    
    [[UIColor whiteColor] set];
    UIRectFill(self.bounds);
    
    //draw the item
    [[UIColor colorWithRed:249/255.f green:78/255.f blue:0 alpha:1.f] set];
    u_int16_t loops = self.meterNums;
    //NSUInteger sampleNums = [self.meterSamples count];
    
    for (u_int16_t i = 0; i < loops; i ++) {
        //NSLog(@"meter:%@", meter);
        CGFloat m_scale = [self fetchMeterScale4Index:i];
        
        CGFloat x = (FLK_AUDIO_METER_SIZEWIDTH+FLK_AUDIO_METER_ITEMCAP)*i;
        CGFloat y = self.meterItemHeight*0.5*(1-m_scale);
        CGFloat m_half_height = self.meterItemHeight*0.5*m_scale;
        CGRect m_bounds = CGRectMake(x, y, FLK_AUDIO_METER_SIZEWIDTH, m_half_height*2);
        UIRectFill(m_bounds);
    }
    
}
//*/

@end
