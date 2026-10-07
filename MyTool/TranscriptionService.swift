import AVFoundation
import Foundation
import Speech

struct TranscriptionService {
    func transcribe(url: URL, requestedLocale: Locale, progress: @escaping @Sendable (String) -> Void) async throws -> Transcript {
        guard SpeechTranscriber.isAvailable else {
            throw SwiftTranscribeError.transcription("SpeechTranscriber is unavailable on this Mac.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw SwiftTranscribeError.unsupportedLocale("Speech transcription does not support locale '\(requestedLocale.identifier)'.")
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
        try await installAssetsIfNeeded(for: transcriber, progress: progress)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SwiftTranscribeError.transcription("No compatible audio format is available for locale '\(locale.identifier)'.")
        }
        let media = try await MediaAudioStream.open(url: url, analyzerFormat: analyzerFormat, progress: progress)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        progress("Transcribing \(url.lastPathComponent)…")
        async let collectedSegments: [TranscriptSegment] = collectResults(from: transcriber)
        do {
            if let lastSample = try await analyzer.analyzeSequence(media) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let segments = try await collectedSegments
            return Transcript(sourceURL: url, locale: locale, duration: media.duration, segments: segments)
        } catch let error as SwiftTranscribeError {
            await analyzer.cancelAndFinishNow()
            throw error
        } catch {
            await analyzer.cancelAndFinishNow()
            throw SwiftTranscribeError.transcription(error.localizedDescription)
        }
    }

    private func collectResults(from transcriber: SpeechTranscriber) async throws -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        for try await result in transcriber.results where result.isFinal {
            segments.append(TranscriptSegment(range: result.range, text: String(result.text.characters)))
        }
        return segments.sorted {
            $0.startTime == $1.startTime ? $0.endTime < $1.endTime : $0.startTime < $1.startTime
        }
    }

    private func installAssetsIfNeeded(
        for transcriber: SpeechTranscriber,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            throw SwiftTranscribeError.unsupportedLocale("Required speech assets are unavailable for this locale.")
        case .supported, .downloading:
            break
        @unknown default:
            break
        }

        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                return
            }
            progress("Downloading speech assets for \(transcriber.selectedLocales.first?.identifier ?? "the selected locale")…")
            let observer = AssetProgressObserver(progress: request.progress, report: progress)
            defer { observer.invalidate() }
            try await request.downloadAndInstall()
        } catch {
            throw SwiftTranscribeError.assetInstallation(error.localizedDescription)
        }
    }
}

private final class AssetProgressObserver: @unchecked Sendable {
    private let progress: Progress
    private let report: @Sendable (String) -> Void
    private var observation: NSKeyValueObservation?

    init(progress: Progress, report: @escaping @Sendable (String) -> Void) {
        self.progress = progress
        self.report = report
        observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [report] progress, _ in
            report("Downloading speech assets: \(Int(progress.fractionCompleted * 100))%")
        }
    }

    func invalidate() {
        observation?.invalidate()
        observation = nil
    }
}
