import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(R9MIDISequencerTests.allTests),
    ]
}
#endif
