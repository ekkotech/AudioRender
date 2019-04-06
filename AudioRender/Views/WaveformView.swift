//
//  WaveformView.swift
//  AudioRenderAaya Lolo-44-MP3-128
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
let kLayerNameGradient          = "G"
let kLayerNameMask              = "M"
let kLayerNameWaveform          = "W"
let kLayerNameCursorSlider      = "CSL"
let kLayerNameCursorScroller    = "CSC"

//
// Layer Indexes
//
let kLayerIndexGradient     = 0
let kLayerIndexWaveform     = 1
let kLayerIndexCursor       = 2

let kLineWidth              = CGFloat(1.0)
let kCursorLineWidth        = kLineWidth
let kWaveformMaxYScale      = CGFloat(0.9)

//
// Rendering control
//
enum RenderConfig:String {
    case lines          = "Lines"       // Individual lines inserted into path, scale on-the-fly
    case linkLines      = "Link Lines"  // Joined lines inserted into path, scale on-the-fly
    case fill           = "Fill"        // Outline inserted into path, scaled by transform and filled
    case mask           = "Mask"        // Outline inserted into path, scaled by transform and masked
}

let renderConfig:RenderConfig   = .fill
let shouldNormalise             = false

class WaveformView: UIView {
    
    //
    // MARK: - Private properties
    //
    internal let cursorLayer = CAShapeLayer()
    internal let maskLayer = CAShapeLayer()
    internal let waveformLayer = CAShapeLayer()
    internal let gradientLayer = CAGradientLayer()
    internal let layerDelegate = WaveformViewLayerDelegate()
    internal var maxLayerWidth:CGFloat = 0.0

    //
    // MARK: - Public properties
    //
    public var sampleBuffer:SampleBuffer? = nil

    //
    // MARK: - Initialisation
    //
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    //
    // MARK: - Geometry management
    //
    override func layoutSubviews() {
        super.layoutSubviews()
        adjustLayerGeometry()
        maxLayerWidth = getMaxLayerWidth()
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

    //
    // MARK: - Private methods
    //
    private func getMaxLayerWidth() -> CGFloat {
        
        let thisDevice = UIDevice()
        var baseWidth = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.width : UIScreen.main.bounds.height
        
        if thisDevice.userInterfaceIdiom == .phone {
            if #available(iOS 11.0, *) {
                let vc = UIApplication.shared.keyWindow!.rootViewController as! RootViewController
                let insets = vc.view.safeAreaInsets
                if insets.top > 0.0 && insets.bottom > 0.0 {
                    baseWidth -= insets.top > insets.bottom ? (insets.top * 2) : (insets.bottom * 2)
                }
                else if insets.left > 0.0 && insets.right > 0.0 {
                    baseWidth -= insets.left > insets.right ? (insets.left * 2) : (insets.right * 2)
                }
            }
        }
        return baseWidth
    }

    //
    // MARK: - Public methods
    //
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
            
        case kLayerNameCursorSlider, kLayerNameCursorScroller:
            let lyr = layer as? CAShapeLayer
            let path = CGMutablePath()
            let xOffset:CGFloat = Int(layer.bounds.width) % 2 == 0 ? 0.5 : 0.0
            let xPosition:CGFloat = layer.name == kLayerNameCursorSlider ? 0.0 : layer.bounds.width / 2
            path.move(to: CGPoint(x: xPosition + xOffset, y: 0.0))
            path.addLine(to: CGPoint(x: xPosition + xOffset, y: layer.bounds.height))
            lyr?.path = path
        default:
            break
        }
    }
    
}

extension WaveformViewLayerDelegate {
    
