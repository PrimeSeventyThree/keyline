import AppKit
import Combine
import NetworkExtension

/// The menu bar item: an icon that dims while disconnected, and a menu with the status,
/// Connect/Disconnect, the servers, and shortcuts into the main window.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let tunnel: TunnelController
    private let servers: ServerRepository
    private let connection: ConnectionModel
    private let selection: ServerSelection
    private let updater: Updater
    private var statusSubscription: AnyCancellable?

    init(tunnel: TunnelController, servers: ServerRepository, connection: ConnectionModel, selection: ServerSelection,
         updater: Updater) {
        self.tunnel = tunnel
        self.servers = servers
        self.connection = connection
        self.selection = selection
        self.updater = updater
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let mark = NSImage(named: "KeylineMark")
        mark?.size = NSSize(width: 18, height: 18)
        mark?.isTemplate = true
        mark?.accessibilityDescription = "Keyline"
        item.button?.image = mark

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        statusSubscription = tunnel.$status.sink { [weak self] status in
            self?.item.button?.appearsDisabled = status != .connected
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let active = connection.activeServerID.flatMap(servers.server(withID:))
        let target = active ?? selection.resolvedServer(in: servers.servers)

        let status = NSMenuItem(title: statusTitle(active: active), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if active != nil {
            menu.addItem(actionItem(String(localized: "menu-disconnect", defaultValue: "Disconnect"), #selector(disconnect)))
        } else if let target {
            menu.addItem(actionItem(String(localized: "menu-connect-to", defaultValue: "Connect to \(target.name)"),
                                    #selector(connectToTarget)))
        }

        if !servers.servers.isEmpty {
            let serversItem = NSMenuItem(title: String(localized: "section-servers", defaultValue: "Servers"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for server in servers.servers {
                let entry = actionItem(server.name, #selector(connectToServer(_:)))
                entry.representedObject = server.id
                entry.image = Self.flagImage(server.country)
                entry.state = server.id == active?.id ? .on : .off
                if let country = server.country { entry.toolTip = country.name() }
                submenu.addItem(entry)
            }
            serversItem.submenu = submenu
            menu.addItem(serversItem)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "menu-open", defaultValue: "Open Keyline"), #selector(openConnect)))
        menu.addItem(actionItem(String(localized: "menu-settings", defaultValue: "Settings…"), #selector(openSettings), key: ","))
        let updates = actionItem(String(localized: "menu-check-updates", defaultValue: "Check for Updates…"), #selector(checkForUpdates))
        updates.isEnabled = updater.canCheckForUpdates
        menu.addItem(updates)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "menu-quit", defaultValue: "Quit Keyline"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func statusTitle(active: Server?) -> String {
        switch tunnel.status {
        case .connected:
            let place = active?.country?.name()
            return place.map { String(localized: "menu-connected-to-place", defaultValue: "Connected to \(active?.name ?? "") (\($0))") }
                ?? String(localized: "menu-connected-to", defaultValue: "Connected to \(active?.name ?? "")")
        case .connecting: return String(localized: "status-connecting", defaultValue: "Connecting…")
        case .reasserting: return String(localized: "status-reconnecting", defaultValue: "Reconnecting…")
        case .disconnecting: return String(localized: "status-disconnecting", defaultValue: "Disconnecting…")
        default: return String(localized: "menu-not-connected", defaultValue: "Not connected")
        }
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// A 16 pt round flag, or a globe for an unknown country.
    private static func flagImage(_ country: Country?) -> NSImage? {
        let source = country.flatMap { Bundle.main.image(forResource: $0.flagAssetName) }
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        guard let source else { return nil }
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            source.draw(in: rect)
            return true
        }
        image.isTemplate = country == nil
        return image
    }

    // MARK: - Actions

    @objc private func disconnect() {
        guard let id = connection.activeServerID else { return }
        Task { await connection.disconnect(serverID: id) }
    }

    @objc private func connectToTarget() {
        guard let target = selection.resolvedServer(in: servers.servers) else { return }
        connect(target.id)
    }

    @objc private func connectToServer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != connection.activeServerID else { return }
        connect(id)
    }

    private func connect(_ id: String) {
        selection.select(id)
        Task {
            do {
                try await connection.connect(serverID: id)
            } catch {
                let shown = UserFacingError(error)
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = shown.message
                alert.informativeText = shown.details ?? ""
                alert.runModal()
            }
        }
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
    }

    @objc private func openConnect() { Self.show(.connect) }
    @objc private func openSettings() { Self.show(.settings) }

    /// Brings the main window forward at `section`, opening a new one if it was closed. A
    /// keyline:// link does both: the window group handles external events, and AppKit's
    /// newWindowForTab: doesn't reach it (#19).
    static func show(_ section: MainSection) {
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.open(section.showURL)
    }
}
