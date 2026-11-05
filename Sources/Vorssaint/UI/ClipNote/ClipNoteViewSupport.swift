// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ClipNoteCore
import QuickLookThumbnailing
import SwiftUI

extension Color {
    init(clipNoteHex hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0x8E8E93
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

extension ClipType {
    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .rich: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var tint: Color {
        switch self {
        case .text: return Color(clipNoteHex: "#5E6AD2")
        case .rich: return Color(clipNoteHex: "#8E5CD9")
        case .link: return Color(clipNoteHex: "#0A84FF")
        case .image: return Color(clipNoteHex: "#30A46C")
        case .file: return Color(clipNoteHex: "#E5893B")
        }
    }
}

struct ClipNoteVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

@MainActor
enum ClipNoteFormatters {
    private static var relativeFormatters: [String: RelativeDateTimeFormatter] = [:]

    static func relativeTime(_ date: Date, now: Date, strings: ClipNoteStrings) -> String {
        if now.timeIntervalSince(date) < 60 { return strings.justNow }
        let language = L10n.shared.language
        let formatter = relativeFormatters[language.rawValue] ?? {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = language.formattingLocale()
            formatter.unitsStyle = .full
            relativeFormatters[language.rawValue] = formatter
            return formatter
        }()
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func meta(for item: ClipItem, strings: ClipNoteStrings) -> String {
        switch item.type {
        case .text, .rich: return String(format: strings.charactersFormat, item.charCount)
        case .link: return URL(string: item.content)?.host ?? String(format: strings.charactersFormat, item.charCount)
        case .image: return "\(item.width) × \(item.height)"
        case .file:
            let count = item.filePaths.count
            if count == 1, let size = fileSize(item.filePaths[0]) { return size }
            return String(format: strings.filesFormat, count)
        }
    }

    static func fileSize(_ path: String) -> String? {
        let resolved = (path as NSString).resolvingSymlinksInPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved),
              let size = attributes[.size] as? Int64,
              (attributes[.type] as? FileAttributeType) != .typeDirectory else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// Source app icons.
@MainActor
enum ClipNoteAppIcons {
    private static var cache: [String: NSImage] = [:]
    private static let pressure = MemoryPressureObservation {
        MainActor.assumeIsolated { removeAll() }
    }

    static func removeAll() {
        cache = [:]
        menuCache = [:]
    }
    private static var menuCache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        _ = pressure
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let original = NSWorkspace.shared.icon(forFile: url.path)
        let icon = ImageThumbnailer.thumbnail(for: original, pointSize: 64) ?? original
        if cache.count >= 128 { removeAll() }
        cache[bundleID] = icon
        return icon
    }

    /// A 16 pt icon for menu items.
    static func menuIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = menuCache[bundleID] { return cached }
        guard let icon = icon(for: bundleID)?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        menuCache[bundleID] = icon
        return icon
    }
}

/// A source app's color: the hue that dominates its icon, the way Paste
/// colors its cards.
@MainActor
enum ClipNoteAppColors {
    private static var cache: [String: Color] = [:]
    /// For icons with no real color (black, white, grey).
    static let neutral = Color(red: 0.24, green: 0.25, blue: 0.27)

    /// Multi-colored icons pick unreliably, so common apps are set by hand to look as they do in Paste.
    private static let overrides: [String: String] = [
        "com.google.Chrome": "#1A73E8",
        "com.google.Chrome.canary": "#1A73E8",
        "com.microsoft.edgemac": "#0C7CD5",
        "com.apple.Safari": "#1E88E5",
        "com.microsoft.VSCode": "#1E7FD0",
        "com.apple.dt.Xcode": "#1D7AF2",
        "com.apple.Terminal": "#3C3C40",
        "com.googlecode.iterm2": "#3C3C40",
    ]

    static func color(for bundleID: String?) -> Color? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        if let hex = overrides[bundleID] ?? (bundleID.hasPrefix("com.jetbrains.") ? "#F27A1A" : nil) {
            let color = Color(clipNoteHex: hex)
            cache[bundleID] = color
            return color
        }
        guard let icon = ClipNoteAppIcons.icon(for: bundleID) else { return nil }
        let color = dominantColor(of: icon) ?? neutral
        cache[bundleID] = color
        return color
    }

    static func dominantColor(of image: NSImage) -> Color? {
        let size = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        // Twelve hue buckets, counting only saturated pixels that are not too dark.
        var weights = [Double](repeating: 0, count: 12)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: 12)
        for x in 0..<size {
            for y in 0..<size {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.6 else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                guard s > 0.35, b > 0.3 else { continue }
                let bucket = min(11, Int(h * 12))
                // The middle counts more: an icon's subject usually sits there (Chrome's blue center).
                let dx = Double(x) - Double(size - 1) / 2, dy = Double(y) - Double(size - 1) / 2
                let centrality = exp(-(dx * dx + dy * dy) / (2 * pow(Double(size) * 0.28, 2)))
                let w = Double(s * b) * (0.35 + centrality)
                weights[bucket] += w
                sums[bucket].r += Double(c.redComponent) * w
                sums[bucket].g += Double(c.greenComponent) * w
                sums[bucket].b += Double(c.blueComponent) * w
            }
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 6 else { return nil }
        let w = weights[best]
        let average = NSColor(deviceRed: sums[best].r / w, green: sums[best].g / w, blue: sums[best].b / w, alpha: 1)
        // Bounded brightness and a floor on saturation keep white text readable.
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(max(s, 0.55)), brightness: Double(min(max(b, 0.55), 0.86)))
    }
}

