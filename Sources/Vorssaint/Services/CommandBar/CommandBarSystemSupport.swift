// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreFoundation

/// Explicit verbs are parsed before fuzzy search. In particular, a colon
/// always denotes a port, never a PID, even when no matching port was found.
enum CommandBarSystemQuery {
    enum Verb: String, CaseIterable { case quit, hide, forcequit, eject, kill, port }
    enum Target: Equatable { case all, name(String), pid(Int32), port(Int), invalid }
    struct Request: Equatable {
        let verb: Verb
        let target: Target
        let force: Bool
    }

    static func request(_ query: String) -> Request? {
        let parts = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let first = parts.first, let verb = Verb(rawValue: first.lowercased()) else { return nil }
        var argument = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        var force = verb == .forcequit
        if verb == .kill, argument.hasPrefix("-") {
            let signal = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            let flag = signal.first.map { $0.lowercased() } ?? ""
            let forceFlags = ["-9", "-kill", "-sigkill"]
            let gracefulFlags = ["-15", "-term", "-sigterm"]
            guard signal.count == 2, forceFlags.contains(flag) || gracefulFlags.contains(flag) else {
                return Request(verb: verb, target: .invalid, force: false)
            }
            force = forceFlags.contains(flag)
            argument = String(signal[1]).trimmingCharacters(in: .whitespaces)
        }
        if verb == .kill {
            let labeled = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if labeled.count == 2, ["pid", "process"].contains(labeled[0].lowercased()),
               labeled[1].allSatisfy({ $0.isASCII && $0.isNumber }) { argument = String(labeled[1]) }
        }
        let target: Target
        if argument.isEmpty {
            target = .all
        } else if verb == .kill, argument.hasPrefix(":") {
            target = portNumber(String(argument.dropFirst())).map(Target.port) ?? .invalid
        } else if verb == .port {
            let digits = argument.hasPrefix(":") ? String(argument.dropFirst()) : argument
            if digits.allSatisfy({ $0.isASCII && $0.isNumber }) || argument.hasPrefix(":") {
                target = portNumber(digits).map(Target.port) ?? .invalid
            } else { target = .name(argument) }
        } else if verb == .kill, argument.allSatisfy({ $0.isASCII && $0.isNumber }) {
            target = Int32(argument).flatMap { $0 > 0 ? .pid($0) : nil } ?? .invalid
        } else if verb == .kill, argument.hasPrefix("-") {
            target = .invalid
        } else { target = .name(argument) }
        return Request(verb: verb, target: target, force: force)
    }

    static func portNumber(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.count <= 5,
              text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = Int(text), (1...65535).contains(port) else { return nil }
        return port
    }

    static let fixed: [String: String] = [
        "lock": "action.lockScreen", "锁屏": "action.lockScreen",
        "sleep": "action.power.sleep", "睡眠": "action.power.sleep",
        "sleepdisplays": "action.displayOff", "息屏": "action.displayOff",
        "screensaver": "action.screenSaver", "屏保": "action.screenSaver",
        "trash": "action.showTrash", "废纸篓": "action.showTrash",
        "emptytrash": "action.emptyTrash", "清空废纸篓": "action.emptyTrash",
        "logout": "action.power.logOut", "注销": "action.power.logOut",
        "restart": "action.power.restart", "重启": "action.power.restart",
        "shutdown": "action.power.shutDown", "关机": "action.power.shutDown",
        "quitall": "action.quitAllApps", "ejectall": "action.ejectDisks",
        "volup": "action.volumeUp", "voldown": "action.volumeDown",
        "mute": "action.soundMute",
    ]

    static func fixedID(_ query: String) -> String? {
        fixed[query.lowercased().filter { !$0.isWhitespace }]
    }

    static func matches(_ name: String, target: Target) -> Bool {
        switch target {
        case .all: return true
        case .name(let term):
            return name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        default: return false
        }
    }
}

enum CommandBarIPQuery {
    static func matches(_ query: String) -> Bool {
        ["ip", "ip地址", "本机ip", "局域网ip", "内网ip", "外网ip", "公网ip", "publicip"]
            .contains(query.lowercased().filter { !$0.isWhitespace })
    }

    static func requestsPublic(_ query: String) -> Bool {
        ["外网ip", "公网ip", "publicip"].contains(query.lowercased().filter { !$0.isWhitespace })
    }

    static func ipv4(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy { $0.isASCII && $0.isNumber }
                && UInt8(part) != nil
        }) else { return nil }
        return value
    }

    static func usableLocal(_ value: String) -> Bool {
        guard let value = ipv4(value) else { return false }
        let parts = value.split(separator: ".").compactMap { Int(String($0)) }
        return parts[0] != 0 && parts[0] != 127 && parts[0] < 224
            && !(parts[0] == 169 && parts[1] == 254)
            && !(parts[0] == 198 && (18...19).contains(parts[1]))
    }
}

/// Fiat currencies only. Recognition is intentionally separate from network
/// access: typing an ordinary word or an incomplete conversion sends nothing.
enum CommandBarCurrency {
    struct Request: Equatable {
        let amount: Double
        let from: String
        let to: String
    }

    struct Table: Codable, Equatable {
        let date: String
        let fetchedAt: Date
        let rates: [String: Double]

