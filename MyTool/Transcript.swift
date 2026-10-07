import CoreMedia
import Foundation

struct TranscriptSegment: Equatable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.startTime = max(0, startTime.isFinite ? startTime : 0)
        self.endTime = max(self.startTime, endTime.isFinite ? endTime : self.startTime)
        self.text = text
    }

    init(range: CMTimeRange, text: String) {
        self.init(
            startTime: range.start.seconds,
            endTime: CMTimeRangeGetEnd(range).seconds,
            text: text
        )
    }
}

struct Transcript: Sendable {
    let sourceURL: URL
    let locale: Locale
    let duration: TimeInterval
    let segments: [TranscriptSegment]
}
