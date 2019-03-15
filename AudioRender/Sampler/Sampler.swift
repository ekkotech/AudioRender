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
    case avgValue       = "Average Value"
    case sampleValue    = "Sample Value"
}
let strategy:DsStrategy = .maxValue

//
// MARK: - Accelerate Framework selection
//
let useAccel = true

//
// Multi-reader
//
let useMultiReader                = false
// Make sure that the block size is an integer multiple of default downsample factor
// Ideally, both should be powers of 2
let kBlockSize                  = AVAudioFrameCount(524288)     // 2**19
let kNumReaders                 = 2

class Sampler: NSObject {
    
    private var assetURL:URL? = nil
    private var processingFormat:AVAudioFormat? = nil
    private var audioFile:AVAudioFile? = nil
    private var peak:Float = 0.0
    private let ripFileGroup:DispatchGroup = DispatchGroup.init()
    private let readerQueue:DispatchQueue = DispatchQueue.init(label: "readerQ", qos: .userInitiated, attributes: .concurrent)
    private let dsConcQueue:DispatchQueue = DispatchQueue.init(label: "dsConQ", qos: .userInitiated, attributes: .concurrent)
    
    //
    private var index:Int = 0       // Just for capturing timing
    
    //
    // MARK: - Public API
    //
    
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
        