        var isValid: Bool {
            CommandBarCurrency.validDate(date) && fetchedAt.timeIntervalSinceReferenceDate.isFinite
                && rates["USD"] == 1 && rates.count >= 2
                && rates.allSatisfy { CommandBarCurrency.codes.contains($0.key) && $0.value.isFinite && $0.value > 0 }
        }

        func convert(_ request: Request) -> Double? {
            guard let from = rates[request.from], from.isFinite, from > 0,
                  let to = rates[request.to], to.isFinite, to > 0 else { return nil }
            let result = request.amount / from * to
            return result.isFinite ? result : nil
        }

        func isStale(now: Date = Date()) -> Bool {
            now.timeIntervalSince(fetchedAt) >= 6 * 3600 || fetchedAt > now.addingTimeInterval(300)
        }
    }

    private static let codes = Set(Locale.commonISOCurrencyCodes)
    private static let names: [String: String] = {
        var names: [String: String] = [:]
        for code in codes {
            names[code.lowercased()] = code
            for locale in [Locale(identifier: "zh_CN"), Locale(identifier: "zh_TW"), Locale(identifier: "en_US")] {
                if let name = locale.localizedString(forCurrencyCode: code) { names[name.lowercased()] = code }
            }
        }
        for (code, aliases) in [
            "CNY": ["人民币", "人民幣", "rmb", "元", "¥", "￥"],
            "USD": ["美元", "美金", "刀", "美刀", "$", "us$"],
            "EUR": ["欧元", "歐元", "€"], "JPY": ["日元", "日圆", "日圓", "日币", "日幣"],
            "GBP": ["英镑", "英鎊", "£"], "HKD": ["港币", "港幣", "港元"],
            "TWD": ["台币", "台幣", "新台币", "新臺幣"], "KRW": ["韩元", "韓元"],
            "AUD": ["澳元", "澳币", "澳幣"], "CAD": ["加元", "加币", "加幣"],
            "SGD": ["新元", "新币", "新幣"],
        ] { for alias in aliases { names[alias] = code } }
        return names
    }()

    private static let sortedNames = names.sorted { $0.key.count > $1.key.count }

    static func code(_ text: String) -> String? {
        names[text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    static func request(_ query: String, home: String = Locale.current.currency?.identifier ?? "CNY") -> Request? {
        let value = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?？")))
        guard value.count <= 200 else { return nil }
        let pattern = #"\s+(?:to|in)\s+|\s*(?:兑换|兌換|是多少|等于|等於|转|轉|兑|兌|=|/)\s*"#
        let sides = value.components(separatedBy: try! NSRegularExpression(pattern: pattern))
        if sides.count == 2, let to = code(sides[1]), let source = side(sides[0], allowsImplicitOne: true) {
            return Request(amount: source.0, from: source.1, to: to)
        }
        // Two codes without an amount, e.g. USD CNY.
        let words = value.split(whereSeparator: \.isWhitespace)
        if words.count == 2, let from = code(String(words[0])), let to = code(String(words[1])) {
            return Request(amount: 1, from: from, to: to)
        }
        guard sides.count == 1, let source = side(value, allowsImplicitOne: false) else { return nil }
        let local = codes.contains(home) ? home : "CNY"
        let to = source.1 != local ? local : local == "USD" ? "EUR" : "USD"
        return Request(amount: source.0, from: source.1, to: to)
    }

    private static func side(_ text: String, allowsImplicitOne: Bool) -> (Double, String)? {
        if allowsImplicitOne, let code = code(text) { return (1, code) }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for (name, code) in sortedNames {
            let number: String
            if trimmed.hasSuffix(name) { number = String(trimmed.dropLast(name.count)) }
            else if trimmed.hasPrefix(name) { number = String(trimmed.dropFirst(name.count)) }
            else { continue }
            var token = number.trimmingCharacters(in: .whitespaces)
            var multiplier: Double = 1
            if let last = token.last, let factor = ["k": 1_000.0, "w": 10_000.0, "万": 10_000.0, "萬": 10_000.0, "m": 1_000_000.0][String(last)] {
                multiplier = factor; token.removeLast()
            }
            guard !token.isEmpty, token.allSatisfy({ $0.isASCII && ($0.isNumber || ".+-".contains($0)) }),
                  let value = Double(token), value.isFinite, (value * multiplier).isFinite else { continue }
            return (value * multiplier, code)
        }
        return nil
    }

    private static func validDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    static func decode(_ data: Data, now: Date = Date()) -> Table? {
        guard data.count <= 1_048_576,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let date = json["date"] as? String,
              validDate(date),
              let raw = json["usd"] as? [String: Any] else { return nil }
        var rates: [String: Double] = [:]
        for (key, value) in raw where codes.contains(key.uppercased()) {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue > 0 else { continue }
            rates[key.uppercased()] = number.doubleValue
        }
        guard rates["USD"] == 1, rates.count >= 2 else { return nil }
        return Table(date: date, fetchedAt: now, rates: rates)
    }

    static func formatted(_ value: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = abs(value) > 0 && abs(value) < 1 ? 8 : 4
        return (formatter.string(from: NSNumber(value: value)) ?? String(value)) + " " + code
    }
}

private extension String {
    func components(separatedBy expression: NSRegularExpression) -> [String] {
        var result: [String] = []
        var start = startIndex
        for match in expression.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let range = Range(match.range, in: self) else { continue }
            result.append(String(self[start..<range.lowerBound])); start = range.upperBound
        }
        result.append(String(self[start...])); return result
    }
}
