import Foundation
import XCTest

final class TranscriptWriterTests: XCTestCase {
    func testWritesAndRequiresOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("result.md")

        try TranscriptWriter.write("first", to: output, overwrite: false)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "first")
        XCTAssertThrowsError(try TranscriptWriter.write("second", to: output, overwrite: false))
        try TranscriptWriter.write("second", to: output, overwrite: true)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "second")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".tmp") })
    }
}
