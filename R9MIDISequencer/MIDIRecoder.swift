//
//  MusicSequenceRecoder.swift
//  R9MIDISequencer
//
//  Created by taisuke fujita on 2017/03/30.
//
//

import AVFoundation
import CoreMIDI
import AudioToolbox

public class MIDIRecoder {
    var musicSequence: MusicSequence?
    var track: MusicTrack?
    var startTime: MusicTimeStamp = 0
    var noteStartTimes: [UInt8: MusicTimeStamp] = [:]
    
    public init() {
        var status = NewMusicSequence(&musicSequence)
        if status != OSStatus(noErr) {
            print("Error creating music sequence \(status)")
        }
        status = MusicSequenceNewTrack(musicSequence!, &track)
        if status != OSStatus(noErr) {
            print("Error creating track \(status)")
        }
    }
    
    public func prepare(bpm: TimeInterval = 60.0) {
        startTime = Date().timeIntervalSince1970
        var tempoTrack: MusicTrack?
        var status = MusicSequenceGetTempoTrack(musicSequence!, &tempoTrack)
        if status != OSStatus(noErr) {
            print("Error getting tempo track: \(status)")
        }
        status = MusicTrackNewExtendedTempoEvent(tempoTrack!, 0, bpm)
        if status != OSStatus(noErr) {
            print("Error adding tempo to track: \(status)");
        }
    }
    
    public func noteOn(note: UInt8) {
        noteStartTimes[note] = Date().timeIntervalSince1970
    }
    
    public func noteOff(note: UInt8) {
        guard let noteStartTime = noteStartTimes[note] else {
            return
        }
        let duration = Date().timeIntervalSince1970 - noteStartTime
        let beat = Date().timeIntervalSince1970 - startTime - duration
        var message = MIDINoteMessage(channel: 0,
                                      note: note,
                                      velocity: 100,
                                      releaseVelocity: 0,
                                      duration: Float32(duration))
        let status = MusicTrackNewMIDINoteEvent(track!, beat, &message)
        if status != OSStatus(noErr) {
            print("error creating midi note event \(status)")
        }
    }
    
    public func save(destinationURL: URL, fileName: String) {
        guard let sequence = musicSequence else {
            return
        }
        let destinationFilePath = destinationURL.appendingPathComponent(fileName)
        // Save
        let status = MusicSequenceFileCreate(sequence, destinationFilePath as CFURL, .midiType, [.eraseFile], 0)
        if status != OSStatus(noErr) {
            print("error creating midi file \(status)")
        }
    }
}
