//
//  Recorder.swift
//  R9MIDISequencer
//
//  Created by taisuke fujita on 2017/03/30.
//
//

import AVFoundation
import CoreMIDI
import AudioToolbox

@available(iOS 9.0, *)
@available(OSX 10.11, *)
public class Recorder {
    var musicSequence: MusicSequence?
    var track: MusicTrack?
    
    var midiClient = MIDIClientRef()
    var midiDestination = MIDIEndpointRef()
    
    var startTime: MusicTimeStamp = 0
    var noteStartTimes: [UInt8: MusicTimeStamp] = [:]
    
    public var bpm: TimeInterval = 60.0
    
    public init() {
        
        let result = MIDIClientCreateWithBlock("MIDI Client" as CFString, &midiClient) { midiNotification in
            print(midiNotification)
        }
        if result != OSStatus(noErr) {
            print("error creating client : \(result)")
        }
        
        Thread.sleep(forTimeInterval: 0.2) // スリープを入れないとDestinationのコールバックが呼ばれない
        createMIDIDestination()
    }
    
    deinit {
        MIDIEndpointDispose(midiDestination)
        MIDIClientDispose(midiClient)
        if let ms = musicSequence {
            if let mt = track {
                MusicSequenceDisposeTrack(ms, mt)
            }
            DisposeMusicSequence(ms)
        }
    }
    
    public func record() {
        startTime = Date().timeIntervalSince1970
        
        var result = NewMusicSequence(&musicSequence)
        if result != OSStatus(noErr) {
            print("Error creating music sequence \(result)")
        }
        result = MusicSequenceNewTrack(musicSequence!, &track)
        if result != OSStatus(noErr) {
            print("Error creating track \(result)")
        }
        
        var tempoTrack: MusicTrack?
        var status = MusicSequenceGetTempoTrack(musicSequence!, &tempoTrack)
        if status != OSStatus(noErr) {
            print("Error getting tempo track: \(status)")
        }
        status = MusicTrackNewExtendedTempoEvent(tempoTrack!, 0, bpm)
        if status != OSStatus(noErr) {
            print("Error adding tempo to track: \(status)");
        }
        
        result = MusicSequenceSetMIDIEndpoint(musicSequence!, midiDestination);
        if result != OSStatus(noErr) {
            print("error creating endpoint : \(result)")
        }
    }
    
    public func save(fileURL: URL) {
        guard let sequence = musicSequence else {
            return
        }
        guard startTime != 0 else {
            return
        }
        startTime = 0
        // Save
        let status = MusicSequenceFileCreate(sequence, fileURL as CFURL, .midiType, [.eraseFile], 0)
        if status != OSStatus(noErr) {
            print("error creating midi file \(status)")
        }
        
        if let mt = track {
            MusicSequenceDisposeTrack(sequence, mt)
        }
        DisposeMusicSequence(sequence)
    }
    
    private func createMIDIDestination() {
        /// This block will be method then memory leak
        /// @see https://github.com/genedelisa/Swift2MIDI/blob/master/Swift2MIDI/ViewController.swift
        /// - parameter packet: パケットデータ
        let handleMIDIMessage = { [weak self] (packet: MIDIPacket) in
            guard let localSelf = self else {
                return
            }
            guard localSelf.startTime != 0 else {
                return
            }
            guard let mt = localSelf.track else {
                return
            }
            let status = UInt8(packet.data.0)
            let d1 = UInt8(packet.data.1)
            let d2 = UInt8(packet.data.2)
            let rawStatus = status & 0xF0 // without channel
            let channel = UInt8(status & 0x0F)
            
            switch rawStatus {
            case 0x80, 0x90:
                let position = Date().timeIntervalSince1970 - localSelf.startTime
                var message = MIDINoteMessage(channel: channel,
                                              note: d1,
                                              velocity: d2,
                                              releaseVelocity: d2,
                                              duration: 0)
                let status = MusicTrackNewMIDINoteEvent(mt, position, &message)
                if status != OSStatus(noErr) {
                    print("error creating midi note event \(status)")
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
        
        var result = OSStatus(noErr)
        let name = Constants.midiRecorderDestinationName as CFString
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
