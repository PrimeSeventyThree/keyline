import NetworkExtension
import XCTest

/// Ported from upstream's VpnExtensionTest.swift, plus subnet parsing.
final class TunnelNetworkSettingsTests: XCTestCase {
    func testSelectsAnUnusedSubnet() {
        let address = TunnelNetworkSettings.selectVpnAddress(interfaceAddresses: ["172.16.9.2", "192.168.20.2", "169.254.19.1"])
        XCTAssertEqual(address, "10.111.222.0")
    }

    func testFallsBackToAnyCandidateWhenAllAreUsed() {
        let address = TunnelNetworkSettings.selectVpnAddress(
            interfaceAddresses: ["10.111.222.1", "172.16.9.2", "192.168.20.2", "169.254.19.1"])
        XCTAssertTrue(TunnelNetworkSettings.vpnSubnetCandidates.values.contains(address))
    }

    func testSubnetMasks() {
        XCTAssertEqual(IPv4Subnet(cidr: "10.0.0.0/8")?.mask, "255.0.0.0")
        XCTAssertEqual(IPv4Subnet(cidr: "100.64.0.0/10")?.mask, "255.192.0.0")
        XCTAssertEqual(IPv4Subnet(cidr: "192.0.0.0/24")?.mask, "255.255.255.0")
        XCTAssertEqual(IPv4Subnet(cidr: "0.0.0.0/0")?.mask, "0.0.0.0")
        XCTAssertEqual(IPv4Subnet(cidr: "1.2.3.4/32")?.mask, "255.255.255.255")
        XCTAssertNil(IPv4Subnet(cidr: "10.0.0.0"))
        XCTAssertNil(IPv4Subnet(cidr: "10.0.0.0/33"))
    }

    func testSettingsRouteEverythingButLocalRangesAndUseTheFakeResolver() throws {
        let settings = TunnelNetworkSettings.make()
        let ipv4 = try XCTUnwrap(settings.ipv4Settings)
        XCTAssertEqual(ipv4.includedRoutes, [NEIPv4Route.default()])
        XCTAssertEqual(ipv4.excludedRoutes?.count, TunnelNetworkSettings.excludedSubnets.count)
        XCTAssertEqual(settings.dnsSettings?.servers, ["169.254.113.53"])
    }

    func testRoutableIPv6GoesIntoTheTunnel() throws {
        let ipv6 = try XCTUnwrap(TunnelNetworkSettings.make().ipv6Settings)
        let routes = (ipv6.includedRoutes ?? []).map { "\($0.destinationAddress)/\($0.destinationNetworkPrefixLength)" }
        XCTAssertEqual(routes, ["fc00::/7", "2000::/4", "3000::/4"])
        XCTAssertFalse(routes.contains { $0.hasPrefix("fe80") }, "link-local stays outside the tunnel")
    }

    func testOnlyIPv4PacketsReachTheGoCore() {
        let v4 = Data([0x45, 0, 0, 20]), v6 = Data([0x60, 0, 0, 0])
        let kept = TunnelNetworkSettings.ipv4Packets(
            [v4, v6, v4], protocols: [NSNumber(value: AF_INET), NSNumber(value: AF_INET6), NSNumber(value: AF_INET)])
        XCTAssertEqual(kept, [v4, v4])
    }
}
