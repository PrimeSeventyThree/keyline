import Darwin
import Foundation
import NetworkExtension

/// Which traffic goes through the VPN. Chosen in the app, applied by the tunnel extension.
struct SplitTunnelSettings: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// Everything goes through the VPN.
        case off
        /// Everything except the listed destinations.
        case exclude
        /// Only the listed destinations.
        case include
        var id: String { rawValue }
    }

    var mode: Mode = .off
    /// Keep local networks (home router, printers) outside the VPN.
    var bypassLocalNetwork = true
    /// IPv4 addresses, IPv4 subnets in CIDR notation, and host names, as the user typed them.
    var entries: [String] = []

    var parsedEntries: [SplitTunnelEntry] { entries.compactMap(SplitTunnelEntry.init) }
    var subnets: [IPv4Subnet] { parsedEntries.compactMap { if case .subnet(let subnet) = $0 { return subnet } else { return nil } } }
    var domains: [String] { parsedEntries.compactMap { if case .domain(let name) = $0 { return name } else { return nil } } }

    /// JSON for `NETunnelProviderProtocol.providerConfiguration` and app messages.
    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decoded(from data: Data?) -> SplitTunnelSettings? {
        data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}

/// One line of the split tunneling list.
enum SplitTunnelEntry: Equatable {
    case subnet(IPv4Subnet)
    case domain(String)

    /// Parses "203.0.113.7", "10.0.0.0/8" or "example.com". Nil for anything else, including
    /// IPv6 (the tunnel carries IPv4 only).
    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let subnet = IPv4Subnet(cidr: text.contains("/") ? text : "\(text)/32") {
            self = .subnet(subnet)
        } else if Self.isHostName(text) {
            self = .domain(text.hasSuffix(".") ? String(text.dropLast()) : text)
        } else {
            return nil
        }
    }

    /// Letters, digits and hyphens in dot-separated labels, with at least one dot and a
    /// top-level label that isn't all digits.
    private static func isHostName(_ text: String) -> Bool {
        let name = text.hasSuffix(".") ? String(text.dropLast()) : text
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard name.count <= 253, labels.count >= 2, let top = labels.last, !top.allSatisfy(\.isNumber) else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

/// An IPv4 subnet in CIDR notation, such as "10.0.0.0/8".
struct IPv4Subnet: Equatable, Hashable {
    /// The network address (host bits cleared).
    let address: String
    let prefix: UInt8

    init?(cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = UInt8(parts[1]), prefix <= 32 else { return nil }
        var addr = in_addr()
        guard inet_pton(AF_INET, String(parts[0]), &addr) == 1 else { return nil }
        let bits = Self.maskBits(prefix)
        let network = UInt32(bigEndian: addr.s_addr) & bits
        self.address = Self.string(network)
        self.prefix = prefix
    }

    var mask: String { Self.string(Self.maskBits(prefix)) }

    var cidr: String { "\(address)/\(prefix)" }

    /// The route for this subnet; 0.0.0.0/0 is the system's default route.
    var route: NEIPv4Route {
        prefix == 0 ? NEIPv4Route.default() : NEIPv4Route(destinationAddress: address, subnetMask: mask)
    }

    private static func maskBits(_ prefix: UInt8) -> UInt32 {
        prefix == 0 ? 0 : 0xffff_ffff << (32 - UInt32(prefix))
    }

    private static func string(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> $0) & 0xff) }.joined(separator: ".")
    }
}

extension SplitTunnelSettings {
    /// The IPv4 addresses `domains` resolve to, through the system resolver. Blocks; call it
    /// off the main thread when you can. Names that don't resolve are skipped.
    static func resolveIPv4(_ domains: [String]) -> [String] {
        var addresses: [String] = []
        for domain in domains {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var results: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(domain, nil, &hints, &results) == 0 else { continue }
            var info = results
            while let current = info?.pointee {
                if let addr = current.ai_addr {
                    var inAddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &inAddr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                        let address = String(cString: buffer)
                        if !addresses.contains(address) { addresses.append(address) }
                    }
                }
                info = current.ai_next
            }
            freeaddrinfo(results)
        }
        return addresses
    }
}
