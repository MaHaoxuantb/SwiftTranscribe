import Foundation

enum MarkdownRenderer {
    static func render(_ transcript: Transcript) -> String {
        let title = escape(transcript.sourceURL.deletingPathExtension().lastPathComponent)
        let source = inlineCode(transcript.sourceURL.lastPathComponent)
        let locale = inlineCode(transcript.locale.identifier)
        var lines = [
            "# \(title)",
            "",
            "- Source: `\(source)`",
            "- Locale: `\(locale)`",
            "- Duration: \(timestamp(transcript.duration))",
            "",
        ]

        let sections = timedSections(from: transcript.segments)
        for section in sections {
            lines.append("## [\(timestamp(section.startTime))]")
            lines.append("")
            lines.append(escape(section.text))
            lines.append("")
        }

        if sections.isEmpty {
            lines.append("_No speech was detected._")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        return String(format: "%02d:%02d:%02d", wholeSeconds / 3600, (wholeSeconds % 3600) / 60, wholeSeconds % 60)
    }

    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }

    static func escape(_ text: String) -> String {
        var escaped = text
        for character in ["\\", "*", "_", "[", "]", "<", ">", "#", "|"] {
            escaped = escaped.replacingOccurrences(of: character, with: "\\\(character)")
        }
        return escaped
    }

    private static func inlineCode(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "\\`")
    }

    private static func timedSections(from segments: [TranscriptSegment]) -> [(startTime: TimeInterval, text: String)] {
        let maximumSectionDuration: TimeInterval = 15
        var sections: [(startTime: TimeInterval, text: String)] = []
        var sectionStart: TimeInterval?
        var fragments: [String] = []

        func appendSection() {
            guard let start = sectionStart, !fragments.isEmpty else { return }
            sections.append((start, normalize(fragments.joined(separator: " "))))
        }

        for segment in segments.sorted(by: segmentOrder) {
            let text = normalize(segment.text)
            guard !text.isEmpty else { continue }
            if let start = sectionStart, segment.startTime - start >= maximumSectionDuration {
                appendSection()
                fragments.removeAll(keepingCapacity: true)
                sectionStart = segment.startTime
            } else if sectionStart == nil {
                sectionStart = segment.startTime
            }
            fragments.append(text)
        }
        appendSection()
        return sections
    }

    private static func segmentOrder(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment) -> Bool {
        lhs.startTime == rhs.startTime ? lhs.endTime < rhs.endTime : lhs.startTime < rhs.startTime
    }
}
