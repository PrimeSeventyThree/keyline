import NetworkExtension
import XCTest

final class SplitTunnelEntryTests: XCTestCase {
    func testAddressesAndSubnets() {
        XCTAssertEqual(SplitTunnelEntry("203.0.113.7"), .subnet(IPv4Subnet(cidr: "203.0.113.7/32")!))
        XCTAssertEqual(SplitTunnelEntry(" 10.0.0.0/8 "), .subnet(IPv4Subnet(cidr: "10.0.0.0/8")!))
        XCTAssertEqual(IPv4Subnet(cidr: "10.1.2.3/8")?.cidr, "10.0.0.0/8", "host bits are cleared")
        XCTAssertNil(IPv4Subnet(cidr: "300.1.1.1/32"))
    }

    func testDomains() {
        XCTAssertEqual(SplitTunnelEntry("Example.COM"), .domain("example.com"))
        XCTAssertEqual(SplitTunnelEntry("www.example.co.uk."), .domain("www.example.co.uk"))
        XCTAssertEqual(SplitTunnelEntry("my-site.example"), .domain("my-site.example"))
    }

    func testRejectsEverythingElse() {
        for text in ["", "localhost", "example", "-bad.example.com", "bad-.example.com", "exa mple.com",
                     "2001:db8::1", "2001:db8::/32", "1.2.3", "10.0.0.0/33", "https://example.com"] {
            XCTAssertNil(SplitTunnelEntry(text), text)
        }
    }

    func testSettingsSurviveEncoding() {
        let settings = SplitTunnelSettings(mode: .include, bypassLocalNetwork: false, entries: ["10.0.0.0/8", "example.com"])
        XCTAssertEqual(SplitTunnelSettings.decoded(from: settings.encoded()), settings)
        XCTAssertEqual(settings.subnets, [IPv4Subnet(cidr: "10.0.0.0/8")!])
        XCTAssertEqual(settings.domains, ["example.com"])
        XCTAssertNil(SplitTunnelSettings.decoded(from: Data("nope".utf8)))
    }

    func testResolvesIPLiteralsWithoutTheNetwork() {
        XCTAssertEqual(SplitTunnelSettings.resolveIPv4(["192.0.2.10"]), ["192.0.2.10"])
    }
}

final class SplitTunnelRouteTests: XCTestCase {
    private let local = TunnelNetworkSettings.excludedSubnets.compactMap(IPv4Subnet.init(cidr:))
    private let listed = SplitTunnelSettings(mode: .exclude, entries: ["203.0.113.0/24", "example.com"])

    func testOffSendsEverythingThroughTheTunnel() {
        let routes = TunnelNetworkSettings.ipv4Routes(splitTunnel: SplitTunnelSettings(), resolvedAddresses: [])
        XCTAssertEqual(routes.included.map(\.cidr), ["0.0.0.0/0"])
        XCTAssertEqual(routes.excluded, local)
    }

    func testLocalNetworkCanGoThroughTheTunnel() {
        let routes = TunnelNetworkSettings.ipv4Routes(splitTunnel: SplitTunnelSettings(bypassLocalNetwork: false), resolvedAddresses: [])
        XCTAssertEqual(routes.excluded, [])
    }

    func testExcludeKeepsListedDestinationsOutside() {
        let routes = TunnelNetworkSettings.ipv4Routes(splitTunnel: listed, resolvedAddresses: ["198.51.100.4"])
        XCTAssertEqual(routes.included.map(\.cidr), ["0.0.0.0/0"])
        XCTAssertTrue(routes.excluded.map(\.cidr).contains("203.0.113.0/24"))
        XCTAssertTrue(routes.excluded.map(\.cidr).contains("198.51.100.4/32"), "a domain's address is excluded")
        XCTAssertTrue(routes.excluded.contains(local[0]), "local ranges stay excluded")
    }

    func testIncludeOnlyRoutesListedDestinationsAndDNS() {
        var settings = listed
        settings.mode = .include
        let routes = TunnelNetworkSettings.ipv4Routes(splitTunnel: settings, resolvedAddresses: ["198.51.100.4", "198.51.100.4"])
        XCTAssertEqual(routes.included.map(\.cidr), ["203.0.113.0/24", "198.51.100.4/32", "169.254.113.53/32"],
                       "listed, resolved (once) and the tunnel's DNS resolver")
    }

    func testIPv6IsBlockedUnlessOnlyListedTrafficUsesTheVPN() {
        XCTAssertNotNil(TunnelNetworkSettings.make(splitTunnel: listed).ipv6Settings)
        var include = listed
        include.mode = .include
        XCTAssertNil(TunnelNetworkSettings.make(splitTunnel: include).ipv6Settings)
        XCTAssertEqual(TunnelNetworkSettings.make(splitTunnel: include).dnsSettings?.servers, ["169.254.113.53"])
    }
}

@MainActor
final class SplitTunnelSettingsStorageTests: XCTestCase {
    func testSettingsPersist() {
        let suite = "keyline-split-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, domain: suite)
        XCTAssertEqual(settings.splitTunnel, SplitTunnelSettings(), "off by default")
        settings.splitTunnel = SplitTunnelSettings(mode: .exclude, entries: ["example.com"])
        XCTAssertEqual(AppSettings(defaults: defaults, domain: suite).splitTunnel.entries, ["example.com"])
    }

    func testSummary() {
        XCTAssertEqual(SplitTunnelSheet.summary(SplitTunnelSettings()), "All traffic goes through the VPN.")
        XCTAssertEqual(SplitTunnelSheet.summary(SplitTunnelSettings(mode: .include, entries: ["a.example", "b.example"])),
                       "Only listed · 2 entries")
        XCTAssertEqual(SplitTunnelSheet.summary(SplitTunnelSettings(mode: .exclude, entries: ["a.example"])),
                       "Exclude listed · 1 entry")
    }
}
