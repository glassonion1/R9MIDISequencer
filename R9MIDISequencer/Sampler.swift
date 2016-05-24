//
//  Sampler.swift
//  R9MIDISequencer
//
//  Created by Taisuke Fujita on 2016/01/29.
//  Copyright © 2016年 Taisuke Fujita. All rights reserved.
//

import Foundation

public class Sampler {
    
    var audioEngine = AVAudioEngine()
    let samplerNode = AVAudioUnitSampler()
    let channelNumberForDrum: UInt8 = 10
    
    var bankURL: NSURL = NSURL()
    var program: UInt8 = 0;
    var bankMSB: UInt8 = 0;
    var bankLSB: UInt8 = 0;
    var channelNumber: UInt8 = 0;
    
    /// MIDI Client Reference
    var midiClient = MIDIClientRef()
    var midiOutPort = MIDIPortRef()
    
    private init() {
        self.audioEngine.attachNode(self.samplerNode)
        self.audioEngine.connect(self.samplerNode,
            to: self.audioEngine.mainMixerNode,
            format: self.samplerNode.outputFormatForBus(0))
        
        MIDINetworkSession.defaultSession().enabled = true
        MIDINetworkSession.defaultSession().connectionPolicy =
            MIDINetworkConnectionPolicy.Anyone
        
        var result = OSStatus(noErr)
        result = MIDIClientCreateWithBlock("MIDI Client", &midiClient, MIDINotifyBlock)
        if result != OSStatus(noErr) {
            print("error creating client : \(result)")
        }
        result = MIDIOutputPortCreate(midiClient, "Midi Output", &midiOutPort);
        if result != OSStatus(noErr) {
            print("error creating output port : \(result)")
        }
        
        let center = NSNotificationCenter.defaultCenter()
        center.addObserverForName(AVAudioEngineConfigurationChangeNotification, object: nil, queue: NSOperationQueue.mainQueue()) {(notification: NSNotification) in
            if !self.audioEngine.running {
                self.startAudioEngine()
            }
        }
    }
    
    public convenience init(audioFiles: [NSURL]) {
        self.init(audioFiles: audioFiles, channelNumber: 0)
    }
    
    // ドラムの場合はチャンネル10を指定すること
    public convenience init(audioFiles: [NSURL], channelNumber: UInt8) {
        self.init()
        self.channelNumber = channelNumber
        do {
            try self.samplerNode.loadAudioFilesAtURLs(audioFiles)
            try self.audioEngine.start()
        } catch {
            
        }
    }
    
    public convenience init(bankURL: NSURL, program: UInt8, bankMSB: UInt8, bankLSB: UInt8) {
        self.init(bankURL: bankURL, program: program, bankMSB: bankMSB, bankLSB: bankLSB, channelNumber: 0)
    }
    
    // ドラムの場合はチャンネル10を指定すること
    public convenience init(bankURL: NSURL, program: UInt8, bankMSB: UInt8, bankLSB: UInt8, channelNumber: UInt8) {
        self.init()
        self.bankURL = bankURL
        self.program = program
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.channelNumber = channelNumber
        startAudioEngine()
    }
    
    deinit {
        MIDIPortDispose(self.midiOutPort)
        MIDIClientDispose(self.midiClient)
        self.audioEngine.stop()
    }
    
    private func startAudioEngine() {
        do {
            try self.samplerNode.loadSoundBankInstrumentAtURL(bankURL, program: program, bankMSB: bankMSB, bankLSB: bankLSB)
            try self.audioEngine.start()
        } catch {
    
        }
    }
    
    public func startNoteWithNumber(noteNumber: UInt8) {
        self.samplerNode.startNote(noteNumber, withVelocity: 127, onChannel: self.channelNumber)
        
        let noteCommand: UInt8 = UInt8(0x90) + UInt8(self.channelNumber)
        let message: [UInt8] = [noteCommand, UInt8(noteNumber), UInt8(127)]
        self.sendMessage(message)
    }
    
    public func stopNoteWithNumber(noteNumber: UInt8) {
        // チャンネル設定 10のときは無視
        if self.channelNumber != self.channelNumberForDrum {
            self.samplerNode.stopNote(noteNumber, onChannel: self.channelNumber)
        }
        
        let noteCommand: UInt8 = UInt8(0x90) + UInt8(channelNumber)
        let message: [UInt8] = [noteCommand, UInt8(noteNumber), UInt8(0)]
        self.sendMessage(message)
    }
    
    public func sendMessage(data: [UInt8]) {
        var result = OSStatus(noErr)
        let packetListPtr: UnsafeMutablePointer<MIDIPacketList> = UnsafeMutablePointer.alloc(1)
        
        var packet = UnsafeMutablePointer<MIDIPacket>()
        packet = MIDIPacketListInit(packetListPtr)
        packet = MIDIPacketListAdd(packetListPtr, 1024, packet, 0, data.count, data)
        
        let destinationCount = MIDIGetNumberOfDestinations()
        print("DestinationCount: \(destinationCount)")
        for var i = 0; i < destinationCount; ++i {
            let destination: MIDIEndpointRef = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            result = MIDIObjectGetStringProperty(destination, kMIDIPropertyName, &cfName)
            if result != OSStatus(noErr) {
                print("error creating destination : \(result)")
            }
            let name = Unmanaged.fromOpaque(
                cfName!.toOpaque()).takeUnretainedValue() as CFStringRef
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
        
        packetListPtr.destroy()
        packetListPtr.dealloc(1)//necessary? wish i could do this without the alloc above
    }
    
    private func MIDINotifyBlock(midiNotification: UnsafePointer<MIDINotification>) {
        let notification = midiNotification.memory
        print("MIDI Notify, messageId= \(notification.messageID.rawValue)")
    }
    
}
