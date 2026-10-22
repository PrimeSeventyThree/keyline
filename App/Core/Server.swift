import Foundation

/// A server the user added. The access key itself lives in a `SecretStore`.
struct Server: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        /// An `ss://` key that holds the whole config.
        case `static`
        /// An `ssconf://` or `https://` key whose config is downloaded on every connect.
        case dynamic
    }

    let id: String
    var name: String
    let kind: Kind
    /// Where the traffic goes first, for display. Known up front for static keys, and
    /// updated on each connect for dynamic ones. Empty when unknown.
    var address: String
    /// Country of `address`, detected offline from the bundled DB-IP table.
    var detectedCountryCode: String?
    /// Country chosen by the user, which wins over the detected one.
    var countryOverride: String?

    init(id: String, name: String, kind: Kind, address: String,
         detectedCountryCode: String? = nil, countryOverride: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.address = address
        self.detectedCountryCode = detectedCountryCode
        self.countryOverride = countryOverride
    }

    /// The country to show: the user's choice, else the detected one.
    var country: Country? {
        (countryOverride ?? detectedCountryCode).flatMap(Country.init(code:))
    }
}

/// Saves the server list (without access keys).
protocol ServerListStorage {
    func load() throws -> [Server]
    func save(_ servers: [Server]) throws
}

/// Keeps the server list as JSON in Keyline's Application Support folder.
struct FileServerListStorage: ServerListStorage {
    let fileURL: URL

    /// `servers.json` in the app's Application Support folder.
    static func standard() throws -> FileServerListStorage {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(KeylineIdentifiers.app, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return FileServerListStorage(fileURL: folder.appendingPathComponent("servers.json"))
    }

    private struct File: Codable {
        var version = 1
        var servers: [Server]
    }

    func load() throws -> [Server] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: fileURL)).servers
    }

    func save(_ servers: [Server]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(File(servers: servers)).write(to: fileURL, options: .atomic)
    }
}

/// A `ServerListStorage` that lives in memory, for tests and previews.
final class InMemoryServerListStorage: ServerListStorage {
    var servers: [Server]
    init(_ servers: [Server] = []) { self.servers = servers }
    func load() throws -> [Server] { servers }
    func save(_ servers: [Server]) throws { self.servers = servers }
}
