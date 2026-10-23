// Ported from Outline's PacketTunnelProvider.m and PacketTunnelProvider.swift
// (client/src/cordova/apple/OutlineLib/VpnExtension/Sources/),
// Copyright 2018 and 2024 The Outline Authors, Apache License 2.0. Changed by Pulsbeat
// Media Inc.: rewritten in Swift for a system extension, logging moved to os.Logger.

import Foundation
import NetworkExtension
import os
import Tun2socks

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger.keyline("tunnel")
    private let packetQueue = DispatchQueue(label: "\(KeylineIdentifiers.tunnelExtension).packets")
    private var remoteDevice: Tun2socksRemoteDevice?
    private let traffic = TrafficCounter()
    private var defaultPathObservation: NSKeyValueObservation?

    /// Split tunneling, from the VPN configuration or the app; the listed domains' current
    /// addresses; and the timer that looks them up again.
    private var splitTunnel = SplitTunnelSettings()
    private var resolvedAddresses: [String] = []
    private var resolveTimer: DispatchSourceTimer?
    private static let resolveInterval: DispatchTimeInterval = .seconds(10 * 60)

    // MARK: - Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("Starting tunnel")
        let finish: (Error?) -> Void = { [weak self] error in
            self?.saveLastError(error)
            completionHandler(error)
        }

        guard let configuration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration else {
            return finish(KeylineError.invalidConfig(message: "no config specified"))
        }
        guard let tunnelID = configuration[TunnelConfigKey.tunnelID] as? String else {
            return finish(KeylineError.internalError(message: "no tunnel ID specified"))
        }
        guard let transport = configuration[TunnelConfigKey.transport] as? String else {
            return finish(KeylineError.invalidConfig(message: "config is not a String"))
        }

        // Started from the app: options without "is-on-demand". Started on demand:
        // "is-on-demand" = 1. Started from the system VPN settings: options == nil.
        let isOnDemand = (options?["is-on-demand"] as? NSNumber)?.intValue == 1
        let isRestart = remoteDevice != nil
        if let remoteDevice {
            _ = remoteDevice.close()
        }
        log.debug("isOnDemand: \(isOnDemand), isRestart: \(isRestart)")

        if let error = connectRemoteDevice(tunnelID: tunnelID, transport: transport, isOnDemand: isOnDemand) {
            return finish(KeylineError.platformError(error))
        }

        // Look the domains up before the tunnel's own DNS takes over.
        splitTunnel = SplitTunnelSettings.decoded(from: configuration[TunnelConfigKey.splitTunnel] as? Data) ?? SplitTunnelSettings()
        resolvedAddresses = SplitTunnelSettings.resolveIPv4(splitTunnel.domains)
        log.info("Split tunneling: \(self.splitTunnel.mode.rawValue), \(self.splitTunnel.entries.count) entries")

        applyNetworkSettings(currentNetworkSettings()) { [weak self] error in
            guard let self else { return }
            if let error {
                return finish(KeylineError(error))
            }
            if let relayError = self.relayTraffic(isRestart: isRestart) {
                return finish(KeylineError.platformError(relayError))
            }
            self.listenForNetworkChanges()
            self.startResolvingDomains()
            finish(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("Stopping tunnel, reason: \(reason.rawValue)")
        defaultPathObservation = nil
        resolveTimer?.cancel()
        resolveTimer = nil
        if let error = remoteDevice?.close() {
            log.warning("Failed to close remote device: \(error.error())")
        }
        remoteDevice = nil
        completionHandler()
    }

    override func cancelTunnelWithError(_ error: Error?) {
        saveLastError(error)
        super.cancelTunnelWithError(error)
    }

    // MARK: - App messages

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // "updateSplitTunnel\n<settings JSON>": apply new split tunneling while connected.
        if let text = String(data: messageData, encoding: .utf8),
           text.hasPrefix(TunnelAppMessage.updateSplitTunnel + "\n") {
            let json = Data(text.dropFirst(TunnelAppMessage.updateSplitTunnel.count + 1).utf8)
            guard let settings = SplitTunnelSettings.decoded(from: json) else { completionHandler?(nil); return }
            updateSplitTunnel(settings) { error in completionHandler?(error == nil ? Data("ok".utf8) : nil) }
            return
        }
        switch String(data: messageData, encoding: .utf8) {
        case TunnelAppMessage.fetchLastError:
            completionHandler?(UserDefaults.standard.data(forKey: Self.lastErrorKey))
        case TunnelAppMessage.trafficStats:
            completionHandler?(try? JSONEncoder().encode(traffic.stats))
        case TunnelAppMessage.measureLatency:
            // The health check makes a round trip through the proxy, so time it. It blocks,
            // so run it off the provider's queue.
            guard let device = remoteDevice else { completionHandler?(nil); return }
            DispatchQueue.global(qos: .utility).async {
                let start = DispatchTime.now()
                let failed = device.getHealthStatus() != nil
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                completionHandler?(failed ? nil : try? JSONEncoder().encode(LatencySample(milliseconds: elapsed)))
            }
        default:
            log.warning("Unknown app message")
            completionHandler?(nil)
        }
    }

    // MARK: - Network settings

    private func applyNetworkSettings(_ settings: NEPacketTunnelNetworkSettings?, completion: @escaping (Error?) -> Void) {
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.log.error("Failed to set tunnel network settings: \(error.localizedDescription)")
            } else {
                // Nil settings clear the tunnel configuration; tell the system the tunnel is
                // being re-established.
                self?.reasserting = settings == nil
            }
            completion(error)
        }
    }

    private func listenForNetworkChanges() {
        defaultPathObservation = observe(\.defaultPath, options: [.old]) { [weak self] provider, change in
            // This fires repeatedly on Wi-Fi even when nothing changed. Compare descriptions,
            // which include properties the class doesn't expose, to skip false positives.
            guard let oldPath = change.oldValue ?? nil, let newPath = provider.defaultPath,
                  !oldPath.isEqual(to: newPath), oldPath.description != newPath.description
            else { return }
            DispatchQueue.main.async { self?.handleNetworkChange(newPath) }
        }
    }

    private func handleNetworkChange(_ path: NWPath) {
        guard path.status == .satisfied else {
            log.info("Network unavailable, clearing tunnel settings")
            applyNetworkSettings(nil) { _ in }
            return
        }
        guard let remoteDevice else {
            log.error("Network changed, but there is no remote device to reconnect")
            return
        }
        log.info("Network changed, reconnecting")
        remoteDevice.notifyNetworkChanged()
        applyNetworkSettings(currentNetworkSettings()) { [weak self] error in
            if let error {
                self?.cancelTunnelWithError(KeylineError(error))
            }
        }
        refreshResolvedDomains()
    }

    // MARK: - Split tunneling

    private func currentNetworkSettings() -> NEPacketTunnelNetworkSettings {
        TunnelNetworkSettings.make(splitTunnel: splitTunnel, resolvedAddresses: resolvedAddresses)
    }

    private func updateSplitTunnel(_ settings: SplitTunnelSettings, completion: @escaping (Error?) -> Void) {
        log.info("Updating split tunneling: \(settings.mode.rawValue), \(settings.entries.count) entries")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let addresses = SplitTunnelSettings.resolveIPv4(settings.domains)
            DispatchQueue.main.async {
                guard let self else { return }
                self.splitTunnel = settings
                self.resolvedAddresses = addresses
                self.applyNetworkSettings(self.currentNetworkSettings(), completion: completion)
            }
        }
    }

    /// Looks the listed domains up every 10 minutes, since their addresses can change.
    private func startResolvingDomains() {
        resolveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.resolveInterval, repeating: Self.resolveInterval)
        timer.setEventHandler { [weak self] in self?.refreshResolvedDomains() }
        timer.resume()
        resolveTimer = timer
    }

    /// Looks the domains up again and reapplies the routes if any address changed.
    private func refreshResolvedDomains() {
        let domains = splitTunnel.domains
        guard splitTunnel.mode != .off, !domains.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let addresses = SplitTunnelSettings.resolveIPv4(domains)
            DispatchQueue.main.async {
                guard let self, Set(addresses) != Set(self.resolvedAddresses), !addresses.isEmpty else { return }
                self.log.info("Split tunneling: domain addresses changed, updating routes")
                self.resolvedAddresses = addresses
                self.applyNetworkSettings(self.currentNetworkSettings()) { _ in }
            }
        }
    }

    // MARK: - Go core

    private func connectRemoteDevice(tunnelID: String, transport: String, isOnDemand: Bool) -> PlaterrorsPlatformError? {
        let clientConfig = OutlineClientConfig()
        do {
            clientConfig.dataDir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).path
        } catch {
            log.warning("No Application Support directory: \(error.localizedDescription)")
        }

        guard let clientResult = clientConfig.new(tunnelID, providerClientConfigText: transport) else {
            return PlaterrorsPlatformError(PlaterrorsInternalError, message: "failed to create client")
        }
        if let error = clientResult.error {
            return error
        }
        guard let deviceResult = Tun2socksConnectRemoteDevice(clientResult.client) else {
            return PlaterrorsPlatformError(PlaterrorsInternalError, message: "failed to connect remote device")
        }
        if let error = deviceResult.error {
            log.error("Failed to connect remote device: \(error.error())")
            return error
        }
        remoteDevice = deviceResult.device

        // On-demand starts skip the health check. The extension can't turn on-demand off, so
        // with a failing check the system would retry forever and the network would look
        // broken with no hint why. Connecting anyway at least shows Keyline as the cause.
        guard !isOnDemand else {
            log.info("On-demand start, skipping health check")
            return nil
        }
        if let error = remoteDevice?.getHealthStatus() {
            log.error("Remote device is not healthy: \(error.error())")
            _ = remoteDevice?.close()
            remoteDevice = nil
            return error
        }
        return nil
    }

    private func relayTraffic(isRestart: Bool) -> PlaterrorsPlatformError? {
        if let error = Tun2socksGoRelayTrafficOneWay(PacketFlowWriter(packetFlow: packetFlow, traffic: traffic), remoteDevice) {
            log.error("Failed to relay traffic to the TUN device: \(error.error())")
            return error
        }
        // A restart reuses the read loop that is already running.
        if !isRestart {
            packetQueue.async { [weak self] in self?.readPackets() }
        }
        return nil
    }

    /// Forwards packets from the system to the Go core, forever.
    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            let packets = TunnelNetworkSettings.ipv4Packets(packets, protocols: protocols)
            var written = 0
            for packet in packets {
                try? self.remoteDevice?.write(packet, ret0_: &written)
            }
            self.traffic.addSent(packets.reduce(0) { $0 + $1.count })
            self.packetQueue.async { self.readPackets() }
        }
    }

    // MARK: - Last error (macOS 12 fallback for fetchLastDisconnectError)

    private static let lastErrorKey = "lastDisconnectError"

    private func saveLastError(_ error: Error?) {
        guard let error else {
            UserDefaults.standard.removeObject(forKey: Self.lastErrorKey)
            return
        }
        let keylineError = KeylineError(error)
        let record = LastTunnelError(errorCode: keylineError.code, errorJson: keylineError.json)
        do {
            UserDefaults.standard.set(try PropertyListEncoder().encode(record), forKey: Self.lastErrorKey)
        } catch {
            log.error("Failed to save last error: \(error.localizedDescription)")
        }
    }
}

/// Writes packets from the Go core back to the system.
private final class PacketFlowWriter: NSObject, Tun2socksTunWriterProtocol {
    private let packetFlow: NEPacketTunnelFlow
    private let traffic: TrafficCounter

    init(packetFlow: NEPacketTunnelFlow, traffic: TrafficCounter) {
        self.packetFlow = packetFlow
        self.traffic = traffic
    }

    func close() throws {}

    func write(_ packet: Data?, n: UnsafeMutablePointer<Int>?) throws {
        guard let packet else { return }
        packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
        traffic.addReceived(packet.count)
        n?.pointee = packet.count
    }
}

/// Counts tunnel bytes. Go calls `addReceived` from its own threads, so access is locked.
final class TrafficCounter {
    private let lock = NSLock()
    private var current = TrafficStats()

    var stats: TrafficStats {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func addSent(_ bytes: Int) {
        lock.lock(); defer { lock.unlock() }
        current.bytesSent &+= UInt64(bytes)
    }

    func addReceived(_ bytes: Int) {
        lock.lock(); defer { lock.unlock() }
        current.bytesReceived &+= UInt64(bytes)
    }
}
