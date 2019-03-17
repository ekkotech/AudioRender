//
//  CGPathInjector.h
//  AudioRender
//
//  Created by Andrew Coad on 16/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

#ifndef CGPathInjector_h
#define CGPathInjector_h

NS_ASSUME_NONNULL_BEGIN

@interface CGPathInjector : NSObject

+(void)injectPath:(CGMutablePathRef)path points:(CGPoint*)points length:(NSInteger)length;

@end

NS_ASSUME_NONNULL_END

#endif /* CGPathInjector_h */
