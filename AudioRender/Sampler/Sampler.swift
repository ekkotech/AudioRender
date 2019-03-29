//
//  Sampler.swift
//  AudioRender
//
//  Created by Andrew Coad on 08/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import Foundation
import AVFoundation
import Accelerate

//
// MARK: - Downsample strategies
//
enum DsStrategy:String {
    case maxValue       = "Max Value"
    case minMaxValue    = "Min Max Value"
    case avgValue       = "Average Value"
    case sampleValue    = "Sample Value"
}
let strategy:DsStrategy = .maxValue

//
// MARK: - Accelerate Framework selection
//
let useAccelForDs = true
let useAccelForMerge = true
let useAccelForPeakCalc = true
let useAccelForBuildPoints = true

//
// Multi-reader
//
let useMultiReader                = true
// Make sure that the block size is an integer multiple of default downsample factor
// Ideally, both should be powers of 2
let kBlockSize                  = AVAudioFrameCount(524288)     // 2**19
let kNumReaders                 = 2

class Sampler: NSObject {
    
    private var assetURL:URL? = nil
    private var processingFormat:AVAudioFormat? = nil
    private var audioFile:AVAudioFile? = nil
    private var _peak:Float = 1.0
    private let ripFileGroup:DispatchGroup = DispatchGroup.init()
    private let readerQueue:DispatchQueue = DispatchQueue.init(label: "readerQ", qos: .userInitiated, attributes: .concurrent)
    private let dsConcQueue:DispatchQueue = DispatchQueue.init(label: "dsConQ", qos: .userInitiated, attributes: .concurrent)
    
    //
    private var index:Int = 0       // Just for capturing timing
    
    //
    // MARK: - Public API
    //
    
    var peak:Float {
        get { return _peak}
        set { _peak = newValue != 0.0 ? newValue : 1.0 }
    }
    
    /**
     Initialises a new asset
     
     - Parameter assetURL: the URL for an audio file
     - Parameter processingFormat: the audio format to be used within the application.  If the audio file format differs, conversion(s) will be performed on reading the file into internal PCM buffers
     */
    public func setAsset(assetURL:URL, processingFormat:AVAudioFormat) {
        
        self.audioFile = nil
        self.processingFormat = nil
        
        do {
            try audioFile = AVAudioFile(forReading: assetURL)
            self.assetURL = assetURL
            self.processingFormat = processingFormat
        }
        catch {
            Logger.debug("ERROR: opening audio file for reading")
            assertionFailure()
        }
    }
    
    public func getSamples(initialRender:Bool, startFrame:AVAudioFramePosition, numOutFrames:AVAudioFrameCount, dsFactor:Int, clientRef:Int, completion:@escaping(SampleBuffer)->()) {
        
        guard let aurl = assetURL, let af = audioFile else { return }
        
        index = initialRender ? 0 : 1
        
        let returnSamples:(SampleBuffer?)->() = { sampleBuffer in
            if let sb = sampleBuffer { completion(sb) }
        }

        let thisStartFrame = startFrame >= 0 ? startFrame : 0
        
        if initialRender {
            // For initial rendering of the entire file:
            // If dsFactor == -1, calculate dsFactor from file length and number of desired output frames
            // If numOutputFrames == 0, calculate numOutput frames from file length and dsFactor
            let thisNumReaders = kNumReaders > 0 ? kNumReaders : 1
            var thisDsFactor:Int = 1
            var thisNumOutFrames:AVAudioFrameCount = 1
            
            if dsFactor == kDsFactorUnspecified && numOutFrames > 0 {
                thisNumOutFrames = numOutFrames
                thisDsFactor = Int(UInt32(af.length) / thisNumOutFrames)
            }
            else if dsFactor > 0 && numOutFrames == 0 {
                thisDsFactor = dsFactor
                thisNumOutFrames = UInt32(af.length) / UInt32(dsFactor)
            }
            else {
                Logger.debug("Error: Invalid numOutFrames, dsFactor combination")
                assertionFailure()
                return
            }

            if useMultiReader {
                // Downsample entire file async
                downsampleAsync(assetURL: aurl, assetLength: UInt32(af.length), startFrame: 0, dsFactor: thisDsFactor, numReaders: thisNumReaders, completion: returnSamples)
            }
            else {
                // Downsample entire file sync
                timing(index: index, key: "total", comment: "Ds: \(String(thisDsFactor))", stats: timeStats) {
                    downsampleSync(sourceFile: af, startFrame: 0, numOutFrames: thisNumOutFrames, dsFactor: thisDsFactor, completion: returnSamples)
                }
            }
        }
        else {
            // Downsample file segment sync
            timing(index: index, key: "total", comment: "Ds: \(String(dsFactor))", stats: timeStats) {
                downsampleSync(sourceFile: af, startFrame: thisStartFrame, numOutFrames: numOutFrames, dsFactor: dsFactor, completion: returnSamples)
            }
        }
    }
    
