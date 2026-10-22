// Ported from Outline's config.ts and server.ts
// (client/web/app/outline_server_repository/), Copyright 2024 The Outline Authors,
// Apache License 2.0. Changed by Pulsbeat Media Inc.: rewritten in Swift.

import Foundation

/// An access key as the user pastes it: a static `ss://` key that holds the whole
/// config, or a dynamic `ssconf://`/`https://` key that points to a config to download
/// on every connect.
enum AccessKey: Equatable {
    case `static`(name: String?, config: TunnelConfig)
    case dynamic(name: String?, configURL: URL)

    /// Parses `text`. Static keys are checked with the Go core now; dynamic keys are only
    /// checked for a valid URL, since their config is fetched when connecting.
    init(_ text: String, using service: TunnelConfigService) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let (keyWithoutFragment, fragment) = Self.splitFragment(trimmed)
        let name = fragment.flatMap(Self.name(fromFragment:))

        switch Self.scheme(of: keyWithoutFragment) {
        case "ss":
            do {
                self = .static(name: name, config: try service.parseTunnelConfig(keyWithoutFragment))
            } catch {
                throw ServerError.invalidAccessKey(cause: error)
            }
        case "ssconf", "https":
            // ssconf:// is https:// under another name.
            let httpsKey = "https" + keyWithoutFragment.drop { $0 != ":" }
            guard let url = URL(string: httpsKey), url.host?.isEmpty == false else {
                throw ServerError.invalidAccessKey(cause: nil)
            }
            self = .dynamic(name: name, configURL: url)
        default:
            throw ServerError.invalidAccessKey(cause: nil)
        }
    }

    /// The name stored in the key, if any.
    var name: String? {
        switch self {
        case .static(let name, _), .dynamic(let name, _): return name
        }
    }

    /// The name to show for a server added from `text` without a name of its own:
    /// the config host for dynamic keys, a generic name for static ones.
    func defaultName(accessKeyText text: String) -> String {
        switch self {
        case .dynamic(_, let url):
            let host = url.host ?? ""
            guard let port = url.port, port != 443 else { return host }
            return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        case .static:
            return text.contains("outline=1")
                ? String(localized: "server-default-name-outline", defaultValue: "Outline Server")
                : String(localized: "server-default-name", defaultValue: "Proxy Server")
        }
    }

    // MARK: - Parsing helpers

    private static func splitFragment(_ text: String) -> (String, String?) {
        guard let hash = text.firstIndex(of: "#") else { return (text, nil) }
        return (String(text[..<hash]), String(text[text.index(after: hash)...]))
    }

    private static func scheme(of text: String) -> String? {
        guard let colon = text.range(of: "://") else { return nil }
        return text[..<colon.lowerBound].lowercased()
    }

    /// The fragment holds `&`-separated entries. The name is the first entry that is not a
    /// `key=value` parameter, percent-decoded.
    static func name(fromFragment fragment: String) -> String? {
        guard let entry = fragment.split(separator: "&", omittingEmptySubsequences: false)
            .first(where: { !$0.contains("=") })
        else { return nil }
        let name = String(entry).removingPercentEncoding ?? String(entry)
        return name.isEmpty ? nil : name
    }
}
