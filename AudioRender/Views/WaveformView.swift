//
//  WaveformView.swift
//  AudioRender
//
//  Created by Andrew Coad on 08/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import UIKit
import Accelerate

//
// Compression (downsample factor)
//
let kDsFactorBase               = 64
let kDsFactorSlider             = 4096
let kDsFactorScrollerInitial    = 512
let kDsFactorUnspecified        = -1
let kDsFactorDefault            = kDsFactorSlider
let kDsFactorMaximum            = true

//
// Layer Names
//
let kLayerNameGradient      = "G"
let kLayerNameMask          = "M"
let kLayerNameWaveform      = "W"
let kLayerNameCursor        = "C"

//
// Layer Indexes
//
let kLayerIndexGradient     = 0
let kLayerIndexWaveform     = 1
let kLayerIndexCursor       = 2

let kLineWidth              = CGFloat(1.0)
let kCursorLineWidth        = kLineWidth
let kWaveformYScale         = CGFloat(0.9)

//
// Rendering control
//
enum RenderConfig:String {
    case basic = "Basic"            // Individual lines scaled and drawn sequentially
    case linkLines = "Link Lines"   // Joined lines inserted into path, scaled by transform
    case outline = "Outline"        // Outline inserted into path, scaled by transform
    case fill = "Fill"              // Outline inserted into path, scaled by transform and filled
    case mask = "Mask"              // Outline inserted into path, scaled by transform and masked
}

let renderConfig:RenderConfig   = .basic
let shouldNormalise             = true

class WaveformView: UIView {
    
    //
    // MARK: - Private properties
    //
    let cursorLayer = CAShapeLayer()
    let maskLayer = CAShapeLayer()
    let waveformLayer = CAShapeLayer()
    let gradientLayer = CAGradientLayer()
    let layerDelegate = WaveformViewLayerDelegate()
    
    //
    // MARK: - Public properties
    //
    public var sampleBuffer:SampleBuffer? = nil
    
    //
    // MARK: - Geometry management
    //
    override func layoutSubviews() {
        super.layoutSubviews()
        adjustLayerGeometry()
    }
    
    private func adjustLayerGeometry() {
        
        self.layer.sublayers?.forEach { this in
            this.frame = CGRect(x: 0.0, y: 0.0,
                                width: self.frame.width,
                                height: self.frame.height)
            if this.name == kLayerNameGradient {
                this.mask?.frame = this.frame
            }
            this.setNeedsDisplay()
        }
    }
    
    func onSamples(sBuff:SampleBuffer) {
        // Implement in sub-class
    }
    
}

//
// MARK: - Layer Delegate
//
class WaveformViewLayerDelegate: NSObject, CALayerDelegate {

    public var parentView:WaveformView? = nil
    
    func draw(_ layer: CALayer, in ctx: CGContext) {
        
        guard let pv = parentView else { return }
        
        let index = pv is SliderView ? 0 : 1
        
        switch layer.name {
        case kLayerNameGradient:
            
            if renderConfig == .mask {
                timing(index: index, key: "render", comment: "(mask)", stats: timeStats) {
                    renderWithMask(layer: layer, in: ctx, parentView: pv)
                }
            }
            
        case kLayerNameWaveform:
            
            if renderConfig != .mask {
                timing(index: index, key: "render", comment: "(wave)", stats: timeStats) {
                    renderWaveform(layer: layer, in: ctx, parentView: pv)
                }
            }
            
        case kLayerNameCursor:
            break
        default:
            break
        }
    }
    
}

extension WaveformViewLayerDelegate {
    
    func renderWithMask(layer: CALayer, in ctx: CGContext, parentView: WaveformView?) {
        
        guard let pv = parentView, let mask = layer.mask as? CAShapeLayer, let sb = pv.sampleBuffer else { return }
        guard sb.frameLength > 0 else { return }

        let index = pv is SliderView ? 0 : 1
        let path = CGMutablePath()
        let yScale = shouldNormalise ? (kWaveformYScale / CGFloat(sb.peak)) : kWaveformYScale
        let tf = CGAffineTransform.init(offsetX: CGFloat(0.5),
                                        offsetY: layer.bounds.height / 2,
                                        scaleX: layer.bounds.width / CGFloat(sb.points.count / 2),
                                        scaleY: (layer.bounds.height / 2) * yScale)

        timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
            path.addLines(between: sb.points, transform: tf)
            path.closeSubpath()
        }
        
