import Foundation

@main
struct SwiftTranscribeApp {
    static func main() async {
        let exitCode = await run()
        if exitCode != .success {
            Foundation.exit(exitCode.rawValue)
        }
    }

    private static func run() async -> ExitCode {
        do {
            let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            if options.showsHelp {
                print(CLIOptions.usage)
                return .success
            }
            if options.showsVersion {
                print("SwiftTranscribe \(CLIOptions.version)")
                return .success
            }

            let selectedInputURL: URL?
            if let providedInputURL = options.inputURL {
                selectedInputURL = providedInputURL
            } else {
                selectedInputURL = await FilePicker.chooseMediaFile()
            }
            guard let inputURL = selectedInputURL else {
                StandardError.write("No file selected; transcription cancelled.")
                return .success
            }
            StandardError.write("Selected: \(inputURL.path)")
            let outputURL = options.outputURL(for: inputURL)
            guard inputURL.standardizedFileURL != outputURL.standardizedFileURL else {
                throw SwiftTranscribeError.outputConflict("Input and output paths must be different.")
            }

            let accessingSecurityScopedResource = inputURL.startAccessingSecurityScopedResource()
            defer {
                if accessingSecurityScopedResource {
                    inputURL.stopAccessingSecurityScopedResource()
                }
            }

            let locale = options.localeIdentifier.map(Locale.init(identifier:)) ?? .current
            let transcript = try await TranscriptionService().transcribe(
                url: inputURL,
                requestedLocale: locale,
                progress: { StandardError.write($0) }
            )
            let markdown = MarkdownRenderer.render(transcript)
            try TranscriptWriter.write(markdown, to: outputURL, overwrite: options.overwrite)
            print(outputURL.path)
            return .success
        } catch let error as SwiftTranscribeError {
            StandardError.write("error: \(error.localizedDescription)")
            if case .invalidArguments = error {
                StandardError.write("Run 'SwiftTranscribe --help' for usage.")
            }
            return error.exitCode
        } catch {
            StandardError.write("error: \(error.localizedDescription)")
            return .transcription
        }
    }
}
