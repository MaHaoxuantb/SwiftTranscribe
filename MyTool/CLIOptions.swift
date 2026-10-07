import Foundation

struct CLIOptions: Equatable {
    var inputURL: URL?
    var outputURL: URL?
    var localeIdentifier: String?
    var overwrite = false
    var showsHelp = false
    var showsVersion = false

    static let version = "1.0.0"

    static func parse(_ arguments: [String], currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 0

        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else {
                throw SwiftTranscribeError.invalidArguments("Missing value for \(option).")
            }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--locale", "-l":
                let value = try value(after: argument)
                guard !value.isEmpty else {
                    throw SwiftTranscribeError.invalidArguments("Locale cannot be empty.")
                }
                options.localeIdentifier = value
            case "--output", "-o":
                options.outputURL = resolvePath(try value(after: argument), relativeTo: currentDirectory)
            case "--overwrite", "-f":
                options.overwrite = true
            case "--help", "-h":
                options.showsHelp = true
            case "--version", "-v":
                options.showsVersion = true
            case "--":
                index += 1
                while index < arguments.count {
                    guard options.inputURL == nil else {
                        throw SwiftTranscribeError.invalidArguments("Only one input file is supported.")
                    }
                    options.inputURL = resolvePath(arguments[index], relativeTo: currentDirectory)
                    index += 1
                }
                continue
            default:
                if argument.hasPrefix("-") {
                    throw SwiftTranscribeError.invalidArguments("Unknown option: \(argument)")
                }
                guard options.inputURL == nil else {
                    throw SwiftTranscribeError.invalidArguments("Only one input file is supported.")
                }
                options.inputURL = resolvePath(argument, relativeTo: currentDirectory)
            }
            index += 1
        }

        return options
    }

    func outputURL(for inputURL: URL) -> URL {
        outputURL ?? inputURL.deletingPathExtension().appendingPathExtension("transcript.md")
    }

    private static func resolvePath(_ path: String, relativeTo directory: URL) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return directory.appendingPathComponent(expanded).standardizedFileURL
    }

    static let usage = """
    Usage: SwiftTranscribe [input-file] [options]

    Transcribe an audio or video file locally with Apple's Speech framework.
    When input-file is omitted, a native file picker is displayed.

    Options:
      -l, --locale <identifier>  Recognition locale (default: system locale)
      -o, --output <file>        Markdown output path
      -f, --overwrite            Replace an existing output file
      -h, --help                 Show this help
      -v, --version              Show the version
    """
}
