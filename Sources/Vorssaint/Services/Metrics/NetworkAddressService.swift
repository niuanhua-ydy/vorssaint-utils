// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import SystemConfiguration

/// View-owned. Every reading comes from the local interface list, so no
/// request leaves the machine and there is no provider to name.
final class NetworkAddressService: ObservableObject {
    @Published private(set) var localAddresses: [String] = []

    func refreshLocalAddresses() {
        let addresses = Self.readLocalAddresses()
        guard addresses != localAddresses else { return }
        localAddresses = addresses
    }

    func cancel() {
        localAddresses = []
    }

    static func includesLocalAddress(name: String, flags: UInt32, family: Int32) -> Bool {
        family == AF_INET && flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING)
            && MetricFormat.includeNetworkInterface(name)
    }

    static func readLocalAddresses() -> [String] {
        let names = connectionNames()
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses = Set<String>()
        var current = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            guard includesLocalAddress(name: name, flags: entry.ifa_flags,
                                       family: Int32(address.pointee.sa_family)) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            // The system knows en0 as "Wi-Fi"; the BSD name means nothing on screen.
            addresses.insert(names[name].map { "\(ip) (\($0))" } ?? ip)
        }
        return addresses.sorted()
    }

    /// Command-bar snapshot, including valid VPN interfaces. This never contacts a server.
    static func commandBarAddresses() -> [CommandBarNetworkAddress] {
        let names = connectionNames()
        let store = SCDynamicStoreCreate(nil, "Vorssaint Command Bar" as CFString, nil, nil)
        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any] }
        let primary = global?["PrimaryInterface"] as? String
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var rows: [CommandBarNetworkAddress] = []
        var seen = Set<String>()
        var current = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr, Int32(address.pointee.sa_family) == AF_INET,
                  entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard CommandBarIPQuery.usableLocal(ip), seen.insert(name + "|" + ip).inserted else { continue }
            rows.append(CommandBarNetworkAddress(interface: name, name: names[name] ?? name,
                                                  address: ip, isPrimary: name == primary))
        }
        return rows.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            if $0.interface != $1.interface { return $0.interface.localizedStandardCompare($1.interface) == .orderedAscending }
            return $0.address < $1.address
        }
    }

    /// The system's own name per interface ("Wi-Fi", "Ethernet"), keyed by BSD
    /// name. An interface the system has no name for keeps no tag.
    private static func connectionNames() -> [String: String] {
        var names: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { continue }
            names[bsd] = display
        }
        return names
    }
}
