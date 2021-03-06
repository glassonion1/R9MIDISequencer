# R9MIDISequencer


MIDI Sequencer for iOS on swift.

# Feature

## Sequencing

R9MIDISequencer now features a full MIDI Sequencer with EXS24 and SoundFont samplers which can be tied to your instruments for awesome, accurate playback.

## Example Code

Play note using the sampler:

```swift
import R9MIDISequencer

let url = Bundle.main.url(forResource: “Sound Font File Name”,
        withExtension: "sf2",
        subdirectory: "Sounds")
        
let sampler = Sampler(bankURL: url!, program: 0, bankMSB: 0x79, bankLSB: 0, channelNumber: 1)

// Play the note C
sampler.startNoteWithNumber(36)
// Play the note G
sampler.startNoteWithNumber(43)
```

Play MIDI file using the Sequencer:

```swift
let sequencer = Sequencer(sampler: sampler, enableLooping: true)

let midiUrl = Bundle.main.url(forResource: “MIDI File",
        withExtension: "mid")
sequencer.playWithMidiURL(midiUrl)
```

Callback from MIDI message

```swift
class GameScene: SKScene, MIDIMessageListener {
    override func didMoveToView(view: SKView) {
        
        ...Initialize sampler
        
        let sequencer = Sequencer(sampler: sampler, enableLooping: true)
        sequencer.addListener(self)
        
        ...Play MIDI
        
    }
    
    func midiNoteOn(note: UInt32, velocity: UInt32, channel: UInt32) {
        // Call back of note on message.
    }
    func midiNoteOff(note: UInt32, channel: UInt32) {
        // Call back of note off message.
    }
    func midiSequenceDidFinish() {
        // Call back of finish MIDI sequence.
    }
}
```

## Installation

### Swift Package Manager
Create a Package.swift file.
```swift
import PackageDescription

let package = Package(
  name: "RxTestProject",
  dependencies: [
    .package(url: "https://github.com/glassonion1/R9MIDISequencer.git", from: "1.5.1")
  ],
  targets: [
    .target(name: "RxTestProject", dependencies: ["R9MIDISequencer"])
  ]
)
```

## License

R9MIDISequencer is available under the MIT license. See the LICENSE file for more info.