/// File icons.
@MainActor
enum ClipNoteFileIcons {
    private static var cache: [String: NSImage] = [:]
    private static let pressure = MemoryPressureObservation {
        MainActor.assumeIsolated { removeAll() }
    }

    static func removeAll() {
        cache = [:]
    }

    static func icon(for path: String) -> NSImage {
        _ = pressure
        if let cached = cache[path] { return cached }
        let original = NSWorkspace.shared.icon(forFile: path)
        let icon = ImageThumbnailer.thumbnail(for: original, pointSize: 64) ?? original
        if cache.count >= 128 { cache.removeAll() }
        cache[path] = icon
        return icon
    }
}

/// Image thumbnails, decoded at the size shown and cached, never the full image.
final class ClipNoteThumbnails: @unchecked Sendable {
    static let shared = ClipNoteThumbnails()
    private let cache = CostBoundedCache<String, NSImage>(byteLimit: 32 * 1024 * 1024, countLimit: 300)
    private var pressure: MemoryPressureObservation?

    init() {
        pressure = MemoryPressureObservation { [weak self] in self?.removeAll() }
    }

    func removeAll() { cache.removeAll() }

    private static func cost(of image: NSImage) -> Int {
        var cost = 0
        for rep in image.representations {
            let bytes = CostBoundedCache<String, NSImage>.bitmapCost(
                width: rep.pixelsWide, height: rep.pixelsHigh,
                bytesPerRow: (rep as? NSBitmapImageRep)?.bytesPerRow)
            let sum = cost.addingReportingOverflow(bytes)
            if sum.overflow { return Int.max }
            cost = sum.partialValue
        }
        // Quick Look normally gives bitmap reps. A representation without
        // pixel dimensions is displayed but not cached with a fictitious cost.
        return cost > 0 ? cost : Int.max
    }

    func cached(for url: URL, maxPixel: Int) -> NSImage? {
        cache.value(for: "\(url.path)#\(maxPixel)")
    }

    func fileThumbnail(path: String, size: CGSize) async -> NSImage? {
        guard let key = Self.fileKey(path: path, size: size) else { return nil }
        if let cached = cache.value(for: key) { return cached }
        let generation = cache.generation
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: size,
                                                   scale: 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
              !Task.isCancelled else { return nil }
        let image = representation.nsImage
        cache.insert(image, for: key, cost: Self.cost(of: image), generation: generation)
        return image
    }

    func cachedFileThumbnail(path: String, size: CGSize) -> NSImage? {
        Self.fileKey(path: path, size: size).flatMap { cache.value(for: $0) }
    }

    private static func fileKey(path: String, size: CGSize) -> String? {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else {
            return nil
        }
        return "ql:\(path)#\(Int(size.width))x\(Int(size.height))#\(modified.timeIntervalSince1970)"
    }

    func thumbnail(for url: URL, maxPixel: Int) async -> NSImage? {
        let key = "\(url.path)#\(maxPixel)"
        if let cached = cache.value(for: key) { return cached }
        let generation = cache.generation
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(
                    url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }.value
        guard !Task.isCancelled else { return nil }
        if let image { cache.insert(image, for: key, cost: Self.cost(of: image), generation: generation) }
        return image
    }
}

struct ClipNoteThumbnailView: View {
    let url: URL
    let maxPixel: Int
    @State private var image: NSImage?

    init(url: URL, maxPixel: Int = 600) {
        self.url = url
        self.maxPixel = maxPixel
        // A cached thumbnail shows at once, without a flash.
        _image = State(initialValue: ClipNoteThumbnails.shared.cached(for: url, maxPixel: maxPixel))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .transition(.opacity)
            } else {
                Color.primary.opacity(0.04)
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            let loaded = await ClipNoteThumbnails.shared.thumbnail(for: url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// A file's content thumbnail, with its icon until one is made (or when none can be).
struct ClipNoteFileThumbnailView: View {
    let path: String
    let size: CGSize
    @State private var image: NSImage?

    init(path: String, size: CGSize) {
        self.path = path
        self.size = size
        _image = State(initialValue: ClipNoteThumbnails.shared.cachedFileThumbnail(path: path, size: size))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .transition(.opacity)
            } else {
                Image(nsImage: ClipNoteFileIcons.icon(for: path)).resizable().scaledToFit()
                    .frame(maxWidth: min(size.width, 72), maxHeight: min(size.height, 72))
            }
        }
        .task(id: path) {
            guard image == nil else { return }
            let loaded = await ClipNoteThumbnails.shared.fileThumbnail(path: path, size: size)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// A restrained highlight on search hits.
enum ClipNoteHighlighter {
    static func attributed(_ text: String, terms: [String],
                           color: Color = Color.yellow.opacity(0.45)) -> AttributedString {
        var result = AttributedString(text)
        guard !terms.isEmpty else { return result }
        let ns = text as NSString
        for term in terms where !term.isEmpty {
            var searchRange = NSRange(location: 0, length: ns.length)
            while true {
                let found = ns.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard found.location != NSNotFound, let range = Range(found, in: text),
                      let attributedRange = Range(range, in: result) else { break }
                result[attributedRange].backgroundColor = color
                let next = found.location + max(found.length, 1)
                guard next < ns.length else { break }
                searchRange = NSRange(location: next, length: ns.length - next)
            }
        }
        return result
    }
}
