// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PortManagerEntry: Identifiable, Equatable {
    let port: Int
    let protocolName: String
    let address: String
    let pid: Int32
    let processName: String
    let startedAt: UInt64?
    var id: String { "\(protocolName)-\(port)-\(pid)-\(address)" }
}

enum PortManagerSupport {
    static func browserURL(for entry: PortManagerEntry) -> URL? {
        guard entry.protocolName == "TCP", (1...65535).contains(entry.port),
              let separator = entry.address.lastIndex(of: ":") else { return nil }
        let host = String(entry.address[..<separator])
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        // Wildcard binds are not destinations. Preserve the address family
        // when it is known, and a specific bind when localhost cannot reach it.
        switch host {
        case "*": components.host = "localhost"
        case "0.0.0.0": components.host = "127.0.0.1"
        case "[::]", "::": components.host = "[::1]"
        default: components.host = host
        }
        components.port = entry.port
        return components.url
    }

    /// Whether an lsof endpoint such as `*:3000` or `127.0.0.1:3000` is bound
    /// to every interface rather than one specific address. A wildcard bind
    /// accepts connections from other machines on the network unless a
    /// firewall stops them, so it is worth pointing out.
    static func listensOnAllInterfaces(_ endpoint: String) -> Bool {
        guard let separator = endpoint.lastIndex(of: ":") else { return false }
        var host = endpoint[..<separator]
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = host.dropFirst().dropLast()
        }
        return host == "*" || host == "0.0.0.0" || host == "::"
    }

    static func parseLsof(_ text: String) -> [PortManagerEntry] {
        var name = "", pid: Int32 = 0, address = "", port = 0, proto = "TCP"
        var rows: [PortManagerEntry] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n").map(String.init) {
            guard let type = line.first else { continue }
            let value = String(line.dropFirst())
            switch type {
            case "p":
                pid = Int32(value) ?? 0; port = 0; address = ""
            case "c": name = value
            case "P": proto = value
            case "n":
                address = value
                guard let last = value.split(separator: ":").last, let parsed = Int(last) else {
                    port = 0
                    continue
                }
                port = parsed
                if pid > 0 && port > 0 {
                    let key = "\(proto)|\(port)|\(address)|\(pid)"
                    if seen.insert(key).inserted {
                        rows.append(.init(port: port, protocolName: proto, address: address,
                                          pid: pid, processName: name, startedAt: nil))
                    }
                }
            case "T": continue
            default: continue
            }
        }
        return rows.sorted { $0.port == $1.port ? $0.processName < $1.processName : $0.port < $1.port }
    }
}

// MARK: - Command Bar rows

/// How a listening port reads as a Command Bar row. Pure, so the words the
/// bar ranks against and the query that brings ports into a plain search are
/// pinned by tests rather than by trying it.
extension PortManagerSupport {
    /// What Return does on a port row. Terminating needs Kill Process and an
    /// identity the scan could confirm; without either the row stays useful
    /// by opening what is listening, or at least handing over the number.
    enum CommandBarPrimary: Equatable {
        case terminate
        case openInBrowser
        case copyPort
    }

    static func commandBarPrimary(canTerminate: Bool, hasBrowserURL: Bool) -> CommandBarPrimary {
        if canTerminate { return .terminate }
        return hasBrowserURL ? .openInBrowser : .copyPort
    }

    /// The port leads, written the way people type it, so a column of rows
    /// reads as a column of ports.
    static func commandBarTitle(for entry: PortManagerEntry) -> String {
        ":\(entry.port)  \(entry.processName)"
    }

    /// Protocol, bind address and PID, plus the same all-interfaces warning
    /// the Port Manager page shows as a badge. Plain `String(format:)` and
    /// interpolation never group digits, so 5173 never reads "5,173".
    static func commandBarSubtitle(for entry: PortManagerEntry,
                                   pidFormat: String,
                                   allInterfaces: String) -> String {
        var parts = [entry.protocolName, entry.address, String(format: pidFormat, entry.pid)]
        if listensOnAllInterfaces(entry.address) { parts.append(allInterfaces) }
        return parts.joined(separator: " · ")
    }

    /// The bare number and its colon form, so both `3000` and `:3000` are
    /// whole-word hits, and the process name. The PID stays out on purpose:
    /// a typed port would otherwise also find every PID that contains it.
    static func commandBarKeywords(for entry: PortManagerEntry) -> String {
        "\(entry.port) :\(entry.port) \(entry.processName)"
    }

    /// The digits of a query that reads as a port, or nil. A bare number needs
    /// two digits before it counts, so a single keystroke does not pull every
    /// port into the list; with a leading colon one digit is already a clear
    /// ask. Anything that could not be a TCP port is left to the rest of the bar.
    static func portQuery(from query: String) -> String? {
        var text = Substring(query.trimmingCharacters(in: .whitespaces))
        let colon = text.hasPrefix(":")
        if colon { text = text.dropFirst() }
        guard (colon ? 1 : 2)...5 ~= text.count,
              text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), (1...65535).contains(value) else { return nil }
        return String(text)
    }

    /// Words that find the "Port Manager" row: the language's own, plus the
    /// English and Simplified Chinese ones, so "port", "lsof" and "端口" find
    /// it whatever language the app is in.
    static func browseKeywords(_ language: AppLanguage) -> String {
        var words: [String] = []
        for strings in [FeatureStrings.portManager(language), .enUS, .zhHans] {
            for word in [strings.title, strings.browseKeywords]
            where !words.contains(word) {
                words.append(word)
            }
        }
        return words.joined(separator: " ")
    }
}
