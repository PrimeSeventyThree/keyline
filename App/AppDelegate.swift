import AppKit

/// Owns the menu bar item. SwiftUI's MenuBarExtra needs macOS 13, so on the macOS 12
/// baseline the status item is plain AppKit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "key", accessibilityDescription: "Keyline")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Open Keyline"), action: #selector(openMainWindow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Keyline"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // The menu bar item keeps the app running.
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
