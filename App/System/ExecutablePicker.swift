import AppKit

@MainActor
enum ExecutablePicker {
    /// Shows a file-only open panel starting at ~/.local/bin. Returns the chosen path, or nil if cancelled.
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/bin", directoryHint: .isDirectory)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
