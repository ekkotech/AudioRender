//
//  AudioSessionPatch.m
//  AudioRender
//
//  Created by Andrew Coad on 08/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

#import <Foundation/Foundation.h>

// AVAudioSessionPatch.m

#import "AudioSessionPatch.h"

@implementation AVAudioSessionPatch

+ (BOOL)setSession:(AVAudioSession *)session category:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(__autoreleasing NSError **)outError {
    return [session setCategory:category withOptions:options error:outError];
}

@end
