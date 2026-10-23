// Ported from Outline's outline_server_repository (index.ts, server.ts)
// (client/web/app/outline_server_repository/), Copyright 2024 The Outline Authors,
// Apache License 2.0. Changed by Pulsbeat Media Inc.: rewritten in Swift, access keys
// moved to the Keychain, server list stored as JSON.

import Foundation
import os

/// The user's servers: adding from an access key, renaming, forgetting with undo, and
/// turning a server into a tunnel config when connecting.
@MainActor
final class ServerRepository: ObservableObject {
    @Published private(set) var servers: [Server] = []

    private let storage: ServerListStorage
    private let secrets: SecretStore
    private let configService: TunnelConfigService
    private let countryResolver: CountryResolving?
    private let log = Logger.keyline("servers")
    /// The last forgotten server, its position and access key, kept for undo.
    private var lastForgotten: (server: Server, index: Int, accessKey: String)?

    init(storage: ServerListStorage, secrets: SecretStore, configService: TunnelConfigService,
         countryResolver: CountryResolving? = nil) {
        self.storage = storage
        self.secrets = secrets
        self.configService = configService
        self.countryResolver = countryResolver
        do {
            // A server without its key in the Keychain can't connect; drop it.
            servers = try storage.load().filter { server in
                let hasKey = (try? secrets.secret(for: server.id)) != nil
                if !hasKey { log.error("Dropping server \(server.id, privacy: .public): access key missing") }
                return hasKey
            }
        } catch {
            log.error("Failed to load servers: \(error.localizedDescription, privacy: .public)")
        }
    }

    func server(withID id: String) -> Server? {
        servers.first { $0.id == id }
    }

    /// The server added from `accessKey`, if any (surrounding whitespace ignored).
    func server(withAccessKey accessKey: String) -> Server? {
        let accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return servers.first { (try? secrets.secret(for: $0.id)) == accessKey }
    }

    /// Adds a server from an access key, named after the key or a default name.
    /// Throws `ServerError.alreadyAdded` if a server with the same key exists.
    @discardableResult
    func add(accessKey text: String) async throws -> Server {
        let accessKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = server(withAccessKey: accessKey) {
            throw ServerError.alreadyAdded(serverName: existing.name)
        }

        let service = configService
        let key = try await Task.detached { try AccessKey(accessKey, using: service) }.value
        let address: String
        switch key {
        case .static(_, let config): address = config.firstHop
        case .dynamic: address = ""
        }
        let server = Server(
            id: UUID().uuidString,
            name: key.name ?? key.defaultName(accessKeyText: accessKey),
            kind: key.isDynamic ? .dynamic : .static,
            address: address)

        try secrets.setSecret(accessKey, for: server.id)
        servers.append(server)
        do {
            try storage.save(servers)
        } catch {
            servers.removeLast()
            try? secrets.deleteSecret(for: server.id)
            throw error
        }
        Task { await refreshCountry(forServer: server.id) }
        return server
    }

    func rename(id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].name = name
        persist()
    }

    /// Removes a server. `undoForget` brings back the most recently forgotten one.
    func forget(id: String) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        let accessKey = (try? secrets.secret(for: id)) ?? ""
        lastForgotten = (servers.remove(at: index), index, accessKey)
        do {
            try secrets.deleteSecret(for: id)
        } catch {
            log.error("Failed to delete access key: \(error.localizedDescription, privacy: .public)")
        }
        persist()
        let service = configService
        Task.detached { try? service.eraseServiceStorage(serverID: id) }
    }

    func undoForget(id: String) {
        guard let forgotten = lastForgotten, forgotten.server.id == id else { return }
        do {
            try secrets.setSecret(forgotten.accessKey, for: id)
        } catch {
            log.error("Failed to restore access key: \(error.localizedDescription, privacy: .public)")
            return
        }
        servers.insert(forgotten.server, at: min(forgotten.index, servers.count))
        lastForgotten = nil
        persist()
    }

    /// The tunnel config to connect server `id` with. Dynamic keys download their config
    /// first, which can fail with the provider's own error message.
    func tunnelConfig(forServer id: String) async throws -> TunnelConfig {
        guard let accessKey = try secrets.secret(for: id) else { throw ServerError.missingAccessKey }
        let service = configService
        let config = try await Task.detached { () throws -> TunnelConfig in
            switch try AccessKey(accessKey, using: service) {
            case .static(_, let config):
                return config
            case .dynamic(_, let url):
                let text = try service.fetchResource(url).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw ServerError.emptyDynamicConfig }
                return try service.parseTunnelConfig(text)
            }
        }.value

        guard config.connectionType != .direct else { throw ServerError.proxylessNotSupported }
        if let index = servers.firstIndex(where: { $0.id == id }), servers[index].address != config.firstHop {
            servers[index].address = config.firstHop
            persist()
            Task { await refreshCountry(forServer: id) }
        }
        return config
    }

    /// Sets the country to show for server `id`, or nil to go back to the detected one.
    func setCountryOverride(id: String, countryCode: String?) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].countryOverride = countryCode.flatMap(Country.init(code:))?.code
        persist()
    }

    /// Detects the country of server `id` from its address, offline.
    func refreshCountry(forServer id: String) async {
        guard let resolver = countryResolver,
              let address = server(withID: id)?.address,
              let host = CountryLookup.host(ofFirstHop: address)
        else { return }
        let code = await Task.detached { resolver.countryCode(forHost: host) }.value
        guard let index = servers.firstIndex(where: { $0.id == id }),
              servers[index].address == address, servers[index].detectedCountryCode != code
        else { return }
        servers[index].detectedCountryCode = code
        persist()
    }

    private func persist() {
        do {
            try storage.save(servers)
        } catch {
            log.error("Failed to save servers: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension AccessKey {
    var isDynamic: Bool {
        if case .dynamic = self { return true }
        return false
    }
}