    func renderWithMask(layer: CALayer, in ctx: CGContext, parentView: WaveformView?) {
        
        guard let pv = parentView, let mask = layer.mask as? CAShapeLayer, let sb = pv.sampleBuffer else { return }
        guard sb.frameLength.value > 0 else { return }

        let index = pv is SliderView ? 0 : 1
        let path = CGMutablePath()
        let yScale = shouldNormalise ? (kWaveformMaxYScale / CGFloat(sb.peak)) : kWaveformMaxYScale
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
        
        guard let pv = parentView, let sb = pv.sampleBuffer, sb.frameLength.value > 0 else { return }
        
        let index = pv is SliderView ? 0 : 1

        ctx.setStrokeColor(sliderViewPalette.waveformLineColour)
        ctx.setFillColor(sliderViewPalette.waveformLineColour)
        ctx.setLineWidth(kLineWidth)
        
        if renderConfig == .lines {
            // Render using points array...
            // For "basic" rendering, only the first half of the points buffer is required
            guard sb.points.count > 0 else { return }

            let path = CGMutablePath()

            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                let yTranslation:CGFloat = layer.bounds.height / 2
                let xScale = layer.bounds.size.width / CGFloat(sb.frameLength.value)
                let yScale = shouldNormalise ? (layer.bounds.size.height / 2) * (kWaveformMaxYScale / CGFloat(sb.peak)) : (layer.bounds.size.height / 2) * kWaveformMaxYScale
                
                for idx in 0..<sb.points.count / 2 {
                    let xScaled = CGFloat(xScale * CGFloat(idx))
                    let yUpperScaled = CGFloat(yScale * sb.points[idx].y)
                    let yLowerScaled = CGFloat(yScale * sb.points[(sb.points.count - 1) - idx].y)
                    path.move(to: CGPoint(x: xScaled + 0.5, y: yTranslation - yUpperScaled))
                    path.addLine(to: CGPoint(x: xScaled + 0.5, y: yTranslation - yLowerScaled))
                }
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                if let lyr = layer as? CAShapeLayer { lyr.path = path }
            }
        }
        else if renderConfig == .linkLines {
            guard sb.points.count > 0 else { return }
            
            let path = CGMutablePath()
            
            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                let yTranslation:CGFloat = layer.bounds.height / 2
                let xScale = layer.bounds.size.width / CGFloat(sb.frameLength.value)
                let yScale = shouldNormalise ? (layer.bounds.size.height / 2) * (kWaveformMaxYScale / CGFloat(sb.peak)) : (layer.bounds.size.height / 2) * kWaveformMaxYScale
                path.move(to: CGPoint(x: 0.0, y: yTranslation))
                for idx in 0..<sb.points.count / 2 {
                    let xScaled = CGFloat(xScale * CGFloat(idx))
                    let yUpperScaled = CGFloat(yScale * sb.points[idx].y)
                    let yLowerScaled = CGFloat(yScale * sb.points[(sb.points.count - 1) - idx].y)
                    let modifier = idx % 2 == 0 ? 1 : -1
                    path.addLine(to: CGPoint(x: xScaled + 0.5, y: (yTranslation - (yUpperScaled * CGFloat(modifier)))))
                    path.addLine(to: CGPoint(x: xScaled + 0.5, y: (yTranslation - (yLowerScaled * CGFloat(modifier)))))
                    if idx == (sb.points.count / 2) - 1 {
                        path.addLine(to: CGPoint(x: xScaled + 0.5, y: yTranslation))
                    }
                }
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                if let lyr = layer as? CAShapeLayer { lyr.path = path }
            }
            
        }
        else if renderConfig == .fill {
            guard sb.points.count > 0 else { return }
            
            let path = CGMutablePath()
            //
            // Add CGAffineTransform code here
            //
            let tf = CGAffineTransform.identity

            timing(index: index, key: "buildpath", comment: "", stats: timeStats) {
                path.addLines(between: sb.points, transform: tf)
                path.closeSubpath()
            }
            
            timing(index: index, key: "draw", comment: "", stats: timeStats) {
                if let lyr = layer as? CAShapeLayer { lyr.path = path }
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
 let yScale = shouldNormalise ? (kWaveformMaxYScale / CGFloat(sb.peak)) : kWaveformMaxYScale
 tf = tf.translatedBy(x: 0.5, y: layer.bounds.height / 2)
 tf = tf.scaledBy(x: layer.bounds.width / CGFloat(sb.points.count / 2), y: (layer.bounds.height / 2) * yScale)

 
 
 */
