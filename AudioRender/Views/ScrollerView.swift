//
//  ScrollerView.swift
//  AudioRender
//
//  Created by Andrew Coad on 13/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import UIKit
import AVFoundation

class ScrollerView: WaveformView {
    
    var dsFactor = kDsFactorScrollerInitial
    let maxLayerWidth = UInt32(UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.width : UIScreen.main.bounds.height)
    let displayScale = UIScreen.main.scale
    public var sampleSourceDelegate:SampleRequestProtocol? = nil
    
    //
    // MARK: - Initialisation
    //
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        self.layerDelegate.parentView = self
        
        self.layer.backgroundColor = scrollerViewPalette.gradientBackgroundColour
        self.layer.insertSublayer(gradientLayer, at: UInt32(self.layer.sublayers?.count ?? 0))
        self.layer.insertSublayer(waveformLayer, at: UInt32(self.layer.sublayers?.count ?? 0))
        self.layer.insertSublayer(cursorLayer, at: UInt32(self.layer.sublayers?.count ?? 0))
        
        maskLayer.fillColor = scrollerViewPalette.maskFillColour
        maskLayer.backgroundColor = scrollerViewPalette.maskBackgroundColour
        maskLayer.name = kLayerNameMask
        maskLayer.delegate = layerDelegate
        //
        gradientLayer.backgroundColor = scrollerViewPalette.gradientBackgroundColour
        gradientLayer.colors = colourThemeSunset
        gradientLayer.startPoint = CGPoint.zero
        gradientLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
        gradientLayer.mask = maskLayer
        gradientLayer.name = kLayerNameGradient
        gradientLayer.delegate = layerDelegate
        //
        waveformLayer.lineWidth = kLineWidth
        waveformLayer.backgroundColor = scrollerViewPalette.waveformBackgroundColour
        waveformLayer.strokeColor = scrollerViewPalette.waveformLineColour
        waveformLayer.fillColor = scrollerViewPalette.waveformLineColour
        waveformLayer.name = kLayerNameWaveform
        waveformLayer.delegate = layerDelegate
        //
        cursorLayer.lineWidth = kCursorLineWidth
        cursorLayer.backgroundColor = scrollerViewPalette.cursorBackgroundColour
        cursorLayer.strokeColor = scrollerViewPalette.cursorLineColour
        cursorLayer.fillColor = scrollerViewPalette.cursorLineColour
        cursorLayer.name = kLayerNameCursor
        cursorLayer.delegate = layerDelegate
    }
    
    //
    // MARK: - Public API (WaveformRenderProtocol)
    //
    func onClearWaveform(clear: Bool) {
        sampleBuffer = nil
        updateAllLayers()
    }
    
    func onScrollTo(position: AVAudioFramePosition) {
        //
    }
    
    func onRenderInitialWaveform(target:RenderTarget) {
        guard let ssd = sampleSourceDelegate, target == .scroller else { return }
        
        ssd.getSamples(initialRender: false, startFrame: 0, numOutFrames: maxLayerWidth, dsFactor: dsFactor, clientRef: 0, samplesCB: renderSamples)
    }
    
    //
    // MARK: - Private functions
    // MARK: Render waveform callback
    //
    private func renderSamples(sBuff:SampleBuffer) {
        sampleBuffer = sBuff
        updateAllLayers()
    }
    
    //
    // MARK: Support primitives
    //
    private func updateAllLayers() {
        
        DispatchQueue.main.async {
            self.layer.sublayers?.forEach { this in
                this.setNeedsDisplay()
            }
        }
        
        // Print statistics
        printQueue.asyncAfter(deadline: .now() + 1) {
            timeStats.printStats()
        }
    }
    
}
