//
//  Extensions.swift
//  AudioRender
//
//  Created by Andrew Coad on 17/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import Foundation
import UIKit

//
// UIColor class extensions
// Provides abillity to initialise a UIColor object using hex #hhhhhh format value
//
extension UIColor {
    
    convenience init(rgb: Int, alpha: Float) {
        self.init(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: CGFloat(alpha))
    }
    
}

//
// CGAffineTransform extensions
//
extension CGAffineTransform {
    
    init(offsetX:CGFloat, offsetY:CGFloat, scaleX:CGFloat, scaleY:CGFloat) {
        self.init(scaleX: scaleX, y: scaleY)
        self.tx = offsetX
        self.ty = offsetY
    }
    
}

@discardableResult
func measure<A>(name: String = "", _ block: () -> A) -> A {
    let startTime = CACurrentMediaTime()
    let result = block()
    let timeElapsed = CACurrentMediaTime() - startTime
    print("Duration: \(name) - \(timeElapsed)")
    return result
}

@discardableResult
func timing<T>(index:Int, key:String, comment:String, stats:Statistics, _ block: () -> T) -> T {
    let startTime = CACurrentMediaTime()
    let result = block()
    let endTime = CACurrentMediaTime()
    stats.setTimeParameter(index: index, key: key, timing: (comment: comment, start: startTime, end: endTime))
    return result
}
