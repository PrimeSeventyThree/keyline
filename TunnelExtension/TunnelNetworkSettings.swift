// Ported from Outline's PacketTunnelProvider.swift
// (client/src/cordova/apple/OutlineLib/VpnExtension/Sources/PacketTunnelProvider.swift),
// Copyright 2024 The Outline Authors, Apache License 2.0. Changed by Pulsbeat Media Inc.:
// restructured into an enum, Subnet replaced by a value type.

import Darwin
import NetworkExtension
import os

enum TunnelNetworkSettings {
    /// A "fake" DNS resolver inside the tunnel. The Go core intercepts DNS sent to this
    /// address. Must match client/go/outline/configregistry/outline_dns_intercept.go.
    static let dnsResolver = "169.254.113.53"

    /// VPN interface addresses, keyed by the first octet of the subnet they belong to.
    static let vpnSubnetCandidates: [String: String] = [
        "10": "10.111.222.0",
        "172": "172.16.9.1",
        "192": "192.168.20.1",
        "169": "169.254.19.0",
    ]

    /// Local and reserved ranges that stay outside the tunnel.
    static let excludedSubnets = [
        "10.0.0.0/8",
        "100.64.0.0/10",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.0.0.0/24",
        "192.0.2.0/24",
        "192.31.196.0/24",
        "192.52.193.0/24",
        "192.88.99.0/24",
        "192.168.0.0/16",
        "192.175.48.0/24",
        "198.18.0.0/15",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "240.0.0.0/4",
    ]

    static func make() -> NEPacketTunnelNetworkSettings {
        // The remote address is not used, but must be valid, or the system rejects the
        // settings with "Invalid NETunnelNetworkSettings tunnelRemoteAddress".
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "::")

        let vpnAddress = selectVpnAddress(interfaceAddresses: interfaceIPv4Addresses())
        let ipv4Settings = NEIPv4Settings(addresses: [vpnAddress], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = excludedSubnets.compactMap(IPv4Subnet.init(cidr:)).map(\.route)
        settings.ipv4Settings = ipv4Settings

        settings.dnsSettings = NEDNSSettings(servers: [dnsResolver])
        return settings
    }

    /// Picks a VPN address in a private subnet no local interface uses. If all candidate
    /// subnets are in use, any candidate will do: an actual address collision is unlikely.
    static func selectVpnAddress(interfaceAddresses: [String]) -> String {
        let candidates = vpnSubnetCandidates.filter { prefix, _ in
            !interfaceAddresses.contains { $0.hasPrefix(prefix) }
        }
        return (candidates.isEmpty ? vpnSubnetCandidates : candidates).randomElement()!.value
    }

    /// IPv4 addresses of all network interfaces.
    static func interfaceIPv4Addresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else {
            Logger.keyline("tunnel").error("Failed to retrieve network interface addresses")
            return []
        }
        defer { freeifaddrs(interfaces) }

        var addresses: [String] = []
        var interface = interfaces
        while let current = interface?.pointee {
            if let addr = current.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let inAddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                addresses.append(String(cString: inet_ntoa(inAddr)))
            }
            interface = current.ifa_next
        }
        return addresses
    }
}

/// An IPv4 subnet in CIDR notation, such as "10.0.0.0/8".
struct IPv4Subnet: Equatable {
    let address: String
    let prefix: UInt8

    init?(cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = UInt8(parts[1]), prefix <= 32 else { return nil }
        self.address = String(parts[0])
        self.prefix = prefix
    }

    var mask: String {
        let bits: UInt32 = prefix == 0 ? 0 : 0xffff_ffff << (32 - UInt32(prefix))
        return [24, 16, 8, 0].map { String((bits >> $0) & 0xff) }.joined(separator: ".")
    }

    var route: NEIPv4Route {
        NEIPv4Route(destinationAddress: address, subnetMask: mask)
    }
}
