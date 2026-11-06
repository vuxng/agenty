import AppKit

@MainActor
enum Finder {
    static func show(_ url: URL) {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue {
                NSWorkspace.shared.open(parent)
            }
        }
    }
}
