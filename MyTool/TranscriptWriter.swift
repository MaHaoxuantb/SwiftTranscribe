import Foundation

enum TranscriptWriter {
    static func write(_ markdown: String, to outputURL: URL, overwrite: Bool) throws {
        let fileManager = FileManager.default
        let destination = outputURL.standardizedFileURL
        guard destination.pathExtension.lowercased() == "md" else {
            throw SwiftTranscribeError.invalidArguments("Output file must use the .md extension.")
        }
        guard fileManager.fileExists(atPath: destination.deletingLastPathComponent().path) else {
            throw SwiftTranscribeError.outputConflict("Output directory does not exist: \(destination.deletingLastPathComponent().path)")
        }

        let exists = fileManager.fileExists(atPath: destination.path)
        if exists && !overwrite {
            throw SwiftTranscribeError.outputConflict("Output already exists; use --overwrite to replace it: \(destination.path)")
        }

        let temporaryURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            try Data(markdown.utf8).write(to: temporaryURL, options: [.withoutOverwriting])
            if exists {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destination)
            }
        } catch let error as SwiftTranscribeError {
            throw error
        } catch {
            throw SwiftTranscribeError.outputConflict("Unable to write transcript: \(error.localizedDescription)")
        }
    }
}
