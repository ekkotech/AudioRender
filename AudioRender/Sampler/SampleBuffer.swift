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
    
    private let _fsd:UnsafePointer<UnsafeMutablePointer<Float>>?
    private var _fData:UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private var _points:Array<CGPoint> = []
    private var _capacity:AVAudioFrameCount = 0
    private var _peak:Float = 1.0

    public let frameLength = AtomicUInt32(0)

    var floatSampleData:UnsafePointer<UnsafeMutablePointer<Float>>? {
        get { return _fsd }
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
        _fData = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        _fData[0] = UnsafeMutablePointer<Float>.allocate(capacity: Int(capacity))
        _fData[1] = UnsafeMutablePointer<Float>.allocate(capacity: Int(capacity))
        _fsd = UnsafePointer(_fData)
        
        _capacity = capacity
    }
    
    deinit {
        _fData[0].deallocate()
        _fData[1].deallocate()
        _fData.deallocate()
    }
}

class AtomicUInt32 {
    private let _atomQ = DispatchQueue(label: "aq")
    private let _sema = DispatchSemaphore(value: 1)
    private var _value:UInt32 = 0
    
    init(_ newValue:UInt32) {
        self._value = newValue
    }
    
    var value:UInt32 {
        get {
            return _value
        }
    }
    
    func mutate(to newValue:UInt32) {
        _sema.wait()
        _value = newValue
        _sema.signal()
//        _atomQ.sync {
//            _value = newValue
//        }
    }
    
    func increment(by newValue:UInt32) {
//        let start = CACurrentMediaTime()
        _sema.wait()
//        print("In sema")
        _value += newValue
        _sema.signal()
//        print("Sema done: \(CACurrentMediaTime() - start)")
//        _atomQ.sync {
//            _value += newValue
//        }
    }
}