    //
    // MARK: - Downsampling functions
    //
    private func downsampleAsync(assetURL:URL, assetLength:AVAudioFrameCount, startFrame:AVAudioFramePosition, dsFactor:Int, numReaders:Int, completion:@escaping(SampleBuffer?)->()) {
        
        var blockId = 0
        
        let downsample:(_ frameBuffer:AVAudioPCMBuffer, _ dsFactor:Int, _ blockId:Int, _ sampleBuffer:SampleBuffer)->() = { (fb, dsFactor, blockId, sb) in
            guard let fcd = fb.floatChannelData, /*let fd = sb.floatData,*/ let fsd = sb.floatSampleData else { return }

            let nominalOutSamples = Int(fb.frameCapacity) / Int(dsFactor)
            let thisOutSamples = Int(fb.frameLength) / Int(dsFactor)
            let outOffset:Int = nominalOutSamples * blockId

            // Downsample buffer
            for idx in 0..<thisOutSamples {
                self.downsample(frameBuffer: fb, sampleBuffer: sb, dsFactor: dsFactor, outOffset: outOffset)
            }
            
            // Adjust number of valid frames in sample buffer
            sb.frameLength.increment(by: AVAudioFrameCount(thisOutSamples))   // Atomic
            
            // Merge channels and accumulate in sample buffer (no merge for minMax downsampling)
            if strategy != .minMaxValue {
                var avg:Float = 0.5
                var invert:Float = -1.0
                vDSP_vasm(fsd[0] + outOffset, 1, fsd[1] + outOffset, 1, &avg, fsd[0] + outOffset, 1, vDSP_Length(thisOutSamples))
                vDSP_vsmul(fsd[0] + outOffset, 1, &invert, fsd[1] + outOffset, 1, vDSP_Length(thisOutSamples))
            }
        }
        
        let readFile:(_ assetURL: URL, _ pFormat: AVAudioFormat, _ sourceLength: AVAudioFrameCount, _ dsFactor: Int, _ blockSize: AVAudioFrameCount, _ startBlock: Int, _ numBlocks: Int, _ outBuffer: SampleBuffer)->() = {audioFile, pFormat, sourceLength, dsFactor, blockSize, startBlock, numBlocks, outBuffer in
            
            do {
                let audioFile = try AVAudioFile(forReading: assetURL)
                audioFile.framePosition = Int64(blockSize * UInt32(startBlock))
                for idx in 0..<numBlocks {
                    if let fb = AVAudioPCMBuffer.init(pcmFormat: pFormat, frameCapacity: blockSize) {
                        do {
                            try audioFile.read(into: fb, frameCount: blockSize)
                            submitDownsample(fb, dsFactor, startBlock + idx, outBuffer)
                            blockId += 1
                        }
                        catch {
                            Logger.debug("Error reading audio file on thread")
                            assertionFailure()
                        }
                    }
                }
            }
            catch {
                Logger.debug("Error opening audio file on thread")
                assertionFailure()
            }
        }
        
        
        
        func submitReadFile(assetURL:URL, pFormat: AVAudioFormat, sourceLength: AVAudioFrameCount, dsFactor: Int, blockSize: AVAudioFrameCount, startBlock: Int, numBlocks: Int, outBuffer: SampleBuffer) {
            self.ripFileGroup.enter()
            readerQueue.async {
                readFile(assetURL, pFormat, sourceLength, dsFactor, blockSize, startBlock, numBlocks, outBuffer)
                self.ripFileGroup.leave()
            }
        }
        
        
        func submitDownsample(_ fb:AVAudioPCMBuffer, _ dsFactor:Int, _ blockId:Int, _ sb:SampleBuffer) {
            self.ripFileGroup.enter()
            self.dsConcQueue.async {
                downsample(fb, dsFactor, blockId, sb)
                self.ripFileGroup.leave()
            }
        }
        
        
        let ripStartTime = CACurrentMediaTime()
        
        // Allocate sample buffer large enough for downsampled frames
        let thisOutFrames = assetLength / UInt32(dsFactor)
        let sampleBuffer = SampleBuffer.init(capacity: thisOutFrames)
        if let sb = sampleBuffer { sb.peak = _peak }
        
        guard let pf = processingFormat, let sb = sampleBuffer else { completion(nil); return }
        
        // Round down block size to integer multiple of downsample factor
        let thisBlockSize = kBlockSize - (kBlockSize % UInt32(dsFactor))
        // Round down frames per reader to integer multiple of block size
        var framesPerReader = (assetLength / UInt32(numReaders)) - ((assetLength / UInt32(numReaders)) % thisBlockSize)
        var blocksPerReader =  Int(framesPerReader / thisBlockSize)
        
        for idx in 0..<numReaders {
            let startBlock = Int(blocksPerReader) * idx
            if idx == (numReaders - 1) {
                // Adjust number of frames, number of blocks for the last reader
                framesPerReader = assetLength - (framesPerReader * UInt32(idx))
                blocksPerReader = Int((framesPerReader % thisBlockSize) != 0 ? (framesPerReader / thisBlockSize) + 1 : framesPerReader / thisBlockSize)
            }
            
            submitReadFile(assetURL: assetURL, pFormat: pf, sourceLength: assetLength, dsFactor: dsFactor, blockSize: thisBlockSize, startBlock: startBlock, numBlocks: blocksPerReader, outBuffer: sb)
        }
        
        ripFileGroup.notify(queue: DispatchQueue.main, execute: {
            self.calcPeak(sampleBuffer: sb)
            self.buildPointArray(sampleBuffer: sb)
            print("Async file duration: Ds: \(String(dsFactor)) \(CACurrentMediaTime() - ripStartTime)")
            completion(sb)
        })
        
    }
    
