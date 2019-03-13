//
//  Protocols.swift
//  AudioRender
//
//  Created by Andrew Coad on 08/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import Foundation
import AVFoundation

protocol SampleRequestProtocol {
    
    func getSamples(initialRender:Bool,
                    startFrame:AVAudioFramePosition,
                    numOutFrames:AVAudioFrameCount,
                    dsFactor:Int,
                    clientRef:Int,
                    samplesCB:@escaping(SampleBuffer)->()) ->()
}

protocol WaveformRenderProtocol {
    func onClearWaveform(clear:Bool)
    func onScrollTo(position:AVAudioFramePosition)
    func onRenderInitialWaveform(target:RenderTarget)
}
