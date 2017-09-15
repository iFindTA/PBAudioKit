//
//  FLKAudioMeter.h
//  AudioKit
//
//  Created by nanhujiaju on 2017/3/7.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import <FLKBaseClasses/FLKBaseView.h>

@interface FLKAudioMeter : FLKBaseView

/**
 update meter for audio

 @param meter the value of meter
 */
- (void)updateMeter:(NSNumber *)meter;

@end

FOUNDATION_EXTERN CGFloat const FLK_AUDIO_METER_MIN_WIDTH;
