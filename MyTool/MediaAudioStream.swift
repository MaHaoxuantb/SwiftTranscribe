@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

struct MediaAudioStream: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput

    private let reader: ReaderState
    let duration: TimeInterval

    struct AsyncIterator: AsyncIteratorProtocol {
        private let reader: ReaderState

        fileprivate init(reader: ReaderState) {
            self.reader = reader
        }

        mutating func next() async throws -> AnalyzerInput? {
            try await reader.next()
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(reader: reader)
    }

    static func open(
        url: URL,
        analyzerFormat: AVAudioFormat,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> MediaAudioStream {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SwiftTranscribeError.unsupportedMedia("Input file does not exist: \(url.path)")
        }

        let asset = AVURLAsset(url: url)
        let duration: CMTime
        let tracks: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration)
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw SwiftTranscribeError.unsupportedMedia("Unable to inspect the media file: \(error.localizedDescription)")
        }
        guard let audioTrack = tracks.first else {
            throw SwiftTranscribeError.unsupportedMedia("The selected file has no readable audio track.")
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw SwiftTranscribeError.unsupportedMedia("Unable to open the media file: \(error.localizedDescription)")
        }

        let pcmDescription: (bitDepth: Int, isFloat: Bool)
        switch analyzerFormat.commonFormat {
        case .pcmFormatInt16:
            pcmDescription = (16, false)
        case .pcmFormatInt32:
            pcmDescription = (32, false)
        case .pcmFormatFloat32:
            pcmDescription = (32, true)
        case .pcmFormatFloat64:
            pcmDescription = (64, true)
        default:
            throw SwiftTranscribeError.transcription("SpeechAnalyzer requested an unsupported PCM format.")
        }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: analyzerFormat.sampleRate,
            AVNumberOfChannelsKey: Int(analyzerFormat.channelCount),
            AVLinearPCMBitDepthKey: pcmDescription.bitDepth,
            AVLinearPCMIsFloatKey: pcmDescription.isFloat,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: !analyzerFormat.isInterleaved,
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw SwiftTranscribeError.unsupportedMedia("The audio track cannot be decoded into a transcription-compatible format.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw SwiftTranscribeError.unsupportedMedia(reader.error?.localizedDescription ?? "The media reader could not start.")
        }

        return MediaAudioStream(
            reader: ReaderState(reader: reader, output: output, duration: duration.seconds, report: progress),
            duration: duration.seconds
        )
    }

    fileprivate static func analyzerInput(from sampleBuffer: CMSampleBuffer) throws -> AnalyzerInput {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw SwiftTranscribeError.unsupportedMedia("A decoded audio buffer has no usable format.")
        }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr, requiredSize > 0 else {
            throw SwiftTranscribeError.unsupportedMedia("Unable to inspect decoded audio (OSStatus \(status)).")
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: requiredSize, alignment: 16)
        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        retainedBlockBuffer = nil
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else {
            rawPointer.deallocate()
            throw SwiftTranscribeError.unsupportedMedia("Unable to read decoded audio (OSStatus \(status)).")
        }

        let retainedData = retainedBlockBuffer
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            bufferListNoCopy: audioBufferList,
            deallocator: { _ in
                _ = retainedData
                rawPointer.deallocate()
            }
        ) else {
            rawPointer.deallocate()
            throw SwiftTranscribeError.unsupportedMedia("Unable to create an audio buffer for transcription.")
        }
        pcmBuffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        return AnalyzerInput(buffer: pcmBuffer, bufferStartTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private actor ReaderState {
    private let reader: UncheckedSendableBox<AVAssetReader>
    private let output: UncheckedSendableBox<AVAssetReaderTrackOutput>
    private let duration: TimeInterval
    private let report: @Sendable (String) -> Void
    private var finished = false
    private var lastReportedPercent = 0

    init(
        reader: AVAssetReader,
        output: AVAssetReaderTrackOutput,
        duration: TimeInterval,
        report: @escaping @Sendable (String) -> Void
    ) {
        self.reader = UncheckedSendableBox(reader)
        self.output = UncheckedSendableBox(output)
        self.duration = duration
        self.report = report
    }

    func next() throws -> AnalyzerInput? {
        if finished { return nil }
        if Task.isCancelled {
            finished = true
            reader.value.cancelReading()
            throw CancellationError()
        }

        while let sampleBuffer = output.value.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { continue }
            reportProgress(for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            return try MediaAudioStream.analyzerInput(from: sampleBuffer)
        }

        finished = true
        switch reader.value.status {
        case .completed:
            if lastReportedPercent < 100 {
                lastReportedPercent = 100
                report("Transcribing: 100%")
            }
            return nil
        case .cancelled:
            throw CancellationError()
        case .failed:
            throw SwiftTranscribeError.unsupportedMedia(
                reader.value.error?.localizedDescription ?? "Media decoding failed."
            )
        default:
            throw SwiftTranscribeError.unsupportedMedia("Media decoding ended unexpectedly.")
        }
    }

    private func reportProgress(for time: CMTime) {
        guard duration.isFinite, duration > 0, time.seconds.isFinite else { return }
        let percent = min(99, max(0, Int((time.seconds / duration) * 100)))
        guard percent >= lastReportedPercent + 5 else { return }
        lastReportedPercent = percent - (percent % 5)
        report("Transcribing: \(lastReportedPercent)%")
    }
}
