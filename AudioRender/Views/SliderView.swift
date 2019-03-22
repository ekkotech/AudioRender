//
//  SliderView.swift
//  AudioRender
//
//  Created by Andrew Coad on 13/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import UIKit
import AVFoundation

class SliderView: WaveformView, WaveformRenderProtocol {
    
    let decimation = kDsFactorSlider
    let displayScale = UIScreen.main.scale
    public var sampleSourceDelegate:SampleRequestProtocol? = nil
    private var renderCompletionCallback:(()->())? = nil
    
    //
    // MARK: - Initialisation
    //
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        self.layerDelegate.parentView = self
        
        self.layer.backgroundColor = sliderViewPalette.gradientBackgroundColour
        self.layer.insertSublayer(gradientLayer, at: UInt32(self.layer.sublayers?.count ?? 0))
        self.layer.insertSublayer(waveformLayer, at: UInt32(self.layer.sublayers?.count ?? 0))
        self.layer.insertSublayer(cursorLayer, at: UInt32(self.layer.sublayers?.count ?? 0))
        
        maskLayer.fillColor = sliderViewPalette.maskFillColour
        maskLayer.backgroundColor = sliderViewPalette.maskBackgroundColour
        maskLayer.name = kLayerNameMask
        maskLayer.delegate = layerDelegate
        //
        gradientLayer.backgroundColor = sliderViewPalette.gradientBackgroundColour
        gradientLayer.colors = colourThemeSunset
        gradientLayer.startPoint = CGPoint.zero
        gradientLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
        gradientLayer.mask = maskLayer
        gradientLayer.name = kLayerNameGradient
        gradientLayer.delegate = layerDelegate
        //
        waveformLayer.lineWidth = kLineWidth
        waveformLayer.backgroundColor = sliderViewPalette.waveformBackgroundColour
        waveformLayer.strokeColor = sliderViewPalette.waveformLineColour
        waveformLayer.fillColor = sliderViewPalette.waveformLineColour
        waveformLayer.name = kLayerNameWaveform
        waveformLayer.delegate = layerDelegate
        //
        cursorLayer.lineWidth = kCursorLineWidth
        cursorLayer.backgroundColor = sliderViewPalette.cursorBackgroundColour
        cursorLayer.strokeColor = sliderViewPalette.cursorLineColour
        cursorLayer.fillColor = sliderViewPalette.cursorLineColour
        cursorLayer.name = kLayerNameCursorSlider
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
        guard let ssd = sampleSourceDelegate, target == .slider else { return }
        
        if kDsFactorMaximum {
            // Compresses entire file to width of landscape view
            ssd.getSamples(initialRender: true, startFrame: 0, numOutFrames: AVAudioFrameCount(maxLayerWidth), dsFactor: kDsFactorUnspecified, clientRef: 0, samplesCB: renderSamples)
        }
        else {
            // Compresses entire file by specified compression factor
            ssd.getSamples(initialRender: true, startFrame: 0, numOutFrames: 0, dsFactor: kDsFactorSlider, clientRef: 0, samplesCB: renderSamples)
        }
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
    }
    
}