    private func downsampleSync(sourceFile:AVAudioFile, startFrame:AVAudioFramePosition, numOutFrames:AVAudioFrameCount, dsFactor:Int, completion:@escaping(SampleBuffer?)->()) {
        guard let af = audioFile, let pf = processingFormat else { return }
        
        af.framePosition = startFrame
        
        if let fb = AVAudioPCMBuffer.init(pcmFormat: pf, frameCapacity: numOutFrames * UInt32(dsFactor)), let sb = SampleBuffer.init(capacity: numOutFrames) {
            
            sb.peak = _peak
            do {
                let readFileStartTime = CACurrentMediaTime()
                try af.read(into: fb, frameCount: numOutFrames * UInt32(dsFactor))
                timeStats.setTimeParameter(index: index, key: "fileread", timing: (comment: "", start: readFileStartTime, end: CACurrentMediaTime()))
                
                timing(index: index, key: "downsample", comment: "", stats: timeStats) {
                    downsample(frameBuffer: fb, sampleBuffer: sb, dsFactor: dsFactor, outOffset: 0)
                }
                
                // Adjust sample buffer frame length to number of downsampled frames
                sb.frameLength.mutate(to: UInt32(fb.frameLength) / UInt32(dsFactor))

                if strategy != .minMaxValue {   // No merging for min max downsampling
                    timing(index: index, key: "merge", comment: "", stats: timeStats) {
                        merge(sampleBuffer: sb, outOffset: 0, sampleCount: Int(sb.frameLength.value))
                    }
                }
                
                timing(index: index, key: "peakcalc", comment: "sync", stats: timeStats) {
                    calcPeak(sampleBuffer: sb)
                }
                
                timing(index: index, key: "buildpoints", comment: "sync", stats: timeStats) {
                    buildPointArray(sampleBuffer: sb)
                }
                
                completion(sb)
            }
            catch {
                Logger.debug("Error reading audio file on thread")
                assertionFailure()
            }
        }
    }
    
