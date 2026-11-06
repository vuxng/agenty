import AppKit

enum DockPolicy {
    @MainActor static func windowDidAppear() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    @MainActor static func windowDidDisappear() {
        NSApp.setActivationPolicy(.accessory)
    }
}
