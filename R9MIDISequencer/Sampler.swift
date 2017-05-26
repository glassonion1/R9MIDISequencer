//
//  Sampler.swift
//  R9MIDISequencer
//
//  Created by Taisuke Fujita on 2016/01/29.
//  Copyright © 2016年 Taisuke Fujita. All rights reserved.
//

import AVFoundation
import CoreMIDI

open class Sampler {
    
    // Sampler's volume
    public var volume: Float {
        get {
            return samplerNode.volume
        }
        set(value) {
            samplerNode.volume = value
        }
    }

    public var audioEngine = AVAudioEngine()
    let samplerNode = AVAudioUnitSampler()
    let channelNumberForDrum: UInt8 = 10
    
    var bankURL: URL = URL(fileURLWithPath: Bundle.main.bundlePath)
    var program: UInt8 = 0;
    var bankMSB: UInt8 = 0;
    var bankLSB: UInt8 = 0;
    var channelNumber: UInt8 = 0;
    
    /// MIDI Client Reference
    var midiClient = MIDIClientRef()
    var midiOutPort = MIDIPortRef()
    
    private init() {
        audioEngine.attach(samplerNode)
        audioEngine.connect(samplerNode,
            to: audioEngine.mainMixerNode,
            format: samplerNode.outputFormat(forBus: 0))

        var result = OSStatus(noErr)
        result = MIDIClientCreateWithBlock("MIDI Client" as CFString, &midiClient, MIDINotifyBlock)
        if result != OSStatus(noErr) {
            print("error creating client : \(result)")
        }
        result = MIDIOutputPortCreate(midiClient, "Midi Output" as CFString, &midiOutPort);
        if result != OSStatus(noErr) {
            print("error creating output port : \(result)")
        }
        
        let center = NotificationCenter.default
        center.addObserver(forName: NSNotification.Name.AVAudioEngineConfigurationChange, object: nil, queue: OperationQueue.main) {(notification: Notification) in
            if !self.audioEngine.isRunning {
                self.startAudioEngine()
            }
        }
    }
    
    public convenience init(audioFiles: [URL]) {
        self.init(audioFiles: audioFiles, channelNumber: 0)
    }
    
    // ドラムの場合はチャンネル10を指定すること
    public convenience init(audioFiles: [URL], channelNumber: UInt8) {
        self.init()
        self.channelNumber = channelNumber
        do {
            try samplerNode.loadAudioFiles(at: audioFiles)
            try audioEngine.start()
        } catch {
            
        }
    }
    
    public convenience init(bankURL: URL, program: UInt8, bankMSB: UInt8, bankLSB: UInt8) {
        self.init(bankURL: bankURL, program: program, bankMSB: bankMSB, bankLSB: bankLSB, channelNumber: 0)
    }
    
    // ドラムの場合はチャンネル10を指定すること
    public convenience init(bankURL: URL, program: UInt8, bankMSB: UInt8, bankLSB: UInt8, channelNumber: UInt8) {
        self.init()
        self.bankURL = bankURL
        self.program = program
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.channelNumber = channelNumber
        startAudioEngine()
    }
    
    deinit {
        MIDIPortDispose(midiOutPort)
        MIDIClientDispose(midiClient)
        audioEngine.stop()
    }
    
    private func startAudioEngine() {
        do {
            try samplerNode.loadSoundBankInstrument(at: bankURL, program: program, bankMSB: bankMSB, bankLSB: bankLSB)
            try audioEngine.start()
        } catch {
    
        }
    }
    
    public func turnOnSustain() {
        samplerNode.sendController(64, withValue: 127, onChannel: channelNumber)
        
        let controllerCommand: UInt8 = UInt8(0xB0) + channelNumber
        let message: [UInt8] = [controllerCommand, 64, UInt8(127)]
        sendMessage(message)
    }
    
    public func turnOffSustain() {
        samplerNode.sendController(64, withValue: 0, onChannel: channelNumber)
        
        let controllerCommand: UInt8 = UInt8(0xB0) + channelNumber
        let message: [UInt8] = [controllerCommand, 64, UInt8(0)]
        sendMessage(message)
    }
    
    public func startNote(_ note: UInt8, withVelocity velocity: UInt8 = 100) {
        samplerNode.startNote(note, withVelocity: velocity, onChannel: channelNumber)
        
        let noteCommand: UInt8 = UInt8(0x90) + channelNumber
        let message: [UInt8] = [noteCommand, note, velocity]
        sendMessage(message)
    }
    
    public func stopNote(_ note: UInt8) {
        // チャンネル設定 10のときは無視
        if channelNumber != channelNumberForDrum {
            samplerNode.stopNote(note, onChannel: channelNumber)
        }
        
        let noteCommand: UInt8 = UInt8(0x90) + channelNumber
        let message: [UInt8] = [noteCommand, note, UInt8(0)]
        sendMessage(message)
    }
    
    open func sendMessage(_ data: [UInt8]) {
        var result = OSStatus(noErr)
        let packetListPtr: UnsafeMutablePointer<MIDIPacketList> = UnsafeMutablePointer.allocate(capacity: 1)
        
        var packet: UnsafeMutablePointer<MIDIPacket>? = nil
        packet = MIDIPacketListInit(packetListPtr)
        packet = MIDIPacketListAdd(packetListPtr, 1024, packet!, 0, data.count, data)
        
        let destinationCount = MIDIGetNumberOfDestinations()
        print("DestinationCount: \(destinationCount)")
        for i in 0 ..< destinationCount {
            let destination: MIDIEndpointRef = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            result = MIDIObjectGetStringProperty(destination, kMIDIPropertyName, &cfName)
            if result != OSStatus(noErr) {
                print("error creating destination : \(result)")
            }
            let name = Unmanaged.fromOpaque(
                cfName!.toOpaque()).takeUnretainedValue() as CFString
            // シーケンサー側には送らない
            if String(name) != Constants.midiDestinationName {
                result = MIDISend(midiOutPort, destination, packetListPtr)
                if result == OSStatus(noErr) {
                    print("sent midi")
                } else {
                    print("error sending midi : \(result)")
                }
            }
        }
        
        packetListPtr.deinitialize()
        packetListPtr.deallocate(capacity: 1)//necessary? wish i could do this without the alloc above
    }
    
    fileprivate func MIDINotifyBlock(_ midiNotification: UnsafePointer<MIDINotification>) {
        let notification = midiNotification.pointee
        print("MIDI Notify, messageId= \(notification.messageID.rawValue)")
    }
    
}