    //
    // MARK: - Support primitives
    //
    private func downsample(frameBuffer:AVAudioPCMBuffer, sampleBuffer:SampleBuffer, dsFactor:Int, outOffset:Int) {
        guard let fcd = frameBuffer.floatChannelData, let fsd = sampleBuffer.floatSampleData else { return }

        switch (strategy, useAccelForDs) {
        case (.maxValue, false):
            var leftMaxValue:Float
            var rightMaxValue:Float
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                leftMaxValue = 0.0
                rightMaxValue = 0.0
                for jdx in 0..<Int(dsFactor) {
                    if abs(fcd[0][(idx * Int(dsFactor)) + jdx]) > leftMaxValue {
                        leftMaxValue = abs(fcd[0][(idx * Int(dsFactor)) + jdx])
                    }
                    if abs(fcd[1][(idx * Int(dsFactor)) + jdx]) > rightMaxValue {
                        rightMaxValue = abs(fcd[1][(idx * Int(dsFactor)) + jdx])
                    }
                }
                fsd[0][idx + outOffset] = leftMaxValue
                fsd[1][idx + outOffset] = rightMaxValue
            }
        case (.maxValue, true):
            //
            // Insert Accelerate downsample code here
            //
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                vDSP_maxmgv(fcd[0] + (idx * Int(dsFactor)), 1, fsd[0] + outOffset + idx, vDSP_Length(dsFactor))
                vDSP_maxmgv(fcd[1] + (idx * Int(dsFactor)), 1, fsd[1] + outOffset + idx, vDSP_Length(dsFactor))
            }
        case (.minMaxValue, false):
            var leftMaxValue:Float
            var rightMinValue:Float
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                leftMaxValue = 0.0
                rightMinValue = 0.0
                for jdx in 0..<Int(dsFactor) {
                    if fcd[0][(idx * Int(dsFactor)) + jdx] > leftMaxValue {
                        leftMaxValue = fcd[0][(idx * Int(dsFactor)) + jdx]
                    }
                    if fcd[1][(idx * Int(dsFactor)) + jdx] < rightMinValue {
                        rightMinValue = fcd[1][(idx * Int(dsFactor)) + jdx]
                    }
                }
                fsd[0][idx + outOffset] = leftMaxValue
                fsd[1][idx + outOffset] = rightMinValue
            }
        case (.minMaxValue, true):
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                vDSP_maxv(fcd[0] + (idx * Int(dsFactor)), 1, fsd[0] + outOffset + idx, vDSP_Length(dsFactor))
                vDSP_minv(fcd[1] + (idx * Int(dsFactor)), 1, fsd[1] + outOffset + idx, vDSP_Length(dsFactor))
            }
        case (.avgValue, false):
            var leftAvgValue:Float
            var rightAvgValue:Float
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                leftAvgValue = 0.0
                rightAvgValue = 0.0
                for jdx in 0..<Int(dsFactor) {
                    leftAvgValue += abs(fcd[0][(idx * Int(dsFactor)) + jdx])
                    rightAvgValue += abs(fcd[1][(idx * Int(dsFactor)) + jdx])
                }
                fsd[0][idx + outOffset] = leftAvgValue / Float(dsFactor)
                fsd[1][idx + outOffset] = rightAvgValue / Float(dsFactor)
            }
        case (.avgValue, true):
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                vDSP_meamgv(fcd[0] + (idx * Int(dsFactor)), 1, fsd[0] + outOffset + idx, vDSP_Length(dsFactor))
                vDSP_meamgv(fcd[1] + (idx * Int(dsFactor)), 1, fsd[1] + outOffset + idx, vDSP_Length(dsFactor))
            }
        case (.sampleValue, false):
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                fsd[0][idx + outOffset] = abs(fcd[0][idx * Int(dsFactor)])
                fsd[1][idx + outOffset] = abs(fcd[1][idx * Int(dsFactor)])
            }
        case (.sampleValue, true):
            for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                vDSP_maxmgv(fcd[0] + (idx * Int(dsFactor)), 1, fsd[0] + outOffset + idx, 1)
                vDSP_maxmgv(fcd[1] + (idx * Int(dsFactor)), 1, fsd[1] + outOffset + idx, 1)
            }
        }
    }
    
    private func merge(sampleBuffer:SampleBuffer, outOffset:Int, sampleCount:Int) {
        guard /*let fcd = frameBuffer.floatChannelData,*/ let fsd = sampleBuffer.floatSampleData else { return }

        switch useAccelForMerge {
        case false:
            for idx in 0..<Int(sampleBuffer.frameLength.value) {
                fsd[0][idx + outOffset] = (fsd[0][idx + outOffset] + fsd[1][idx + outOffset]) / Float(2.0)
                fsd[1][idx + outOffset] = -fsd[0][idx + outOffset]
            }
        case true:
            //
            // Insert Accelerate merge code here
            //
            var avg:Float = 0.5
            var invert:Float = -1.0
            vDSP_vasm(fsd[0] + outOffset, 1, fsd[1] + outOffset, 1, &avg, fsd[0] + outOffset, 1, vDSP_Length(sampleCount))
            vDSP_vsmul(fsd[0] + outOffset, 1, &invert, fsd[1] + outOffset, 1, vDSP_Length(sampleCount))
        }
    }
    
    private func calcPeak(sampleBuffer:SampleBuffer) {
        guard let fsd = sampleBuffer.floatSampleData else { return }
    
        var peakValue = Float(0.0)
        
        switch useAccelForPeakCalc {
        case false:
            for idx in 0..<Int(sampleBuffer.frameLength.value) {
                peakValue = fsd[0][idx] > peakValue ? fsd[0][idx] : peakValue
            }
        case true:
            vDSP_maxv(fsd[0], 1, &peakValue, vDSP_Length(sampleBuffer.frameLength.value))
        }
        
        sampleBuffer.peak = peakValue
        _peak = peakValue
    }
    
    private func buildPointArray(sampleBuffer: SampleBuffer) {
        guard let fsd = sampleBuffer.floatSampleData, sampleBuffer.frameLength.value > 0 else { return }
        
        var ptArray = Array<CGPoint>.init(repeating: CGPoint(x: 0.0, y: 0.0), count: Int(sampleBuffer.frameLength.value) * 2)

        switch useAccelForBuildPoints {
        case false:
            for idx in 0..<Int(sampleBuffer.frameLength.value) {
                ptArray[idx].x = CGFloat(idx)
                ptArray[idx].y = CGFloat(fsd[0][idx])
                ptArray[(ptArray.count - 1) - idx].x = CGFloat(idx)
                ptArray[(ptArray.count - 1) - idx].y = CGFloat(fsd[1][idx])
            }
         case true:
            //
            // Insert Accelerate build point array code here
            //
            ptArray.withUnsafeBufferPointer { buffer in
                guard let bp = buffer.baseAddress else { return }
                
                let doublePtr = UnsafeMutableRawPointer(mutating: bp).bindMemory(to: Double.self, capacity: Int(sampleBuffer.frameLength.value) * 2)
                var startValue:Double = 0.0
                var incrBy:Double = 1.0
                vDSP_vrampD(&startValue, &incrBy, doublePtr, 2, vDSP_Length(sampleBuffer.frameLength.value))
                vDSP_vrampD(&startValue, &incrBy, doublePtr + (Int(sampleBuffer.frameLength.value) * 4) - 2, -2, vDSP_Length(sampleBuffer.frameLength.value))
                vDSP_vspdp(fsd[0], 1, doublePtr + 1, 2, vDSP_Length(sampleBuffer.frameLength.value))
                vDSP_vspdp(fsd[1], 1, doublePtr + (Int(sampleBuffer.frameLength.value) * 4) - 1, -2, vDSP_Length(sampleBuffer.frameLength.value))
            }
        }
        sampleBuffer.points = ptArray
    }
    
}















