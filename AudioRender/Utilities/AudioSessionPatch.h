//
//  AudioSessionPatch.h
//  AudioRender
//
//  Created by Andrew Coad on 08/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

#ifndef AudioSessionPatch_h
#define AudioSessionPatch_h

// AVAudioSessionPatch.h

@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

@interface AVAudioSessionPatch : NSObject

+ (BOOL)setSession:(AVAudioSession *)session category:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(__autoreleasing NSError **)outError;

@end

NS_ASSUME_NONNULL_END

#endif /* AudioSessionPatch_h */
