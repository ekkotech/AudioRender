//
//  WaveformView.swift
//  AudioRender
//
//  Created by Andrew Coad on 08/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import UIKit

//
// Compression (downsample factor)
//
let kDsFactorBase               = 64
let kDsFactorSlider             = 4096
let kDsFactorScrollerInitial    = 512
let kDsFactorUnspecified        = -1
let kDsFactorDefault            = kDsFactorSlider
let kDsFactorMaximum            = false

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
    case transform = "Transform"    // Individual lines inserted into path, scaled by transform
    case linkLines = "Link Lines"   // Joined lines inserted into path, scaled by transform
    case fill = "Fill"              // Outline inserted into path, scaled by transform and filled
    case mask = "Mask"              // Outine inserted into path, scaled by transform and masked
}

let renderConfig:RenderConfig   = .mask
let shouldNormalise             = false

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
        guard let sfd = sb.floatData, sb.frameLength > 0 else { return }

        let index = pv is SliderView ? 0 : 1
        let lines = UIBezierPath()
        

        timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
            lines.move(to: CGPoint(x: 0.0, y: 0.0))
            for idx in 0..<Int(sb.frameLength) {
                lines.addLine(to: CGPoint(x: CGFloat(idx), y: CGFloat(sfd[idx])))
            }
            
            for idx in (0..<Int(sb.frameLength)).reversed() {
                lines.addLine(to: CGPoint(x: CGFloat(idx), y: CGFloat(-sfd[idx])))
            }
            lines.close()
        }

        timing(index: index, key: "transform", comment: "", stats: timeStats) {
            doTransform(sBuff: sb, bounds: layer.bounds, lines: lines)
        }

        timing(index: index, key: "draw", comment: "", stats: timeStats) {
            mask.path = lines.cgPath
        }
    }
    
    func renderWaveform(layer: CALayer, in ctx: CGContext, parentView: WaveformView?) {
        
        guard let pv = parentView, let sb = pv.sampleBuffer, let sbfd = sb.floatData, sb.frameLength > 0 else { return }
        
        let index = pv is SliderView ? 0 : 1

        ctx.setStrokeColor(sliderViewPalette.waveformLineColour)
        ctx.setFillColor(sliderViewPalette.waveformLineColour)
        ctx.setLineWidth(kLineWidth)
        
        if renderConfig == .basic {
            timing(index: index, key: "render", comment: "", stats: timeStats) {
                let yTranslation:CGFloat = layer.bounds.height / 2
                let xScale = layer.bounds.size.width / CGFloat(sb.frameLength)
                let yScale = shouldNormalise ? (layer.bounds.size.height / 2) * (kWaveformYScale / CGFloat(sb.peak)) : (layer.bounds.size.height / 2) * kWaveformYScale
                
                for idx in 0..<Int(sb.frameLength) {
                    let xLocation = CGFloat(xScale * CGFloat(idx))
                    let yOffset = (CGFloat(sbfd[idx]) * yScale)
                    
                    ctx.move(to: CGPoint(x: xLocation, y: yTranslation - yOffset))
                    ctx.addLine(to: CGPoint(x: xLocation, y: yTranslation + yOffset))
                    ctx.strokePath()
                }
            }
        }
        else if renderConfig == .transform {
            let lines = UIBezierPath()

            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                for idx in 0..<Int(sb.frameLength) {
                    lines.move(to: CGPoint(x: CGFloat(idx), y: CGFloat(sbfd[idx])))
                    lines.addLine(to: CGPoint(x: CGFloat(idx), y: CGFloat(-sbfd[idx])))
                }
            }
            
            timing(index: index, key: "transform", comment: "", stats: timeStats) {
                doTransform(sBuff: sb, bounds: layer.bounds, lines: lines)
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                doStroke(ctx: ctx, lines: lines)
            }
        }
        else if renderConfig == .linkLines {
            let lines = UIBezierPath()
            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                lines.move(to: CGPoint(x: 0.0, y: 0.0))
                for idx in 0..<Int(sb.frameLength) {
                    let modifier = idx % 2 == 0 ? 1 : -1
                    lines.addLine(to: CGPoint(x: CGFloat(idx), y: CGFloat(sbfd[idx]) * CGFloat(modifier)))
                    lines.addLine(to: CGPoint(x: CGFloat(idx), y: CGFloat(sbfd[idx]) * CGFloat(-modifier)))
                }
            }
            
            timing(index: index, key: "transform", comment: "", stats: timeStats) {
                doTransform(sBuff: sb, bounds: layer.bounds, lines: lines)
            }

            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                doStroke(ctx: ctx, lines: lines)
            }
        }
        else if renderConfig == .fill {
            let lines = UIBezierPath()

            print("Hello with index: \(index)")
            
            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                lines.move(to: CGPoint(x: 0.0, y: 0.0))
                for idx in 0..<Int(sb.frameLength) {
                    lines.addLine(to: CGPoint(x: CGFloat(idx), y: CGFloat(sbfd[idx])))
                }
                
                for idx in (0..<Int(sb.frameLength)).reversed() {
                    lines.addLine(to: CGPoint(x: CGFloat(idx), y: CGFloat(-sbfd[idx])))
                }
                lines.close()
            }
            
            timing(index: index, key: "transform", comment: "", stats: timeStats) {
                doTransform(sBuff: sb, bounds: layer.bounds, lines: lines)
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                doFill(ctx: ctx, lines: lines)
            }
        }
    }
    
    private func doTransform(sBuff:SampleBuffer, bounds:CGRect, lines:UIBezierPath) {
        guard sBuff.frameLength > 0 else { return }
        
        let yScale = shouldNormalise ? (kWaveformYScale / CGFloat(sBuff.peak)) : kWaveformYScale
        var tf = CGAffineTransform.identity
        tf = tf.translatedBy(x: 0.0, y: bounds.height / 2)
        tf = tf.scaledBy(x: bounds.width / CGFloat(sBuff.frameLength), y: (bounds.height / 2) * yScale)
        lines.apply(tf)
    }
    
    private func doStroke(ctx:CGContext, lines:UIBezierPath) {
        ctx.beginPath()
        ctx.addPath(lines.cgPath)
        ctx.strokePath()
    }
    
    private func doFill(ctx:CGContext, lines:UIBezierPath) {
        ctx.beginPath()
        ctx.addPath(lines.cgPath)
        ctx.fillPath()
    }
    
}