/*
 // Accelerate downsample code
 for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
 vDSP_maxmgv(fcd[0] + (idx * Int(dsFactor)), 1, fcd[0] + idx, vDSP_Length(dsFactor))
 vDSP_maxmgv(fcd[1] + (idx * Int(dsFactor)), 1, fcd[1] + idx, vDSP_Length(dsFactor))
 }

 
 // Accelerate merge code
 var avg:Float = 0.5
 vDSP_vasm(fcd[0], 1, fcd[1], 1, &avg, fsd, 1, vDSP_Length(frameLength))

 
 // Accelerate build point array code
 ptArray.withUnsafeMutableBufferPointer { buffer in
 guard let bp = buffer.baseAddress else { return }
 
 let doublesPtr = UnsafeMutableRawPointer(bp).bindMemory(to: Double.self, capacity: Int(sampleBuffer.frameLength) * 2)
 var startValue:Double = 0.0
 var incrBy:Double = 1.0
 vDSP_vrampD(&startValue, &incrBy, doublesPtr, 2, vDSP_Length(sampleBuffer.frameLength))
 vDSP_vrampD(&startValue, &incrBy, doublesPtr + (Int(sampleBuffer.frameLength) * 4) - 2, -2, vDSP_Length(sampleBuffer.frameLength))
 vDSP_vspdp(fd, 1, doublesPtr + 1, 2, vDSP_Length(sampleBuffer.frameLength))
 vDSP_vneg(fd, 1, fd, 1, vDSP_Length(sampleBuffer.frameLength))
 vDSP_vspdp(fd, 1, doublesPtr + (Int(sampleBuffer.frameLength) * 4) - 1, -2, vDSP_Length(sampleBuffer.frameLength))
 }

 */
