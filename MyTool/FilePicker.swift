import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePicker {
    static func chooseMediaFile() -> URL? {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()

        let panel = NSOpenPanel()
        panel.title = "Choose Audio or Video"
        panel.message = "Select one media file to transcribe."
        panel.prompt = "Transcribe"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]

        let result = PickerResult()
        panel.begin { response in
            result.url = response == .OK ? panel.url : nil
            application.stop(nil)
            wakeEventLoop(application)
        }
        application.activate(ignoringOtherApps: true)
        application.run()
        return result.url
    }

    private static func wakeEventLoop(_ application: NSApplication) {
        guard let event = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) else { return }
        application.postEvent(event, atStart: false)
    }
}

@MainActor
private final class PickerResult {
    var url: URL?
}
