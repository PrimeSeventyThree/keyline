import SwiftUI

/// The main menu, trimmed to what Keyline uses: About, Settings and updates in the app menu,
/// Close, the pasteboard commands for the access key field, full screen and the Window menu.
/// SwiftUI's New Window and Close All (Keyline has one main window), the Help book it doesn't
/// have, and the text-editing extras are gone. SwiftUI leaves the removed groups' separators
/// behind; `NSMenu.removeRedundantSeparators()` tidies them when the menu bar opens.
struct KeylineCommands: Commands {
    @ObservedObject var updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(String(localized: "menu-check-updates", defaultValue: "Check for Updates…")) { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "menu-settings", defaultValue: "Settings…")) { StatusMenuController.show(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        Group {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu-close", defaultValue: "Close")) { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
        }
        Group {
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .help) {}
        }
    }
}
