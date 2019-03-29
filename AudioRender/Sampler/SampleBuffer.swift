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
    private let _fsd:UnsafePointer<UnsafeMutablePointer<Float>>?
    private var _fData:UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private var _points:Array<CGPoint> = []
    private var _capacity:AVAudioFrameCount = 0
    private var _extrema:Float = 0.0
    private var _peak:Float = 1.0

    public let frameLength = AtomicUInt32(0)

    var floatData:UnsafeMutablePointer<Float>? {
        get { return _sBuff }
    }
    
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
        _sBuff = UnsafeMutablePointer.allocate(capacity: Int(capacity))
        _fData = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        _fData[0] = UnsafeMutablePointer<Float>.allocate(capacity: Int(capacity))
        _fData[1] = UnsafeMutablePointer<Float>.allocate(capacity: Int(capacity))
        _fsd = UnsafePointer(_fData)
        
        if _sBuff == nil {
            return nil
        }
        _capacity = capacity
    }
    
    func updatePeak() -> Float {

        if let sb = _sBuff {
            vDSP_maxv(sb, 1, &_extrema, vDSP_Length(frameLength.value))
            _peak = _extrema != 0.0 ? _extrema : 1.0
            return _peak
        }
        
        return 1.0
    }
    
    deinit {
        if _sBuff != nil { _sBuff?.deallocate() }
    }
}

class AtomicUInt32 {
    private let _atomQ = DispatchQueue(label: "aq")
    private var _value:UInt32 = 0
//    private let lock = ReadWriteLock()
    
    init(_ newValue:UInt32) {
        self._value = newValue
    }
    
    var value:UInt32 {
        get {
            return _value
        }
    }
    
    func mutate(to newValue:UInt32) {
        _atomQ.sync {
            _value = newValue
        }
    }
    
    func increment(by newValue:UInt32) {
        _atomQ.sync {
            _value = _value + newValue
        }
    }
}

//final class ReadWriteLock {
//    private var rwlock: pthread_rwlock_t = {
//        var rwlock = pthread_rwlock_t()
//        pthread_rwlock_init(&rwlock, nil)
//        return rwlock
//    }()
//
//    func writeLock() {
//        pthread_rwlock_wrlock(&rwlock)
//    }
//
//    func readLock() {
//        pthread_rwlock_rdlock(&rwlock)
//    }
//
//    func unlock() {
//        pthread_rwlock_unlock(&rwlock)
//    }
//}

