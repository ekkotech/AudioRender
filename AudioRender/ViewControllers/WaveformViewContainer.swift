//
//  WaveformViewContainer.swift
//  AudioRender
//
//  Created by Andrew Coad on 08/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import UIKit
import AVFoundation
import Accelerate

enum RenderTarget {
    case slider
    case scroller
}

//
// Temporary globals for profiling preformance
var timeStats:Statistics = Statistics()
let printQueue:DispatchQueue = DispatchQueue.init(label: "printQ", qos: .background)

class WaveformViewContainer: UIViewController, SampleRequestProtocol {
    
    @IBOutlet weak var sliderView: SliderView!
    @IBOutlet weak var scrollerView: ScrollerView!
    
    //
    // MARK: - Signal interface (sources)
    //
    private let onClearWaveform:Signal<Bool> = Signal<Bool>()
    private let onScrollTo:Signal<AVAudioFramePosition> = Signal<AVAudioFramePosition>()
    private let onRenderInitialWaveform:Signal<RenderTarget> = Signal<RenderTarget>()
    
    private let sampler:Sampler = Sampler()
    private let requestQueue:DispatchQueue = DispatchQueue.init(label: "dispQ", qos: .userInitiated)
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sliderView.sampleSourceDelegate = self
        scrollerView.sampleSourceDelegate = self
        setUpProxySubscriptions()

    }
    
    private func setUpProxySubscriptions() {
        onClearWaveform.subscribe(with: sliderView, callback: sliderView.onClearWaveform)
        onClearWaveform.subscribe(with: scrollerView, callback: scrollerView.onClearWaveform)
        onScrollTo.subscribe(with: sliderView, callback: sliderView.onScrollTo)
        onScrollTo.subscribe(with: scrollerView, callback: scrollerView.onScrollTo)
        onRenderInitialWaveform.subscribe(with: sliderView, callback: sliderView.onRenderInitialWaveform)
        onRenderInitialWaveform.subscribe(with: scrollerView, callback: scrollerView.onRenderInitialWaveform)
    }
    
    //
    // MARK: - Public API
    //
    func setAsset(assetURL:URL, pFormat:AVAudioFormat) {
        // Create a new global time stats object
        timeStats = Statistics()
        timeStats.setTitle(title: "Strategy: \(strategy.rawValue), \nUsing Accelerate: Ds: \(useAccelForDs ? "Y" : "N"), Merge: \(useAccelForMerge ? "Y" : "N"), Calc Peak: \(useAccelForPeakCalc ? "Y" : "N"), BuildPoints: \(useAccelForBuildPoints ? "Y" : "N") \nMulti-reader: \(useMultiReader ? "Yes" : "No") \nNum Readers: \(useMultiReader ? kNumReaders : 1) \nRender style: \(renderConfig.rawValue)")
        
        sampler.setAsset(assetURL: assetURL, processingFormat: pFormat)
        onRenderInitialWaveform.fire(.slider)
    }
    
    //
    // MARK: Public API (SampleRequestProtocol)
    //
    func getSamples(initialRender:Bool, startFrame:AVAudioFramePosition, numOutFrames:AVAudioFrameCount, dsFactor:Int, clientRef:Int, samplesCB:@escaping(SampleBuffer)->()) {
        
        func samplesReturned(sampleBuffer:SampleBuffer) {
            if initialRender {
                if let fsd = sampleBuffer.floatSampleData {
                    // Calculate peak value (of entire file)
                    var thisPeak:Float = 1.0
                    vDSP_maxv(fsd[0], 1, &thisPeak, vDSP_Length(sampleBuffer.frameLength.value))
                    sampleBuffer.peak = thisPeak
                    sampler.peak = thisPeak
                }
                // Render scroller
                onRenderInitialWaveform.fire(.scroller)
            }
            samplesCB(sampleBuffer)
        }
        
        requestQueue.async {
            self.sampler.getSamples(initialRender: initialRender, startFrame: startFrame, numOutFrames: numOutFrames, dsFactor: dsFactor, clientRef: clientRef, completion: samplesReturned)
        }
    }
    
}
