//
//  SampleBuffer.swift
//  AudioRender
//
//  Created by Andrew Coad on 06/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import Accelerate

class SampleBuffer: NSObject {
    
    private let _sBuff:UnsafeMutablePointer<Float>?
    private var _points:Array<CGPoint> = []
    private var _capacity:AVAudioFrameCount = 0
    private var _length:AVAudioFrameCount = 0
    private var _extrema:Float = 0.0
    private var _peak:Float = 1.0
    
    var floatData:UnsafeMutablePointer<Float>? {
        get { return _sBuff }
    }
    
    var frameLength:AVAudioFrameCount {
        get { return _length }
        set { _length = newValue }
    }
    
    var frameCapacity:AVAudioFrameCount {
        get { return _capacity }
    }
    
    var peak:Float {
        get { return _peak }
        set { _peak = newValue }
    }
    
    var points:Array<CGPoint> {
        get { return _points }
        set { _points = newValue }
    }
    
    init?(capacity:AVAudioFrameCount) {
        _sBuff = UnsafeMutablePointer.allocate(capacity: Int(capacity))
        if _sBuff == nil {
            return nil
        }
        _capacity = capacity
        _length = 0
    }
    
    func append(source:UnsafePointer<Float>, length:AVAudioFrameCount) {
        guard let sb = _sBuff else { return }
        let xferCount = (_length + length > _capacity) ? (_capacity - _length) : length
        for idx in 0..<Int(xferCount) {
            sb[idx] = source[idx]
        }
        _length += xferCount
    }
    
    func updatePeak() -> Float {

        if let sb = _sBuff {
            vDSP_maxv(sb, 1, &_extrema, vDSP_Length(_length))
            _peak = _extrema != 0.0 ? _extrema : 1.0
            return _peak
        }
        
        return 1.0
    }
    
    deinit {
        if _sBuff != nil { _sBuff?.deallocate() }
    }
}
