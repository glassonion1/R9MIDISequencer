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

@available(iOS 9.0, *)
@available(OSX 10.11, *)
open class Sequencer {
    
    let callBack: @convention(c) (UnsafeMutableRawPointer?, MusicSequence, MusicTrack, MusicTimeStamp, UnsafePointer<MusicEventUserData>, MusicTimeStamp, MusicTimeStamp) -> Void = {
        (obj, seq, mt, timestamp, userData, timestamp2, timestamp3) in
        // Cタイプ関数なのでselfを使えません
        unowned let mySelf: Sequencer = unsafeBitCast(obj, to: Sequencer.self)
        if mySelf.enableLooping {
            return
        }
        OperationQueue.main.addOperation({
            mySelf.delegate?.midiSequenceDidFinish()
            if let player = mySelf.musicPlayer {
                MusicPlayerSetTime(player, 0)
            }
        })
    }
    
    var musicSequence: MusicSequence?
    var musicPlayer: MusicPlayer?
    
    var midiClient = MIDIClientRef()
    var midiDestination = MIDIEndpointRef()
    
    public private(set) var lengthInSeconds: TimeInterval = 0.0
    
    // Beats Per Minute
    public private(set) var bpm: TimeInterval = 0.0
    
    weak public var delegate: MIDIMessageListener?
    
    public var enableLooping = false
    
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
    
    public init() {
        
        var result = OSStatus(noErr)
        result = NewMusicPlayer(&musicPlayer)
        if result != OSStatus(noErr) {
            print("error creating player : \(result)")
            return
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
    
    deinit {
        stop()
        if let player = musicPlayer {
            DisposeMusicPlayer(player)
        }
        MIDIEndpointDispose(midiDestination)
        MIDIClientDispose(midiClient)
    }
    
    public func loadMIDIURL(_ midiFileUrl: URL) {
        // 再生中だったら止める
        stop()
        
        var result = NewMusicSequence(&musicSequence)
        guard let sequence = musicSequence else {
            print("error creating sequence : \(result)")
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
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        for i in 0 ..< trackCount {
            var trackLength: MusicTimeStamp = 0
            var trackLengthSize: UInt32 = 0
            
            MusicSequenceGetIndTrack(sequence, i, &musicTrack)
            MusicTrackGetProperty(musicTrack!, kSequenceTrackProperty_TrackLength, &trackLength, &trackLengthSize)
            
            if sequenceLength < trackLength {
                sequenceLength = trackLength
            }
            
            if enableLooping {
                var loopInfo = MusicTrackLoopInfo(loopDuration: 1, numberOfLoops: 0)
                let lisize: UInt32 = 0
                let status = MusicTrackSetProperty(musicTrack!, kSequenceTrackProperty_LoopInfo, &loopInfo, lisize )
                if status != OSStatus(noErr) {
                    print("Error setting loopinfo on track \(status)")
                }
            }
        }
        
        lengthInSeconds = sequenceLength
        
        // 曲の最後にコールバックを仕込む
        result = MusicSequenceSetUserCallback(sequence, callBack, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        if result != OSStatus(noErr) {
            print("error set user callback : \(result)")
        }
        
        let userData: UnsafeMutablePointer<MusicEventUserData> = UnsafeMutablePointer.allocate(capacity: 1)
        result = MusicTrackNewUserEvent(musicTrack!, sequenceLength, userData)
        if result != OSStatus(noErr) {
            print("error new user event : \(result)")
        }
    }
    
    public func play() {
        guard let sequence = musicSequence else {
            return
        }
        guard let player = musicPlayer else {
            return
        }
        MusicPlayerSetSequence(player, sequence)
        MusicPlayerPreroll(player)
        MusicPlayerStart(player)
    }
    
    public func playWithMIDIURL(_ midiFileUrl: URL) {
        loadMIDIURL(midiFileUrl)
        play()
    }
    
    public func stop() {
        if let sequence = musicSequence {
            DisposeMusicSequence(sequence)
        }
        if let player = musicPlayer {
            MusicPlayerStop(player)
            MusicPlayerSetTime(player, 0)
        }
    }
    
    public func addMIDINoteEvent(trackNumber: UInt32,
                    noteNumber: UInt8,
                    velocity: UInt8,
                    position: MusicTimeStamp,
                    duration: Float32,
                    channel: UInt8 = 0) {
        guard let sequence = musicSequence else {
            return
        }
        var musicTrack: MusicTrack? = nil
        var result = MusicSequenceGetIndTrack(sequence, trackNumber, &musicTrack)
        if result != OSStatus(noErr) {
            print("error get track index: \(trackNumber) \(result)")
        }
        guard let track = musicTrack else {
            return
        }
        var message = MIDINoteMessage(channel: channel,
                                      note: noteNumber,
                                      velocity: velocity,
                                      releaseVelocity: 0,
                                      duration: duration)
        result = MusicTrackNewMIDINoteEvent(track, position, &message)
        if result != OSStatus(noErr) {
            print("error creating midi note event \(result)")
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
            let status = UInt8(packet.data.0)
            let d1 = UInt8(packet.data.1)
            let d2 = UInt8(packet.data.2)
            let rawStatus = status & 0xF0 // without channel
            let channel = UInt8(status & 0x0F)
            
            switch rawStatus {
            case 0x80, 0x90:
                // weak delegateにしないとメモリリークする
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
        }
        if result != OSStatus(noErr) {
            print("error creating destination : \(result)")
        }
    }

}
