//
//  Constants.swift
//  R9MIDISequencer
//
//  Created by Taisuke Fujita on 2016/02/26.
//  Copyright © 2016年 Revolution9. All rights reserved.
//

import Foundation

struct R9Constants {
    static let midiDestinationName: String = {
        // アプリごとに名前を変える
        let id = Bundle.main.bundleIdentifier ?? ""
        return "\(id).destination"
    }()
    static let midiRecorderDestinationName: String = {
        // アプリごとに名前を変える
        let id = Bundle.main.bundleIdentifier ?? ""
        return "\(id).recorder.destination"
    }()
}
