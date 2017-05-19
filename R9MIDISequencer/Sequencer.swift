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
        OperationQueue.main.addOperation({ [weak delegate = mySelf.delegate] in
            delegate?.midiSequenceDidFinish()
        })
    }
    
    var enableLooping = false
    
    var musicSequence: MusicSequence?
    var musicPlayer: MusicPlayer?
    
    var midiClient = MIDIClientRef()
    var midiDestination = MIDIEndpointRef()
    
    public private(set) var lengthInBeats: TimeInterval = 0.0
    
    public private(set) var lengthInSeconds: TimeInterval = 0.0
    
    // Beats Per Minute
    public private(set) var bpm: TimeInterval = 0.0
    
    weak public var delegate: MIDIMessageListener?
    
    
    public var currentPositionInSeconds: TimeInterval {
        get {
            guard let player = musicPlayer else {
                return 0.0
            }
            var time: MusicTimeStamp = 0.0
            MusicPlayerGetTime(player, &time)
            return time
        }
    }
    
    public init(enableLooping: Bool) {
        
        self.enableLooping = enableLooping
        
        var result = OSStatus(noErr)
        result = NewMusicSequence(&musicSequence)
        if result != OSStatus(noErr) {
            print("error creating sequence : \(result)")
        }
        
        let destinationCount = MIDIGetNumberOfDestinations()
        print("DestinationCount: \(destinationCount)")
        
        result = MIDIClientCreateWithBlock("MIDI Client" as CFString, &midiClient) { midiNotification in
            print(midiNotification)
        }
        if result != OSStatus(noErr) {
            print("error creating client : \(result)")
        }
        
        Thread.sleep(forTimeInterval: 0.2) // スリープを入れないとDestinationのコールバックが呼ばれない
        createMIDIDestination()
    }
    
    public convenience init() {
        self.init(enableLooping: false)
    }
    
    deinit {
        stop()
        if let seq = musicSequence {
            DisposeMusicSequence(seq)
        }
        MIDIEndpointDispose(midiDestination)
        MIDIClientDispose(midiClient)
    }
    
    public func playWithMidiURL(_ midiFileUrl: URL) {
        stop()

        guard let sequence = musicSequence else {
            return
        }
        
        var result = OSStatus(noErr)
        result = NewMusicPlayer(&musicPlayer)
        if result != OSStatus(noErr) {
            print("error creating player : \(result)")
            return
        }
        
        // MIDIファイルの読み込み
        MusicSequenceFileLoad(sequence, midiFileUrl as CFURL, .midiType, MusicSequenceLoadFlags.smf_ChannelsToTracks)
        
        // bpmの取得
        MusicSequenceGetBeatsForSeconds(sequence, 60, &bpm)
        
        // シーケンサにEndPointをセットする
        // trackが決まってからセットしないとだめ
        result = MusicSequenceSetMIDIEndpoint(sequence, midiDestination);
        if result != OSStatus(noErr) {
            print("error creating endpoint : \(result)")
        }
        
        var musicTrack: MusicTrack? = nil
        var sequenceLength: MusicTimeStamp = 0
        var tracks: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &tracks)
        for i in 0 ..< tracks {
            
            if enableLooping {
                var loopInfo = MusicTrackLoopInfo(loopDuration: 1, numberOfLoops: 0)
                let lisize: UInt32 = 0
                let status = MusicTrackSetProperty(musicTrack!, kSequenceTrackProperty_LoopInfo, &loopInfo, lisize )
                if status != OSStatus(noErr) {
                    print("Error setting loopinfo on track \(status)")
                }
            }
            
            var trackLength: MusicTimeStamp = 0
            var trackLengthSize: UInt32 = 0
            
            MusicSequenceGetIndTrack(sequence, i, &musicTrack)
            MusicTrackGetProperty(musicTrack!, kSequenceTrackProperty_TrackLength, &trackLength, &trackLengthSize)
            
            if sequenceLength < trackLength {
                sequenceLength = trackLength
            }
        }
        
        lengthInSeconds = sequenceLength
        
        // 曲の最後にコールバックを仕込む
        MusicSequenceSetUserCallback(sequence, callBack, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
        let userData: UnsafeMutablePointer<MusicEventUserData> = UnsafeMutablePointer.allocate(capacity: 1)
        MusicTrackNewUserEvent(musicTrack!, sequenceLength, userData)
        
        // play
        MusicPlayerSetSequence(musicPlayer!, sequence)
        MusicPlayerPreroll(musicPlayer!)
        MusicPlayerStart(musicPlayer!)
    }
    
    public func restart() {
        if let player = musicPlayer {
            MusicPlayerPreroll(player)
            MusicPlayerStart(player)
        }
    }
    
    public func stop() {
        if let player = musicPlayer {
            MusicPlayerStop(player)
            DisposeMusicPlayer(player)
        }
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
