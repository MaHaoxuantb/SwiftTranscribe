import Foundation
import XCTest

final class MarkdownRendererTests: XCTestCase {
    func testTimestampFormatting() {
        XCTAssertEqual(MarkdownRenderer.timestamp(0), "00:00:00")
        XCTAssertEqual(MarkdownRenderer.timestamp(3_723.9), "01:02:03")
        XCTAssertEqual(MarkdownRenderer.timestamp(-5), "00:00:00")
    }

    func testRendersSortedNormalizedEscapedSegments() {
        let transcript = Transcript(
            sourceURL: URL(fileURLWithPath: "/tmp/A [demo].mov"),
            locale: Locale(identifier: "en-US"),
            duration: 75,
            segments: [
                TranscriptSegment(startTime: 65, endTime: 70, text: "second   *part*"),
                TranscriptSegment(startTime: 2, endTime: 4, text: "first\nline"),
            ]
        )
        let markdown = MarkdownRenderer.render(transcript)

        XCTAssertTrue(markdown.hasPrefix("# A \\[demo\\]"))
        XCTAssertTrue(markdown.contains("- Duration: 00:01:15"))
        XCTAssertLessThan(markdown.range(of: "## [00:00:02]")!.lowerBound, markdown.range(of: "## [00:01:05]")!.lowerBound)
        XCTAssertTrue(markdown.contains("first line"))
        XCTAssertTrue(markdown.contains("second \\*part\\*"))
    }

    func testGroupsNearbyResultsIntoReadableTimedSections() {
        let transcript = Transcript(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.mov"),
            locale: Locale(identifier: "en-US"),
            duration: 30,
            segments: [
                TranscriptSegment(startTime: 1, endTime: 2, text: "One."),
                TranscriptSegment(startTime: 3, endTime: 4, text: "Two."),
                TranscriptSegment(startTime: 17, endTime: 18, text: "Three."),
            ]
        )
        let markdown = MarkdownRenderer.render(transcript)

        XCTAssertTrue(markdown.contains("## [00:00:01]\n\nOne. Two."))
        XCTAssertTrue(markdown.contains("## [00:00:17]\n\nThree."))
        XCTAssertEqual(markdown.components(separatedBy: "## [").count - 1, 2)
    }
}
