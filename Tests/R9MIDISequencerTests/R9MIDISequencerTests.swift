import XCTest
@testable import R9MIDISequencer

final class R9MIDISequencerTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(R9MIDISequencer().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