        timing(index: index, key: "draw", comment: "", stats: timeStats) {
            mask.path = path
        }
    }
    
    func renderWaveform(layer: CALayer, in ctx: CGContext, parentView: WaveformView?) {
        
        guard let pv = parentView, let sb = pv.sampleBuffer, sb.frameLength > 0 else { return }
        
        let index = pv is SliderView ? 0 : 1

        ctx.setStrokeColor(sliderViewPalette.waveformLineColour)
        ctx.setFillColor(sliderViewPalette.waveformLineColour)
        ctx.setLineWidth(kLineWidth)
        
        if renderConfig == .basic {
            // Render using points array...
            // For "basic" rendering, only the first half of the points buffer is required
            guard sb.points.count > 0 else { return }

            let path = CGMutablePath()

            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                let yTranslation:CGFloat = layer.bounds.height / 2
                let xScale = layer.bounds.size.width / CGFloat(sb.frameLength)
                let yScale = shouldNormalise ? (layer.bounds.size.height / 2) * (kWaveformYScale / CGFloat(sb.peak)) : (layer.bounds.size.height / 2) * kWaveformYScale
                
                for idx in 0..<sb.points.count / 2 {
                    let xScaled = CGFloat(xScale * CGFloat(idx))
                    let yScaled = CGFloat(yScale * sb.points[idx].y)
                    path.move(to: CGPoint(x: xScaled + 0.5, y: yTranslation - yScaled))
                    path.addLine(to: CGPoint(x: xScaled + 0.5, y: yTranslation + yScaled))
                }
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                doStroke(ctx: ctx, path: path)
            }
        }
        else if renderConfig == .linkLines {
            guard sb.points.count > 0 else { return }
            
            let path = CGMutablePath()
            
            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                let yTranslation:CGFloat = layer.bounds.height / 2
                let xScale = layer.bounds.size.width / CGFloat(sb.frameLength)
                let yScale = shouldNormalise ? (layer.bounds.size.height / 2) * (kWaveformYScale / CGFloat(sb.peak)) : (layer.bounds.size.height / 2) * kWaveformYScale
                path.move(to: CGPoint(x: 0.0, y: 0.0))
                for idx in 0..<sb.points.count / 2 {
                    let xScaled = CGFloat(xScale * CGFloat(idx))
                    let yScaled = CGFloat(yScale * sb.points[idx].y)
                    let modifier = idx % 2 == 0 ? 1 : -1
                    path.addLine(to: CGPoint(x: xScaled + 0.5, y: (yTranslation - (yScaled * CGFloat(modifier)))))
                    path.addLine(to: CGPoint(x: xScaled + 0.5, y: (yTranslation + (yScaled * CGFloat(modifier)))))
                }
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                doStroke(ctx: ctx, path: path)
            }
            
        }
        else if renderConfig == .outline {
            guard sb.points.count > 0 else { return }
            
            let path = CGMutablePath()
            //
            // Add create transform code here
            //
            let tf = CGAffineTransform.identity

            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                path.addLines(between: sb.points, transform: tf)
            }

            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                doStroke(ctx: ctx, path: path)
            }

        }
        else if renderConfig == .fill {
            guard sb.points.count > 0 else { return }
            
            let path = CGMutablePath()
            let yScale = shouldNormalise ? (kWaveformYScale / CGFloat(sb.peak)) : kWaveformYScale
            let tf = CGAffineTransform.init(offsetX: CGFloat(0.5),
                                            offsetY: layer.bounds.height / 2,
                                            scaleX: layer.bounds.width / CGFloat(sb.points.count / 2),
                                            scaleY: (layer.bounds.height / 2) * yScale)

            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                path.addLines(between: sb.points, transform: tf)
                path.closeSubpath()
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                doFill(ctx: ctx, path: path)
            }
        }
    }
    
    private func doStroke(ctx:CGContext, path:CGMutablePath) {
        ctx.beginPath()
        ctx.addPath(path)
        ctx.strokePath()
    }
    
    private func doFill(ctx:CGContext, path:CGMutablePath) {
        ctx.beginPath()
        ctx.addPath(path)
        ctx.fillPath()
    }
    
}

/*
 // Affine transform code
 var tf = CGAffineTransform.identity
 let yScale = shouldNormalise ? (kWaveformYScale / CGFloat(sb.peak)) : kWaveformYScale
 tf = tf.translatedBy(x: 0.5, y: layer.bounds.height / 2)
 tf = tf.scaledBy(x: layer.bounds.width / CGFloat(sb.points.count / 2), y: (layer.bounds.height / 2) * yScale)

 //
 
 
 
 
 */
