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

public class Sequencer {

    var enableLooping = false
    
    var sequencer: AVAudioSequencer
    var sampler: Sampler
    var musicSequence: MusicSequence
    
    var endPoint = MIDIEndpointRef()
    
    /// Array of all listeners
    var midiListeners: [MIDIMessageListener] = []
    
    public var currentPositionInSeconds: NSTimeInterval {
        get {
            return sequencer.currentPositionInSeconds
        }
    }
    
    public var currentPositionInBeats: NSTimeInterval {
        get {
            return sequencer.currentPositionInBeats
        }
    }
    
    /// Add a listener to the listeners
    public func addListener(listener: MIDIMessageListener){
        midiListeners.append(listener)
    }
    
    public init(sampler: Sampler, enableLooping: Bool) {
        self.sampler = sampler
        self.enableLooping = enableLooping
        self.sequencer = AVAudioSequencer(audioEngine: sampler.audioEngine)
        self.musicSequence = sampler.audioEngine.musicSequence
        
        var result = OSStatus(noErr)
        /*
        result = MIDIClientCreateWithBlock("MIDI Client for Sequencer", &midiClient, MIDINotifyBlock)
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
                print("error creating destination : \(result)")
            }
            let name = Unmanaged.fromOpaque(
                cfName!.toOpaque()).takeUnretainedValue() as CFStringRef
            if String(name) == Constants.midiDestinationName {
                found = true
                break
            }
        }
        if !found {
            result = MIDIDestinationCreateWithBlock(self.sampler.midiClient, Constants.midiDestinationName, &endPoint, MIDIReadBlock)
        }
    }
    
    public convenience init(sampler: Sampler) {
        self.init(sampler: sampler, enableLooping: false)
    }
    
    public func playWithMidiURL(midiFileUrl: NSURL) -> NSTimeInterval {
        self.stop()

        // MIDIファイルの読み込み
        do {
            try sequencer.loadFromURL(midiFileUrl, options: .SMF_ChannelsToTracks)
        } catch {
            print("Error load MIDI file")
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
                track.loopingEnabled = true
                track.numberOfLoops = AVMusicTrackLoopCount.Forever.rawValue
            }
        }
        
        do {
            sequencer.prepareToPlay()
            try sequencer.start()
        } catch {
            print("Error play MIDI file")
        }
        
        // 曲の最後にコールバックを仕込む
        var musicLengthInBeats: NSTimeInterval = 0.0
        for track in sequencer.tracks {
            let lengthInBeats = track.lengthInBeats
            if musicLengthInBeats < lengthInBeats {
                musicLengthInBeats = lengthInBeats
            }
        }
        let callBack: @convention(c) (UnsafeMutablePointer<Void>, MusicSequence, MusicTrack, MusicTimeStamp, UnsafePointer<MusicEventUserData>, MusicTimeStamp, MusicTimeStamp) -> Void = {
            (obj, seq, mt, timestamp, userData, timestamp2, timestamp3) in
            // Cタイプ関数なのでselfを使えません
            let mySelf: Sequencer = bridge(obj)
            for listener in mySelf.midiListeners {
                NSOperationQueue.mainQueue().addOperationWithBlock({
                    listener.midiSequenceDidFinish()
                })
            }
        }
        MusicSequenceSetUserCallback(self.musicSequence, callBack, UnsafeMutablePointer<Void>(bridge(self)))
        var musicTrack: MusicTrack = nil
        MusicSequenceGetIndTrack(self.musicSequence, 0, &musicTrack)
        let userData: UnsafeMutablePointer<MusicEventUserData> = UnsafeMutablePointer.alloc(1)
        MusicTrackNewUserEvent(musicTrack, ceil(musicLengthInBeats), userData)
        
        // 1小節にかかる時間を返す
        return sequencer.beatsForSeconds(60)
    }
    
    public func stop() {
        sequencer.stop()
        sequencer.currentPositionInSeconds = 0
    }
    
    private func MIDIReadBlock(
        packetList: UnsafePointer<MIDIPacketList>,
        srcConnRefCon: UnsafeMutablePointer<Void>) -> Void {
            let packets = packetList.memory
            let packet: MIDIPacket = packets.packet
            var packetPtr: UnsafeMutablePointer<MIDIPacket> = UnsafeMutablePointer.alloc(1)
            packetPtr.initialize(packet)
            for _ in 0 ..< packets.numPackets {
                self.handleMIDIMessage(packetPtr.memory)
                packetPtr = MIDIPacketNext(packetPtr)
            }
            packetPtr.destroy()
    }
    
    /// @see https://github.com/genedelisa/Swift2MIDI/blob/master/Swift2MIDI/ViewController.swift
    /// - parameter packet: パケットデータ
    private func handleMIDIMessage(packet: MIDIPacket) {
        let status = UInt32(packet.data.0)
        let d1 = UInt32(packet.data.1)
        let d2 = UInt32(packet.data.2)
        let rawStatus = status & 0xF0 // without channel
        let channel = UInt32(status & 0x0F)
        
        switch rawStatus {
        case 0x80, 0x90:
            MusicDeviceMIDIEvent(self.sampler.samplerNode.audioUnit, status, d1, d2, 0)
            for listener in midiListeners {
                NSOperationQueue.mainQueue().addOperationWithBlock({
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
    
    private func MIDINotifyBlock(midiNotification: UnsafePointer<MIDINotification>) {
        let notification = midiNotification.memory
        print("MIDI Notify, messageId= \(notification.messageID.rawValue)")
    }
    
}

/// @see http://stackoverflow.com/questions/33294620/how-to-cast-self-to-unsafemutablepointervoid-type-in-swift
func bridge<T : AnyObject>(obj : T) -> UnsafePointer<Void> {
    return UnsafePointer(Unmanaged.passUnretained(obj).toOpaque())
    // return unsafeAddressOf(obj) // ***
}

func bridge<T : AnyObject>(ptr : UnsafePointer<Void>) -> T {
    return Unmanaged<T>.fromOpaque(COpaquePointer(ptr)).takeUnretainedValue()
    // return unsafeBitCast(ptr, T.self) // ***
}
