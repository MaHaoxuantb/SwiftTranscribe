import Foundation

enum ExitCode: Int32 {
    case success = 0
    case invalidArguments = 2
    case unsupportedMedia = 3
    case unsupportedLocale = 4
    case assetInstallation = 5
    case transcription = 6
    case outputConflict = 7
}

enum SwiftTranscribeError: LocalizedError {
    case invalidArguments(String)
    case unsupportedMedia(String)
    case unsupportedLocale(String)
    case assetInstallation(String)
    case transcription(String)
    case outputConflict(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message), .unsupportedMedia(let message),
             .unsupportedLocale(let message), .assetInstallation(let message),
             .transcription(let message), .outputConflict(let message):
            message
        }
    }

    var exitCode: ExitCode {
        switch self {
        case .invalidArguments: .invalidArguments
        case .unsupportedMedia: .unsupportedMedia
        case .unsupportedLocale: .unsupportedLocale
        case .assetInstallation: .assetInstallation
        case .transcription: .transcription
        case .outputConflict: .outputConflict
        }
    }
}

enum StandardError {
    static func write(_ message: String, terminator: String = "\n") {
        FileHandle.standardError.write(Data((message + terminator).utf8))
    }
}
