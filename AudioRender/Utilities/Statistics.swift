//
//  Statistics.swift
//  AudioRender
//
//  Created by Andrew Coad on 13/03/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import Foundation

let kSliderStatsIdx     = 0
let kScrollerStatsIdx   = 1
class Statistics {
    
    enum TimeCategories:String, CaseIterable {
        case fileread = "fileread"
        case total = "total"
        case downsample = "downsample"
        case merge = "merge"
        case peakcalc = "peakcalc"
        case buildpoints = "buildpoints"
        case buildpath = "buildpath"
        case transform = "transform"
        case draw = "draw"
        case render = "render"
    }
    
    private var title:String = ""
    private var timeStats:[String:(comment:String, start:TimeInterval, end:TimeInterval)] = [:]
    private var stats:[[String:(comment:String, start:TimeInterval, end:TimeInterval)]] = [[:], [:]]
    
    public func setTitle(title:String) {
        self.title = title
    }
    
    public func setTimeParameter(index:Int, key: String, timing:(comment:String, start:TimeInterval, end:TimeInterval)) {
        stats[index][key] = timing
//        timeStats[key] = timing
    }
    
    public func printStats() {

        print(title)
        
        stats.forEach { item in
            print("\n")
            if let ts = item["fileread"] {
                print("File read: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["downsample"] {
                print("Downsample: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["merge"] {
                print("Merge: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["peakcalc"] {
                print("Peak calc: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["buildpoints"] {
                print("Point array: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["total"] {
                print("Total processing: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["buildpath"] {
                print("Build path: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["transform"] {
                print("Transform: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["draw"] {
                print("Draw: \(ts.comment) \t\t\(ts.end - ts.start)")
            }
            if let ts = item["render"] {
                print("Total render: \(ts.comment) \t\t\(ts.end - ts.start)")
            }

        }
    }
}

@discardableResult
func measure<A>(name: String = "", _ block: () -> A) -> A {
    let startTime = CACurrentMediaTime()
    let result = block()
    let timeElapsed = CACurrentMediaTime() - startTime
    print("Duration: \(name) - \(timeElapsed)")
    return result
}

@discardableResult
func timing<T>(index:Int, key:String, comment:String, stats:Statistics, _ block: () -> T) -> T {
    let startTime = CACurrentMediaTime()
    let result = block()
    let endTime = CACurrentMediaTime()
    stats.setTimeParameter(index: index, key: key, timing: (comment: comment, start: startTime, end: endTime))
    return result
}
