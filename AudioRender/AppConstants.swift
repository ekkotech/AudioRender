//
//  AppConstants.swift
//  AudioRender
//
//  Created by Andrew Coad on 17/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import Foundation
import UIKit

//
// MARK: Colour defnitions
//
// Colours are RGB hex codes 0xRRGGBB
//
let kColourBlack                = 0x000000      // ████ U+2588
let kColourGreyBg               = 0xBDBABE
let kColourGreyDark             = 0x3D3D3D
let kColourGreyInactive         = 0x959595
let kColourGreyInactiveDark     = 0x909090
let kColourWhite                = 0xFFFFFF
let kColourWhiteDull            = 0xF0F0F0
let kColourBlueDark             = 0x003B52
let kColourBlueDarkBg           = 0x083352
let kColourBlueTintBg           = 0x1E4652
let kColourBlueLine             = 0x8DB0C1
let kColourBlueBright           = 0x007AFF
let kColourCyanBright           = 0x00F9F9
let kColourTurquoise            = 0x45B8AC
let kColourTurquoiseBlue        = 0x55B4B0
let kColourTurquoiseBright      = 0x17FFD1
let kColourTurquoiseMid         = 0x00B2BF
let kColourTurquoiseLatter      = 0x2DBFCF
let kColourTurquoiseLight       = 0x08F3FF
let kColourTurquoiseLightBg     = 0xA0F2F8
let kColourTurquoiseMidBg       = 0x70DAE7
let kColourTurquoiseDarkBg      = 0x4BBAD3
let kColourAquaSky              = 0x7FCDCD
let kColourOrange               = 0xFF7100
let kColourOrangeHeavy          = 0xF58613
let kColourOrangeBlood          = 0xFF5517
let kColourOrangeYellow         = 0xFFAF00
let kColourBrick                = 0xBB3821
let kColourPinkDark             = 0xFF549B
let kColourRoseDark             = 0xEC1559
let kColourSalmonDark           = 0xFF6954
let kColourClear                = 0xFFFFFF          // Set alpha = 0.0
// Tequila sunrise
let kColourTequilaBottom        = 0xD84342
let kColourTequilaTop           = 0xF69225
// Sunset
let kColourSunset1              = 0x883847
let kColourSunset2              = 0xCF433A
let kColourSunset3              = 0xF4502C
let kColourSunset4              = 0xF3B12A
//59DFE3

//
// MARK: Colour palettes
//
struct ColourPalette {
    var gradientColours:[CGColor]
    var gradientBackgroundColour:CGColor
    var waveformBackgroundColour:CGColor
    var waveformLineColour:CGColor
    var cursorBackgroundColour:CGColor
    var cursorLineColour:CGColor
    let maskFillColour:CGColor  = UIColor(rgb: kColourWhite, alpha: 1.0).cgColor    // Fixed - do not change
    let maskBackgroundColour:CGColor    = UIColor(rgb: kColourWhite, alpha: 0.0).cgColor    // Fixed - do not change
    
    init() {
        self.gradientColours = colourThemeSunset
        self.gradientBackgroundColour = UIColor.gray.cgColor
        self.waveformBackgroundColour = UIColor.clear.cgColor
        self.waveformLineColour = UIColor(rgb: kColourOrangeHeavy, alpha: 1.0).cgColor
        self.cursorBackgroundColour = UIColor.clear.cgColor
        self.cursorLineColour = UIColor.orange.cgColor
    }
    
    init(gradientColours:[CGColor], gradientBackgroundColour:CGColor, waveformBackgroundColour:CGColor, waveformLineColour:CGColor,  cursorBackgroundColour:CGColor, cursorLineColour:CGColor) {
        self.gradientColours = gradientColours
        self.gradientBackgroundColour = gradientBackgroundColour
        self.waveformBackgroundColour = waveformBackgroundColour
        self.waveformLineColour = waveformLineColour
        self.cursorBackgroundColour = cursorBackgroundColour
        self.cursorLineColour = cursorLineColour
    }
}

let scrollerViewPalette = ColourPalette(gradientColours:colourThemeSunset,
                                        gradientBackgroundColour: UIColor(rgb: kColourGreyBg, alpha: 1.0).cgColor,
                                        waveformBackgroundColour: UIColor(rgb: kColourClear, alpha: 0.0).cgColor,
                                        waveformLineColour: UIColor(rgb: kColourBlueDarkBg, alpha: 1.0).cgColor,
                                        cursorBackgroundColour: UIColor(rgb: kColourClear, alpha: 0.0).cgColor,
                                        cursorLineColour: UIColor(rgb: kColourBrick, alpha: 1.0).cgColor)

let sliderViewPalette = ColourPalette(gradientColours: colourThemeSunset,
                                      gradientBackgroundColour: UIColor(rgb: kColourGreyInactive, alpha: 1.0).cgColor,
                                      waveformBackgroundColour: UIColor(rgb: kColourClear, alpha: 0.0).cgColor,
                                      waveformLineColour: UIColor(rgb: kColourBlueDarkBg, alpha: 1.0).cgColor,
                                      cursorBackgroundColour: UIColor(rgb: kColourClear, alpha: 0.0).cgColor,
                                      cursorLineColour: UIColor(rgb: kColourBrick, alpha: 1.0).cgColor)

let colourThemeSunset = [UIColor(rgb: kColourSunset1, alpha: 1.0).cgColor,
                         UIColor(rgb: kColourSunset2, alpha: 1.0).cgColor,
                         UIColor(rgb: kColourSunset3, alpha: 1.0).cgColor,
                         UIColor(rgb: kColourSunset4, alpha: 1.0).cgColor]

let colourThemeTequilaSunrise = [UIColor(rgb: kColourTequilaTop, alpha: 1.0).cgColor,
                                 UIColor(rgb: kColourTequilaBottom, alpha: 1.0).cgColor]