        let returnSamples:(SampleBuffer?)->() = { sBuff in
            if let sb = sBuff { completion(sb) }
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
                timing(index: index, key: "total", comment: "", stats: timeStats) {
                    downsampleSync(sourceFile: af, startFrame: 0, numOutFrames: thisNumOutFrames, dsFactor: thisDsFactor, completion: returnSamples)
                }
            }
        }
        else {
            // Downsample file segment sync
            timing(index: index, key: "total", comment: "", stats: timeStats) {
                downsampleSync(sourceFile: af, startFrame: thisStartFrame, numOutFrames: numOutFrames, dsFactor: dsFactor, completion: returnSamples)
            }
        }
    }
    
    //
    // MARK: - Donwsampling functions
    //
    private func downsampleAsync(assetURL:URL, assetLength:AVAudioFrameCount, startFrame:AVAudioFramePosition, dsFactor:Int, numReaders:Int, completion:@escaping(SampleBuffer?)->()) {
        
        var blockId = 0
        
        let downsample:(_ pb:AVAudioPCMBuffer, _ dsFactor:Int, _ blockId:Int, _ sampBuff:SampleBuffer)->() = { (pb, dsFactor, blockId, sampBuff) in
            guard let fcd = pb.floatChannelData, let sbfd = sampBuff.floatData else { return }
            
            // Downsample buffer
            for idx in 0..<Int(pb.frameLength / AVAudioFrameCount(dsFactor)) {
                vDSP_maxv(fcd[0] + (idx * Int(dsFactor)), 1, fcd[0] + idx, vDSP_Length(dsFactor))
                vDSP_maxv(fcd[1] + (idx * Int(dsFactor)), 1, fcd[1] + idx, vDSP_Length(dsFactor))
            }
            // Adjust number of valid frames in pcm buffer
            pb.frameLength /= AVAudioFrameCount(dsFactor)
            // Merge channels and accumulate in sample buffer
            var avg:Float = 0.5
            let nominalDsLength = Int(pb.frameCapacity) / Int(dsFactor)
            let outOffset:Int = nominalDsLength * blockId
            vDSP_vasm(fcd[0], 1, fcd[1], 1, &avg, sbfd + outOffset, 1, vDSP_Length(pb.frameLength))
            sampBuff.frameLength += pb.frameLength
        }
        
        
        
        let readFile:(_ assetURL: URL, _ pFormat: AVAudioFormat, _ sourceLength: AVAudioFrameCount, _ dsFactor: Int, _ blockSize: AVAudioFrameCount, _ startBlock: Int, _ numBlocks: Int, _ outBuffer: SampleBuffer)->() = {audioFile, pFormat, sourceLength, dsFactor, blockSize, startBlock, numBlocks, outBuffer in
            
            do {
                let audioFile = try AVAudioFile(forReading: assetURL)
                audioFile.framePosition = Int64(blockSize * UInt32(startBlock))
                for idx in 0..<numBlocks {
                    if let pcmb = AVAudioPCMBuffer.init(pcmFormat: pFormat, frameCapacity: blockSize) {
                        do {
                            try audioFile.read(into: pcmb, frameCount: blockSize)
                            submitDownsample(pcmb, dsFactor, startBlock + idx, outBuffer)
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
        
        
        func submitDownsample(_ pb:AVAudioPCMBuffer, _ dsFactor:Int, _ blockId:Int, _ sampBuff:SampleBuffer) {
            self.ripFileGroup.enter()
            self.dsConcQueue.async {
                downsample(pb, dsFactor, blockId, sampBuff)
                self.ripFileGroup.leave()
            }
        }
        
        
        let ripStartTime = CACurrentMediaTime()
        
        // Allocate sample buffer large enough for downsampled frames
        let thisOutFrames = assetLength / UInt32(dsFactor)
        let sBuff = SampleBuffer.init(capacity: thisOutFrames)
        
        guard let pf = processingFormat, let sb = sBuff, let sbfd = sb.floatData else { completion(nil); return }
        
        // Round down frames per reader to integer multiple of block size
        var framesPerReader = (assetLength / UInt32(numReaders)) - ((assetLength / UInt32(numReaders)) % kBlockSize)
        var blocksPerReader =  Int(framesPerReader / kBlockSize)
        
        for idx in 0..<numReaders {
            let startBlock = Int(blocksPerReader) * idx
            if idx == (numReaders - 1) {
                // Adjust number of frames, number of blocks for the last reader
                framesPerReader = assetLength - (framesPerReader * UInt32(idx))
                blocksPerReader = Int((framesPerReader % kBlockSize) != 0 ? (framesPerReader / kBlockSize) + 1 : framesPerReader / kBlockSize)
            }
            
            submitReadFile(assetURL: assetURL, pFormat: pf, sourceLength: assetLength, dsFactor: dsFactor, blockSize: kBlockSize, startBlock: startBlock, numBlocks: blocksPerReader, outBuffer: sb)
        }
        
        ripFileGroup.notify(queue: DispatchQueue.main, execute: {
            var peak:Float = 1.0
            vDSP_maxv(sbfd, 1, &peak, vDSP_Length(sb.frameLength))
            sb.peak = peak
            print("Async file duration: \(CACurrentMediaTime() - ripStartTime)")
            completion(sb)
        })
        
    }
    
    private func downsampleSync(sourceFile:AVAudioFile, startFrame:AVAudioFramePosition, numOutFrames:AVAudioFrameCount, dsFactor:Int, completion:@escaping(SampleBuffer?)->()) {
        
        guard let af = audioFile, let pf = processingFormat else { return }
        
        af.framePosition = startFrame
        
        if let pcmb = AVAudioPCMBuffer.init(pcmFormat: pf, frameCapacity: numOutFrames * UInt32(dsFactor)), let sBuff = SampleBuffer.init(capacity: numOutFrames) {
            
            do {
                let readFileStartTime = CACurrentMediaTime()
                try af.read(into: pcmb, frameCount: numOutFrames * UInt32(dsFactor))
                timeStats.setTimeParameter(index: index, key: "fileread", timing: (comment: "", start: readFileStartTime, end: CACurrentMediaTime()))
                downsample(frameBuffer: pcmb, dsFactor: dsFactor)
                merge(frameBuffer: pcmb, sampleBuffer: sBuff)
                normalise(sampleBuffer: sBuff)
                completion(sBuff)
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
    private func downsample(frameBuffer:AVAudioPCMBuffer, dsFactor:Int) {
        guard let fcd = frameBuffer.floatChannelData else { return }

        switch (strategy, useAccel) {
        case (.avgValue, false):
            timing(index: index, key: "downsample", comment: "", stats: timeStats) {
                var leftAvgValue:Float
                var rightAvgValue:Float
                for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                    leftAvgValue = 0.0
                    rightAvgValue = 0.0
                    for jdx in 0..<Int(dsFactor) {
                        leftAvgValue += abs(fcd[0][(idx * Int(dsFactor)) + jdx])
                        rightAvgValue += abs(fcd[1][(idx * Int(dsFactor)) + jdx])
                    }
                    fcd[0][idx] = leftAvgValue / Float(dsFactor)
                    fcd[1][idx] = rightAvgValue / Float(dsFactor)
                }
            }
        case (.avgValue, true):
            timing(index: index, key: "downsample", comment: "af", stats: timeStats) {
                for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                    vDSP_meamgv(fcd[0] + (idx * Int(dsFactor)), 1, fcd[0] + idx, vDSP_Length(dsFactor))
                    vDSP_meamgv(fcd[1] + (idx * Int(dsFactor)), 1, fcd[1] + idx, vDSP_Length(dsFactor))
                }
            }
        case (.maxValue, false):
            timing(index: index, key: "downsample", comment: "", stats: timeStats) {
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
                    fcd[0][idx] = leftMaxValue
                    fcd[1][idx] = rightMaxValue
                }
            }
        case (.maxValue, true):
            timing(index: index, key: "downsample", comment: "af", stats: timeStats) {
                for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                    vDSP_maxmgv(fcd[0] + (idx * Int(dsFactor)), 1, fcd[0] + idx, vDSP_Length(dsFactor))
                    vDSP_maxmgv(fcd[1] + (idx * Int(dsFactor)), 1, fcd[1] + idx, vDSP_Length(dsFactor))
                }
            }
        case (.sampleValue, false):
            timing(index: index, key: "downsample", comment: "", stats: timeStats) {
                for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                    fcd[0][idx] = abs(fcd[0][idx * Int(dsFactor)])
                    fcd[1][idx] = abs(fcd[1][idx * Int(dsFactor)])
                }
            }
        case (.sampleValue, true):
            timing(index: index, key: "downsample", comment: "af", stats: timeStats) {
                for idx in 0..<Int(frameBuffer.frameLength / UInt32(dsFactor)) {
                    vDSP_maxmgv(fcd[0] + (idx * Int(dsFactor)), 1, fcd[0] + idx, 1)
                    vDSP_maxmgv(fcd[1] + (idx * Int(dsFactor)), 1, fcd[1] + idx, 1)
                }
            }
        }
        // Adjust buffer frame length to downsampled length
        frameBuffer.frameLength = frameBuffer.frameLength / UInt32(dsFactor)
    }
    
    private func merge(frameBuffer:AVAudioPCMBuffer, sampleBuffer:SampleBuffer) {
        guard let fcd = frameBuffer.floatChannelData, let sfd = sampleBuffer.floatData else { return }
        
            let frameLength = frameBuffer.frameLength > sampleBuffer.frameCapacity ? sampleBuffer.frameCapacity : frameBuffer.frameLength
            
            switch useAccel {
            case false:
                timing(index: index, key: "merge", comment: "", stats: timeStats) {
                    for idx in 0..<Int(frameLength) {
                        sfd[idx] = (fcd[0][idx] + fcd[1][idx]) / Float(2.0)
                    }
                }
            case true:
                timing(index: index, key: "merge", comment: "af", stats: timeStats) {
                    var avg:Float = 0.5
                    vDSP_vasm(fcd[0], 1, fcd[1], 1, &avg, sfd, 1, vDSP_Length(frameLength))
                }
            }
            sampleBuffer.frameLength = frameLength
    }
    
    private func normalise(sampleBuffer:SampleBuffer) {
        guard let sbfd = sampleBuffer.floatData else { return }
        
        var peak:Float = 1.0
        var scale:Float = 1.0
        
        switch useAccel {
        case false:
            timing(index: index, key: "normalise", comment: "", stats: timeStats) {
                peak = 0.0
                for idx in 0..<Int(sampleBuffer.frameLength) {
                    peak = sbfd[idx] > peak ? sbfd[idx] : peak
                }
                scale = 1.0 / peak
                for idx in 0..<Int(sampleBuffer.frameLength) {
                    sbfd[idx] = sbfd[idx] * scale
                }
            }
        case true:
            timing(index: index, key: "normalise", comment: "af", stats: timeStats) {
                vDSP_maxv(sbfd, 1, &peak, vDSP_Length(sampleBuffer.frameLength))
                scale = 1.0 / peak
                vDSP_vsmul(sbfd, 1, &scale, sbfd, 1, vDSP_Length(sampleBuffer.frameLength))
            }
        }
    }
    
}
