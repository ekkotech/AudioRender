//
//  CGPathInjector.m
//  AudioRender
//
//  Created by Andrew Coad on 16/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#import "CGPathInjector.h"

@implementation CGPathInjector

+(void)injectPath:(CGMutablePathRef)path points:(CGPoint*)points length:(NSInteger)length {
    
    if (length > 0) {
        CGPathAddLines(path, NULL, points, length);
    }
}

@end
