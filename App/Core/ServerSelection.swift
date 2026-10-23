import Foundation

/// The server the Connect screen acts on, and the servers used most recently.
@MainActor
final class ServerSelection: ObservableObject {
    static let recentLimit = 5

    @Published private(set) var selectedID: String?
    /// Most recent first.
    @Published private(set) var recentIDs: [String]

    private let defaults: UserDefaults
    private enum Key {
        static let selected = "selectedServerID"
        static let recent = "recentServerIDs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedID = defaults.string(forKey: Key.selected)
        recentIDs = defaults.stringArray(forKey: Key.recent) ?? []
    }

    func select(_ id: String) {
        selectedID = id
        defaults.set(id, forKey: Key.selected)
    }

    /// Call after connecting to `id`: it becomes the selection and the most recent server.
    func recordConnection(to id: String) {
        select(id)
        recentIDs = Array(([id] + recentIDs.filter { $0 != id }).prefix(Self.recentLimit))
        defaults.set(recentIDs, forKey: Key.recent)
    }

    /// The server to show: the selected one if it still exists, else the most recent, else
    /// the first in the list.
    func resolvedServer(in servers: [Server]) -> Server? {
        let byID = Dictionary(servers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selectedID.flatMap { byID[$0] } ?? recentIDs.lazy.compactMap { byID[$0] }.first ?? servers.first
    }

    /// Recent servers that still exist, topped up from the list so the strip isn't empty.
    func recentServers(in servers: [Server]) -> [Server] {
        let byID = Dictionary(servers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentIDs.compactMap { byID[$0] }
        let others = servers.filter { server in !recent.contains { $0.id == server.id } }
        return Array((recent + others).prefix(Self.recentLimit))
    }
}
