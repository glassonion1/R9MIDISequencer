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
        unowned let mySelf: Sequencer = unsafeBitCast(obj, to: Sequencer.self)
        MIDIEndpointDispose(mySelf.midiDestination)
        OperationQueue.main.addOperation({ [weak delegate = mySelf.delegate] in
            delegate?.midiSequenceDidFinish()
        })
    }
    
    var enableLooping = false
    
    var sequencer: AVAudioSequencer
    var musicSequence: MusicSequence
    
    var midiClient = MIDIClientRef()
    var midiDestination = MIDIEndpointRef()
    
    public private(set) var lengthInBeats: TimeInterval = 0.0
    
    public private(set) var lengthInSeconds: TimeInterval = 0.0
    
    // Beats Per Minute
    public private(set) var bpm: TimeInterval = 0.0
    
    weak public var delegate: MIDIMessageListener?
    
    public var currentPositionInSeconds: TimeInterval {
        get {
            return sequencer.currentPositionInSeconds
        }
    }
    
    public var currentPositionInBeats: TimeInterval {
        get {
            return sequencer.currentPositionInBeats
        }
    }
    
    public init(audioEngine: AVAudioEngine, enableLooping: Bool) {
        
        self.enableLooping = enableLooping
        self.sequencer = AVAudioSequencer(audioEngine: audioEngine)
        self.musicSequence = audioEngine.musicSequence!
        
        let destinationCount = MIDIGetNumberOfDestinations()
        print("DestinationCount: \(destinationCount)")
        
        var result = OSStatus(noErr)
        result = MIDIClientCreateWithBlock("MIDI Client" as CFString, &midiClient, nil)
        if result != OSStatus(noErr) {
            print("error creating client : \(result)")
        }
    }
    
    public convenience init(audioEngine: AVAudioEngine) {
        self.init(audioEngine: audioEngine, enableLooping: false)
    }
    
    deinit {
        MIDIClientDispose(midiClient)
    }
    
    public func playWithMidiURL(_ midiFileUrl: URL) {
        stop()
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
        
        createMIDIDestination()
        
        // シーケンサにEndPointをセットする
        sequencer.tracks.forEach({ track in
            track.destinationMIDIEndpoint = midiDestination
        })
        /*
        var result = OSStatus(noErr)
        result = MusicSequenceSetMIDIEndpoint(musicSequence, midiDestination);
        if result != OSStatus(noErr) {
            print("error creating endpoint : \(result)")
        }*/
        
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
        
        MusicSequenceSetUserCallback(musicSequence, callBack, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        var musicTrack: MusicTrack? = nil
        MusicSequenceGetIndTrack(musicSequence, 0, &musicTrack)
        let userData: UnsafeMutablePointer<MusicEventUserData> = UnsafeMutablePointer.allocate(capacity: 1)
        MusicTrackNewUserEvent(musicTrack!, ceil(musicLengthInBeats + sequencer.beats(forSeconds: 1)), userData)
        
        lengthInBeats = musicLengthInBeats
        lengthInSeconds = musicLengthInSeconds
        
        bpm = sequencer.beats(forSeconds: 60)
    }
    
    public func restart() {
        do {
            sequencer.prepareToPlay()
            try sequencer.start()
        } catch {
            print("Error replay MIDI file")
        }
    }
    
    public func stop() {
        sequencer.stop()
    }
    
    public func dispose() {
        if sequencer.isPlaying {
            sequencer.stop()
        }
        MIDIEndpointDispose(midiDestination)
    }
    
    private func createMIDIDestination() {
        /// This block will be method then memory leak
        /// @see https://github.com/genedelisa/Swift2MIDI/blob/master/Swift2MIDI/ViewController.swift
        /// - parameter packet: パケットデータ
        let handleMIDIMessage = { [weak self] (packet: MIDIPacket) in
            guard let localSelf = self else {
                return
            }
            let status = UInt32(packet.data.0)
            let d1 = UInt32(packet.data.1)
            let d2 = UInt32(packet.data.2)
            let rawStatus = status & 0xF0 // without channel
            let channel = UInt32(status & 0x0F)
            
            switch rawStatus {
            case 0x80, 0x90:
                OperationQueue.main.addOperation({ [weak delegate = localSelf.delegate] in
                    if rawStatus == 0x90 {
                        delegate?.midiNoteOn(d1, velocity: d2, channel: channel)
                    } else {
                        delegate?.midiNoteOff(d1, channel: channel)
                    }
                })
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
        
        var result = OSStatus(noErr)
        let name = Constants.midiDestinationName as CFString
        result = MIDIDestinationCreateWithBlock(midiClient, name, &midiDestination) { (packetList, srcConnRefCon) in
            let packets = packetList.pointee
            let packet: MIDIPacket = packets.packet
            var packetPtr: UnsafeMutablePointer<MIDIPacket> = UnsafeMutablePointer.allocate(capacity: 1)
            packetPtr.initialize(to: packet)
            for _ in 0 ..< packets.numPackets {
                handleMIDIMessage(packetPtr.pointee)
                packetPtr = MIDIPacketNext(packetPtr)
            }
            packetPtr.deinitialize()
        }
        if result != OSStatus(noErr) {
            print("error creating destination : \(result)")
        }
    }

}
