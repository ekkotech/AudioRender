//
//  Logger.swift
//  AudioRender
//
//  Created by Andrew Coad on 08/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import Foundation

public class Logger {
    public class func debug(_ message:String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        #if DEBUG
        //        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "y-MM-dd H:m:ss.SSSS"
        if let message = message {
            print(df.string(from: Date()), " \(file):\(function):\(line): \(message)")
        } else {
            print(df.string(from: Date()), " \(file):\(function):\(line)")
        }
        #endif
    }
    
}
