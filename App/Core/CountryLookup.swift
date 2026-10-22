import Darwin
import Foundation

/// Finds the country of an IPv4 address in the bundled DB-IP table, entirely offline.
/// See scripts/update-geoip.sh for the file format.
struct CountryLookup {
    private static let recordSize = 6
    private let table: Data

    init(table: Data) {
        self.table = table
    }

    /// Loads `GeoIP/ipv4-country.bin` from `bundle`.
    init?(bundle: Bundle = .keylineResources) {
        guard let url = bundle.url(forResource: "ipv4-country", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .alwaysMapped)
        else { return nil }
        self.init(table: data)
    }

    /// The ISO 3166-1 alpha-2 code (uppercase) for `address`, or nil when the address is
    /// not IPv4 or its range has no country.
    func countryCode(forIPv4 address: String) -> String? {
        var addr = in_addr()
        guard inet_pton(AF_INET, address, &addr) == 1 else { return nil }
        return countryCode(forIPv4: UInt32(bigEndian: addr.s_addr))
    }

    func countryCode(forIPv4 address: UInt32) -> String? {
        let count = table.count / Self.recordSize
        guard count > 0 else { return nil }
        return table.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> String? in
            func start(_ index: Int) -> UInt32 {
                let offset = index * Self.recordSize
                return (0..<4).reduce(0) { $0 << 8 | UInt32(bytes[offset + $1]) }
            }
            // The last record whose start is <= address.
            var low = 0, high = count - 1
            guard start(0) <= address else { return nil }
            while low < high {
                let mid = (low + high + 1) / 2
                if start(mid) <= address { low = mid } else { high = mid - 1 }
            }
            let offset = low * Self.recordSize + 4
            let code = String(decoding: [bytes[offset], bytes[offset + 1]], as: UTF8.self)
            return code == "ZZ" ? nil : code
        }
    }

    /// The country of `host`, an IPv4 address or a hostname resolved to IPv4. Hostname
    /// resolution blocks, so call this off the main thread.
    func countryCode(forHost host: String) -> String? {
        if let code = countryCode(forIPv4: host) { return code }
        return Self.resolveIPv4(host).lazy.compactMap { self.countryCode(forIPv4: $0) }.first
    }

    private static func resolveIPv4(_ host: String) -> [UInt32] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var results: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &results) == 0 else { return [] }
        defer { freeaddrinfo(results) }
        var addresses: [UInt32] = []
        var info = results
        while let current = info?.pointee {
            if let addr = current.ai_addr {
                let inAddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                addresses.append(UInt32(bigEndian: inAddr.s_addr))
            }
            info = current.ai_next
        }
        return addresses
    }

    /// The host part of a first hop such as "example.com:443", "1.2.3.4:8388" or "[::1]:443".
    static func host(ofFirstHop firstHop: String) -> String? {
        let trimmed = firstHop.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        }
        guard let colon = trimmed.lastIndex(of: ":") else { return trimmed }
        return String(trimmed[..<colon])
    }
}

/// A country by its ISO 3166-1 alpha-2 code, with a name in the user's language and a flag.
struct Country: Hashable, Identifiable {
    /// Uppercase ISO code, such as "CA".
    let code: String
    var id: String { code }

    init?(code: String) {
        let code = code.uppercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        self.code = code
    }

    func name(locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    /// Asset name of the flag in Assets.xcassets/Flags.
    var flagAssetName: String { "Flags/\(code.lowercased())" }
}

/// Resolves a server address to a country code. Tests use a fake.
protocol CountryResolving: Sendable {
    func countryCode(forHost host: String) -> String?
}

extension CountryLookup: CountryResolving {}

/// The bundle holding Keyline's resources: the app bundle in the app, the test bundle in tests.
extension Bundle {
    static let keylineResources = Bundle(for: BundleToken.self)
    private final class BundleToken {}
}
