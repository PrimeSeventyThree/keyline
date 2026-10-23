// Ported from Outline's OutlineVpn.swift
// (client/src/cordova/apple/OutlineAppleLib/Sources/OutlineTunnel/OutlineVpn.swift),
// Copyright 2018 The Outline Authors, Apache License 2.0. Changed by Pulsbeat Media Inc.:
// observable state for SwiftUI, system extension bundle ID, logging moved to os.Logger.

import Foundation
@preconcurrency import NetworkExtension
import os

/// Starts and stops the system VPN through the tunnel extension, and publishes its status.
@MainActor
final class TunnelController: ObservableObject, TunnelControlling {
    @Published private(set) var status: NEVPNStatus = .invalid
    /// ID of the tunnel the system VPN configuration belongs to.
    @Published private(set) var tunnelID: String?
    /// When the current connection came up, for the connection timer.
    @Published private(set) var connectedDate: Date?

    private let log = Logger.keyline("vpn")
    private var statusObserver: NSObjectProtocol?
    private var session: NETunnelProviderSession?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let session = notification.object as? NETunnelProviderSession else { return }
            MainActor.assumeIsolated { self?.statusChanged(session) }
        }
        Task { await refresh() }
    }

    /// Loads the current status, for example at launch while the VPN is already on.
    func refresh() async {
        let manager = await Self.loadManager()
        session = manager?.connection as? NETunnelProviderSession
        status = session?.status ?? .invalid
        connectedDate = session?.connectedDate
        tunnelID = Self.tunnelID(of: manager)
    }

    /// Connects tunnel `id` using `transport` (the `client` field of a parsed tunnel config).
    /// Stops any other active tunnel first. Throws a `KeylineError` on failure.
    func start(id: String, name: String, transport: String) async throws {
        if let manager = await Self.loadManager(), Self.isActive(manager.connection.status) {
            log.debug("Stopping the active session before starting a new one")
            await stopSession(manager)
        }

        let manager: NETunnelProviderManager
        do {
            manager = try await setUpVPN(id: id, name: name, transport: transport)
        } catch {
            log.error("Failed to set up VPN: \(error.localizedDescription)")
            throw KeylineError.vpnPermissionNotGranted(cause: error)
        }
        let session = manager.connection as! NETunnelProviderSession

        do {
            try await waitForStatus(of: session, in: [.connected, .disconnected, .invalid]) {
                try session.startTunnel(options: [:])
            }
        } catch {
            log.error("Failed to start VPN: \(error.localizedDescription)")
            throw KeylineError.setupSystemVPNFailed(cause: error)
        }

        guard session.status == .connected else {
            throw await Self.lastDisconnectError(of: session)
                ?? KeylineError.internalError(message: "the tunnel stopped without an error")
        }

        // Connect on any network from now on, which also reconnects after a reboot. A
        // user-initiated stop turns this off again.
        await setOnDemand(manager, enabled: true)
    }

    /// Stops the VPN if tunnel `id` is the active one.
    func stop(id: String) async {
        guard let manager = await Self.loadManager(), Self.tunnelID(of: manager) == id,
              Self.isActive(manager.connection.status)
        else {
            log.warning("Asked to stop a tunnel that is not running")
            return
        }
        await stopSession(manager)
    }

    /// Stops whichever tunnel is active, for example when quitting.
    func stopActive() async {
        guard let manager = await Self.loadManager(), Self.isActive(manager.connection.status) else { return }
        await stopSession(manager)
    }

    /// Whether a tunnel is connected or on its way, as far as the last status update knows.
    var isActive: Bool { Self.isActive(status) }

    /// Bytes through the running tunnel, or nil when it is not connected.
    func trafficStats() async -> TrafficStats? {
        await ask(TunnelAppMessage.trafficStats, as: TrafficStats.self)
    }

    /// One round trip through the proxy, or nil when not connected or the check fails.
    func latency() async -> LatencySample? {
        await ask(TunnelAppMessage.measureLatency, as: LatencySample.self)
    }

    /// Sends `message` to the running extension and decodes its JSON reply.
    private func ask<Reply: Decodable>(_ message: String, as: Reply.Type) async -> Reply? {
        guard let session, session.status == .connected else { return nil }
        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(Data(message.utf8)) { data in
                    continuation.resume(returning: data.flatMap { try? JSONDecoder().decode(Reply.self, from: $0) })
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Helpers

    private func setUpVPN(id: String, name: String, transport: String) async throws -> NETunnelProviderManager {
        let manager = try await NETunnelProviderManager.loadAllFromPreferences().first ?? NETunnelProviderManager()
        manager.localizedDescription = name
        // No on-demand until the first successful start, so a failing start isn't retried.
        manager.onDemandRules = nil
        manager.isOnDemandEnabled = false

        let config = NETunnelProviderProtocol()
        config.serverAddress = name
        config.providerBundleIdentifier = KeylineIdentifiers.tunnelExtension
        config.providerConfiguration = [
            TunnelConfigKey.tunnelID: id,
            TunnelConfigKey.transport: transport,
        ]
        manager.protocolConfiguration = config
        manager.isEnabled = true

        try await manager.saveToPreferences()
        // Saving invalidates the manager's connection until it is loaded again
        // (https://forums.developer.apple.com/thread/25928).
        try await manager.loadFromPreferences()
        return manager
    }

    private func stopSession(_ manager: NETunnelProviderManager) async {
        // Turn on-demand off first, or the system starts the tunnel again right away.
        await setOnDemand(manager, enabled: false)
        try? await waitForStatus(of: manager.connection, in: [.disconnected]) {
            manager.connection.stopVPNTunnel()
        }
    }

    private func setOnDemand(_ manager: NETunnelProviderManager, enabled: Bool) async {
        do {
            try await manager.loadFromPreferences()
            if enabled {
                let connectOnAnyNetwork = NEOnDemandRuleConnect()
                connectOnAnyNetwork.interfaceTypeMatch = .any
                manager.onDemandRules = [connectOnAnyNetwork]
            }
            manager.isOnDemandEnabled = enabled
            try await manager.saveToPreferences()
        } catch {
            log.error("Failed to set on-demand to \(enabled): \(error.localizedDescription)")
        }
    }

    /// Runs `action`, then waits until `connection` reaches one of `statuses`.
    private func waitForStatus(
        of connection: NEVPNConnection, in statuses: Set<NEVPNStatus>, after action: () throws -> Void
    ) async throws {
        var observer: NSObjectProtocol?
        defer { observer.map(NotificationCenter.default.removeObserver) }
        let reached = AsyncStream<Void> { continuation in
            observer = NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange, object: connection, queue: .main
            ) { _ in
                if statuses.contains(connection.status) { continuation.finish() }
            }
        }
        try action()
        for await _ in reached {}
    }

    private func statusChanged(_ session: NETunnelProviderSession) {
        guard let manager = session.manager as? NETunnelProviderManager,
              let id = Self.tunnelID(of: manager)
        else { return } // The system also sends spurious notifications without a manager.
        self.session = session
        status = session.status
        connectedDate = session.connectedDate
        tunnelID = id
    }

    private static func loadManager() async -> NETunnelProviderManager? {
        do {
            return try await NETunnelProviderManager.loadAllFromPreferences().first
        } catch {
            Logger.keyline("vpn").error("Failed to load VPN preferences: \(error.localizedDescription)")
            return nil
        }
    }

    private static func tunnelID(of manager: NETunnelProviderManager?) -> String? {
        (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?[TunnelConfigKey.tunnelID] as? String
    }

    private static func isActive(_ status: NEVPNStatus) -> Bool {
        [.connected, .connecting, .reasserting].contains(status)
    }

    /// Errors from the extension come back as `KeylineError`s. Anything else comes from
    /// macOS itself, for example when the extension is not approved yet, so it is a system
    /// VPN setup failure rather than an internal error.
    private nonisolated static func keylineError(fromDisconnectError error: Error) -> KeylineError {
        guard (error as NSError).domain == KeylineError.errorDomain else {
            return .setupSystemVPNFailed(cause: error)
        }
        return KeylineError(error)
    }

    /// The error that made the extension stop. Uses `fetchLastDisconnectError` on macOS 13+
    /// and asks the extension on macOS 12, which is best-effort: once the extension is
    /// unloaded, the message may go unanswered.
    private static func lastDisconnectError(of session: NETunnelProviderSession) async -> KeylineError? {
        if #available(macOS 13, *) {
            return await withCheckedContinuation { continuation in
                session.fetchLastDisconnectError { error in continuation.resume(returning: error.map(keylineError(fromDisconnectError:))) }
            }
        }
        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(Data(TunnelAppMessage.fetchLastError.utf8)) { data in
                    let record = data.flatMap { try? PropertyListDecoder().decode(LastTunnelError.self, from: $0) }
                    continuation.resume(returning: record.map { .detailedJsonError(code: $0.errorCode, json: $0.errorJson) })
                }
            } catch {
                continuation.resume(returning: .internalError(message: "fetching the last error failed: \(error.localizedDescription)"))
            }
        }
    }
}
