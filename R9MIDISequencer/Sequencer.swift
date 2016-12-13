//
//  Sequencer.swift
//  R9MIDISequencer
//
//  Created by Taisuke Fujita on 2016/02/03.
//  Copyright © 2016年 Taisuke Fujita. All rights reserved.
//

import AVFoundation
import CoreMIDI
import AudioToolbox


open class Sequencer {
    
    let callBack: @convention(c) (UnsafeMutableRawPointer?, MusicSequence, MusicTrack, MusicTimeStamp, UnsafePointer<MusicEventUserData>, MusicTimeStamp, MusicTimeStamp) -> Void = {
        (obj, seq, mt, timestamp, userData, timestamp2, timestamp3) in
        // Cタイプ関数なのでselfを使えません
        //let mySelf: Sequencer = bridge(obj)
        let mySelf: Sequencer = unsafeBitCast(obj, to: Sequencer.self)
        for listener in mySelf.midiListeners {
            OperationQueue.main.addOperation({
                listener.midiSequenceDidFinish()
            })
        }
    }
    
    var enableLooping = false
    
    var sequencer: AVAudioSequencer
    var sampler: Sampler
    var musicSequence: MusicSequence
    
    var endPoint = MIDIEndpointRef()
    
    open var lengthInBeats: TimeInterval = 0.0
    
    open var lengthInSeconds: TimeInterval = 0.0
    
    /// Array of all listeners
    var midiListeners: [MIDIMessageListener] = []
    
    open var currentPositionInSeconds: TimeInterval {
        get {
            return sequencer.currentPositionInSeconds
        }
    }
    
    open var currentPositionInBeats: TimeInterval {
        get {
            return sequencer.currentPositionInBeats
        }
    }
    
    /// Add a listener to the listeners
    open func addListener(_ listener: MIDIMessageListener){
        midiListeners.append(listener)
    }
    
    public init(sampler: Sampler, enableLooping: Bool) {
        self.sampler = sampler
        self.enableLooping = enableLooping
        self.sequencer = AVAudioSequencer(audioEngine: sampler.audioEngine)
        self.musicSequence = sampler.audioEngine.musicSequence!
        
        var result = OSStatus(noErr)
        /*
        var midiClient = MIDIClientRef()
        result = MIDIClientCreateWithBlock("MIDI Client for Sequencer" as CFString, &midiClient, MIDINotifyBlock)
        if result != OSStatus(noErr) {
            print("error creating client : \(result)")
        }*/
        let destinationCount = MIDIGetNumberOfDestinations()
        print("DestinationCount: \(destinationCount)")
        var found = false
        for i in 0 ..< destinationCount {
            let destination: MIDIEndpointRef = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            result = MIDIObjectGetStringProperty(destination, kMIDIPropertyName, &cfName)
            if result != OSStatus(noErr) {
                print("error get destination : \(result)")
            }
            let name = Unmanaged.fromOpaque(
                cfName!.toOpaque()).takeUnretainedValue() as CFString
            print(String(name))
            if String(name) == Constants.midiDestinationName {
                found = true
                break
            }
        }
        if !found {
            result = MIDIDestinationCreateWithBlock(self.sampler.midiClient, Constants.midiDestinationName as CFString, &endPoint, MIDIReadBlock)
            if result != OSStatus(noErr) {
                print("error creating destination : \(result)")
            }
        }
    }
    
    public convenience init(sampler: Sampler) {
        self.init(sampler: sampler, enableLooping: false)
    }
    
    deinit {
        MIDIEndpointDispose(endPoint)
    }

