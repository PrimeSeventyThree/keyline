import AppKit

/// Sets up the menu bar item and decides what quitting does to the VPN. SwiftUI's
/// MenuBarExtra needs macOS 13, so on the macOS 12 baseline the menu bar item is AppKit
/// (StatusMenuController).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenuController?
    private var tunnel: TunnelController?
    private var settings: AppSettings?
    /// Set when quitting to restart: skip the VPN question, the VPN stays as it is.
    @MainActor static var isRelaunching = false

    /// Called once the app's models exist.
    @MainActor
    func configure(tunnel: TunnelController, settings: AppSettings, servers: ServerRepository,
                   connection: ConnectionModel, selection: ServerSelection, updater: Updater) {
        guard statusMenu == nil else { return } // Once, even if a second window opens.
        self.tunnel = tunnel
        self.settings = settings
        statusMenu = StatusMenuController(tunnel: tunnel, servers: servers, connection: connection, selection: selection,
                                          updater: updater)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // The menu bar item keeps the app running.
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let tunnel, let settings else { return .terminateNow }
        if Self.isRelaunching { return .terminateNow }
        switch QuitDecision.decide(isVPNActive: tunnel.isActive, stopVPNOnQuit: settings.stopVPNOnQuit,
                                   warnOnQuit: settings.warnOnQuitWhileConnected) {
        case .quit:
            return .terminateNow
        case .disconnectThenQuit:
            return disconnectThenQuit(sender, tunnel: tunnel)
        case .ask:
            let alert = NSAlert()
            alert.messageText = String(localized: "quit-vpn-stays-on-title", defaultValue: "The VPN stays on after Keyline quits")
            alert.informativeText = String(localized: "quit-vpn-stays-on-body",
                                           defaultValue: "Your traffic keeps going through your server, and the VPN reconnects after a restart. To turn it off, disconnect first or open Keyline again later.")
            alert.addButton(withTitle: String(localized: "quit-leave-on", defaultValue: "Quit"))
            alert.addButton(withTitle: String(localized: "quit-disconnect", defaultValue: "Disconnect and Quit"))
            alert.addButton(withTitle: String(localized: "cancel", defaultValue: "Cancel"))
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = String(localized: "quit-dont-ask", defaultValue: "Don’t ask again")
            let response = alert.runModal()
            if alert.suppressionButton?.state == .on, response != .alertThirdButtonReturn {
                settings.warnOnQuitWhileConnected = false
            }
            switch response {
            case .alertFirstButtonReturn: return .terminateNow
            case .alertSecondButtonReturn: return disconnectThenQuit(sender, tunnel: tunnel)
            default: return .terminateCancel
            }
        }
    }

    @MainActor
    private func disconnectThenQuit(_ app: NSApplication, tunnel: TunnelController) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await tunnel.stopActive()
            app.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
