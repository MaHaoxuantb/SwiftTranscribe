import Foundation
import XCTest

final class CLIOptionsTests: XCTestCase {
    func testParsesPathLocaleOutputAndOverwrite() throws {
        let directory = URL(fileURLWithPath: "/tmp/work")
        let options = try CLIOptions.parse(
            ["recording.mov", "--locale", "en-US", "--output", "notes.md", "--overwrite"],
            currentDirectory: directory
        )

        XCTAssertEqual(options.inputURL?.path, "/tmp/work/recording.mov")
        XCTAssertEqual(options.outputURL?.path, "/tmp/work/notes.md")
        XCTAssertEqual(options.localeIdentifier, "en-US")
        XCTAssertTrue(options.overwrite)
    }

    func testDefaultOutputName() throws {
        let input = URL(fileURLWithPath: "/tmp/interview.m4a")
        XCTAssertEqual(CLIOptions().outputURL(for: input).path, "/tmp/interview.transcript.md")
    }

    func testRejectsUnknownOptionAndMultipleInputs() {
        XCTAssertThrowsError(try CLIOptions.parse(["--wat"]))
        XCTAssertThrowsError(try CLIOptions.parse(["one.wav", "two.wav"]))
    }
}