    open func playWithMidiURL(_ midiFileUrl: URL) -> TimeInterval {
        self.stop()
        sequencer.currentPositionInSeconds = 0

        // MIDIファイルの読み込み
        do {
            try sequencer.load(from: midiFileUrl, options: .smfChannelsToTracks)
        } catch let error as NSError {
            print(midiFileUrl)
            print(error)
            // Workaround
            do {
                try sequencer.load(from: midiFileUrl, options: .smfChannelsToTracks)
            } catch {
                print("reload error")
            }
        }
        
        var result = OSStatus(noErr)
        result = MusicSequenceSetMIDIEndpoint(self.musicSequence, self.endPoint);
        if result != OSStatus(noErr) {
            print("error creating endpoint : \(result)")
        }

        let destinationCount = MIDIGetNumberOfDestinations()
        for i in 0 ..< destinationCount {
            let src: MIDIEndpointRef = MIDIGetDestination(i)
            result = MusicSequenceSetMIDIEndpoint(self.musicSequence, src);
            if result != OSStatus(noErr) {
                print("error creating endpoint : \(result)")
            }
        }

        if enableLooping {
            for track in sequencer.tracks {
                track.isLoopingEnabled = true
                track.numberOfLoops = AVMusicTrackLoopCount.forever.rawValue
            }
        }
        
        do {
            sequencer.prepareToPlay()
            try sequencer.start()
        } catch let error as NSError {
            print(error)
        }
        
        // 曲の最後にコールバックを仕込む
        var musicLengthInBeats: TimeInterval = 0.0
        var musicLengthInSeconds: TimeInterval = 0.0
        for track in sequencer.tracks {
            let lengthInBeats = track.lengthInBeats
            let lengthInSeconds = track.lengthInSeconds
            if musicLengthInBeats < lengthInBeats {
                musicLengthInBeats = lengthInBeats
                musicLengthInSeconds = lengthInSeconds
            }
        }

        MusicSequenceSetUserCallback(self.musicSequence, callBack, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        var musicTrack: MusicTrack? = nil
        MusicSequenceGetIndTrack(self.musicSequence, 0, &musicTrack)
        let userData: UnsafeMutablePointer<MusicEventUserData> = UnsafeMutablePointer.allocate(capacity: 1)
        MusicTrackNewUserEvent(musicTrack!, ceil(musicLengthInBeats + sequencer.beats(forSeconds: 1)), userData)
        
        self.lengthInBeats = musicLengthInBeats
        self.lengthInSeconds = musicLengthInSeconds
        
        // 1小節にかかる時間を返す
        return sequencer.beats(forSeconds: 60)
    }
    
    @available(*, unavailable, renamed: "restart")
    open func replay() {
        self.restart()
    }
    
    open func restart() {
        do {
            sequencer.prepareToPlay()
            try sequencer.start()
        } catch {
            print("Error replay MIDI file")
        }
    }
    
    open func stop() {
        sequencer.stop()
    }
    
    fileprivate func MIDIReadBlock(
        _ packetList: UnsafePointer<MIDIPacketList>,
        srcConnRefCon: UnsafeMutableRawPointer?) -> Void {
            let packets = packetList.pointee
            let packet: MIDIPacket = packets.packet
            var packetPtr: UnsafeMutablePointer<MIDIPacket> = UnsafeMutablePointer.allocate(capacity: 1)
            packetPtr.initialize(to: packet)
            for _ in 0 ..< packets.numPackets {
                self.handleMIDIMessage(packetPtr.pointee)
                packetPtr = MIDIPacketNext(packetPtr)
            }
            packetPtr.deinitialize()
    }
    
    /// @see https://github.com/genedelisa/Swift2MIDI/blob/master/Swift2MIDI/ViewController.swift
    /// - parameter packet: パケットデータ
    fileprivate func handleMIDIMessage(_ packet: MIDIPacket) {
        let status = UInt32(packet.data.0)
        let d1 = UInt32(packet.data.1)
        let d2 = UInt32(packet.data.2)
        let rawStatus = status & 0xF0 // without channel
        let channel = UInt32(status & 0x0F)
        
        switch rawStatus {
        case 0x80, 0x90:
            MusicDeviceMIDIEvent(self.sampler.samplerNode.audioUnit, status, d1, d2, 0)
            for listener in midiListeners {
                OperationQueue.main.addOperation({
                    if rawStatus == 0x90 {
                        listener.midiNoteOn(d1, velocity: d2, channel: channel)
                    } else {
                        listener.midiNoteOff(d1, channel: channel)
                    }
                })
            }
            
        case 0xA0:
            print("Polyphonic Key Pressure (Aftertouch). Channel \(channel) note \(d1) pressure \(d2)")
            
        case 0xB0:
            print("Control Change. Channel \(channel) controller \(d1) value \(d2)")
            
        case 0xC0:
            print("Program Change. Channel \(channel) program \(d1)")
            
        case 0xD0:
            print("Channel Pressure (Aftertouch). Channel \(channel) pressure \(d1)")
            
        case 0xE0:
            print("Pitch Bend Change. Channel \(channel) lsb \(d1) msb \(d2)")
            
        default:
            print("Unhandled message \(status)")
            
        }
        
    }
    
    fileprivate func MIDINotifyBlock(_ midiNotification: UnsafePointer<MIDINotification>) {
        let notification = midiNotification.pointee
        print("MIDI Notify, messageId= \(notification.messageID.rawValue)")
    }
    
}
