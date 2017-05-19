//
//  MIDIMessageListener.swift
//  R9MidiSequencer
//
//  Created by Taisuke Fujita on 2016/02/25.
//  Copyright © 2016年 Revolution 9. All rights reserved.
//

import Foundation

public protocol MIDIMessageListener: class {
    
    /// Receive the MIDI note on event
    /// - parameter note:     Note number of activated note
    /// - parameter velocity: MIDI Velocity (0-127)
    /// - parameter channel:  MIDI Channel (1-16)
    func midiNoteOn(_ note: UInt32, velocity: UInt32, channel: UInt32)
    
    /// Receive the MIDI note off event
    /// - parameter note:     Note number of activated note
    /// - parameter channel:  MIDI Channel (1-16)
    func midiNoteOff(_ note: UInt32, channel: UInt32)
    
    /// MIDI sequence did finish
    func midiSequenceDidFinish()
}

public extension MIDIMessageListener {
    
    func midiNoteOn(_ note: UInt32, velocity: UInt32, channel: UInt32) {
        print("Note on. Channel \(channel) note \(note) velocity \(velocity)")
    }
    
    func midiNoteOff(_ note: UInt32, channel: UInt32) {
        print("Note off. Channel \(channel) note \(note)")
    }
    
    func midiSequenceDidFinish() {
        print("MIDI sequence did finish.")
    }
}
