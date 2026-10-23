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

    /// Routable IPv6 ranges, sent into the tunnel and dropped there because the proxy only
    /// carries IPv4. Same ranges upstream's Windows client blocks (OutlineService.cs).
    static let blockedIPv6Subnets: [(address: String, prefixLength: Int)] = [
        ("fc00::", 7), ("2000::", 4), ("3000::", 4),
    ]
    /// The tunnel's own IPv6 address, from a unique local range, needed to claim IPv6 routes.
    static let vpnIPv6Address = "fd6b:6579:6c69::1"

    /// The tunnel's network settings for `splitTunnel`. `resolvedAddresses` are the IPv4
    /// addresses the listed domains resolved to.
    static func make(splitTunnel: SplitTunnelSettings = SplitTunnelSettings(),
                     resolvedAddresses: [String] = []) -> NEPacketTunnelNetworkSettings {
        // The remote address is not used, but must be valid, or the system rejects the
        // settings with "Invalid NETunnelNetworkSettings tunnelRemoteAddress".
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "::")

        let vpnAddress = selectVpnAddress(interfaceAddresses: interfaceIPv4Addresses())
        let ipv4Settings = NEIPv4Settings(addresses: [vpnAddress], subnetMasks: ["255.255.255.0"])
        let routes = ipv4Routes(splitTunnel: splitTunnel, resolvedAddresses: resolvedAddresses)
        ipv4Settings.includedRoutes = routes.included.map(\.route)
        ipv4Settings.excludedRoutes = routes.excluded.map(\.route)
        settings.ipv4Settings = ipv4Settings

        // Block IPv6 whenever the VPN carries everything by default. When only listed
        // destinations use the VPN, everything else (IPv6 included) goes direct anyway.
        if splitTunnel.mode != .include {
            let ipv6Settings = NEIPv6Settings(addresses: [vpnIPv6Address], networkPrefixLengths: [64])
            ipv6Settings.includedRoutes = blockedIPv6Subnets.map {
                NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefixLength))
            }
            settings.ipv6Settings = ipv6Settings
        }

        settings.dnsSettings = NEDNSSettings(servers: [dnsResolver])
        return settings
    }

    /// The IPv4 routes into (`included`) and around (`excluded`) the tunnel.
    static func ipv4Routes(splitTunnel: SplitTunnelSettings,
                           resolvedAddresses: [String]) -> (included: [IPv4Subnet], excluded: [IPv4Subnet]) {
        let everything = IPv4Subnet(cidr: "0.0.0.0/0")!
        let local = splitTunnel.bypassLocalNetwork ? excludedSubnets.compactMap(IPv4Subnet.init(cidr:)) : []
        let listed = unique(splitTunnel.subnets + resolvedAddresses.compactMap { IPv4Subnet(cidr: "\($0)/32") })
        switch splitTunnel.mode {
        case .off:
            return ([everything], local)
        case .exclude:
            return ([everything], unique(local + listed))
        case .include:
            // DNS always goes to the resolver inside the tunnel.
            return (unique(listed + [IPv4Subnet(cidr: "\(dnsResolver)/32")!]), local)
        }
    }

    private static func unique(_ subnets: [IPv4Subnet]) -> [IPv4Subnet] {
        var seen = Set<IPv4Subnet>()
        return subnets.filter { seen.insert($0).inserted }
    }

    /// The packets to pass to the Go core: IPv4 only. IPv6 packets are dropped (blocked).
    static func ipv4Packets(_ packets: [Data], protocols: [NSNumber]) -> [Data] {
        zip(packets, protocols).compactMap { $1.int32Value == AF_INET ? $0 : nil }
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

