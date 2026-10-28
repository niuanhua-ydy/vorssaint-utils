// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchQQLyricsTests {
    static func run(_ suite: TestSuite) {
        let playback = NotchPlayback(
            track: RadialNowPlayingSnapshot(title: "Fixture Song", artist: "Fixture Artist", album: "Fixture Album",
                                           artworkData: nil, appBundleIdentifier: "com.tencent.QQMusicMac", appPID: 42),
            isPlaying: true, elapsed: 3, duration: 180, rate: 1, sampledAt: .now, canSeek: false,
            itemIdentifier: "system-session-uuid")
        let track = NotchMusicIdentity(playback)
        let mid = "003AAAAAAAAAAA"
        let record: [String: Any] = ["songmid": mid, "songname": "Fixture Song", "albumname": "Fixture Album",
                                    "singer": [["name": "Fixture Artist"]], "interval": 180]
        func encode(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        func catalog(_ rows: [[String: Any]]) -> Data { encode(["code": 0, "data": ["song": ["list": rows]]]) }
        let search = NotchLyricsSupport.qqSearchURL(for: track)!
        suite.expect(search.host == "c.y.qq.com" && search.scheme == "https"
                     && URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?
                        .first(where: { $0.name == "w" })?.value == "Fixture Song Fixture Artist",
                     "QQ search sends only the current title and artist to the fixed HTTPS catalog")
        suite.expect(NotchLyricsSupport.qqSongMID(catalog([record]), for: track) == mid,
                     "QQ resolves a song MID from matching recording metadata, not the system UUID")
        for (key, value) in [("songname", "Fixture Song (Live)" as Any), ("singer", [["name": "Cover Artist"]]),
                             ("albumname", "Different Album"), ("interval", 190), ("songmid", "../bad?redirect")] {
            var wrong = record; wrong[key] = value
            suite.expect(NotchLyricsSupport.qqSongMID(catalog([wrong]), for: track) == nil,
                         "QQ rejects mismatched or unsafe candidate field \(key)")
        }
        var other = record; other["songmid"] = "004BBBBBBBBBBB"
        suite.expect(NotchLyricsSupport.qqSongMID(catalog([record, other]), for: track) == nil
                     && NotchLyricsSupport.qqSongMID(catalog([record, record]), for: track) == mid,
                     "distinct matching MIDs are ambiguous; duplicate catalog rows are harmless")
        suite.expect(NotchLyricsSupport.qqSongMID(catalog(Array(repeating: record, count: 21)), for: track) == nil
                     && NotchLyricsSupport.qqSongMID(Data(repeating: 32, count: NotchLyricsSupport.maximumSearchBytes + 1), for: track) == nil,
                     "QQ search envelopes and candidate counts are bounded")
        suite.expect(NotchLyricsSupport.qqLyricsURL(songMID: mid)?.host == "c.y.qq.com"
                     && NotchLyricsSupport.qqLyricsURL(songMID: "https://other.test/") == nil,
                     "catalog data cannot choose a lyrics host or inject URL parameters")
        let otherPlayer = NotchPlayback(track: RadialNowPlayingSnapshot(title: "Fixture Song", artist: "Fixture Artist", album: "Fixture Album",
                                                                        artworkData: nil, appBundleIdentifier: "com.apple.Music", appPID: 43),
                                       isPlaying: true, elapsed: 0, duration: 180, rate: 1, sampledAt: .now, canSeek: false)
        suite.expect(NotchLyricsSupport.qqSearchURL(for: NotchMusicIdentity(otherPlayer)) == nil,
                     "non-QQ sources never send their songs to QQ Music")
        let lrc = "[00:01.00]Synthetic &amp; verse\n[00:05.25]Another &#x266A; verse\n[00:09.00]"
        let payload = encode(["code": 0, "lyric": lrc])
        let decoded = NotchLyricsSupport.decodeQQ(payload, for: track)
        suite.expect(decoded?.lines.map(\.text) == ["Synthetic & verse", "Another ♪ verse", ""]
                     && decoded?.lines.map(\.time) == [1, 5.25, 9],
                     "QQ lyrics retain timestamps and blank instrumental boundaries and decode HTML entities")
        suite.expect(NotchLyricsSupport.decodeQQ(encode(["code": 0, "lyric": Data(lrc.utf8).base64EncodedString()]), for: track) == decoded,
                     "base64 and plain QQ responses produce identical timed lyrics")
        for object: [String: Any] in [["code": 1, "lyric": lrc], ["code": 0, "lyric": "bad"],
                                      ["code": 0, "lyric": "[ti:Metadata only]"],
                                      ["code": 0, "lyric": String(repeating: "x", count: NotchLyricsSupport.maximumBytes + 1)]] {
            suite.expect(NotchLyricsSupport.decodeQQ(encode(object), for: track) == nil,
                         "QQ errors, malformed and oversized replies cannot become ready lyrics")
        }

        typealias Context = NotchLyricsContract
        Context.resetPresentation()
        Context.Preferences.enabled = true
        Context.Preferences.online = true
        Context.NotchLyricsDownload.requests = []
        defer {
            Context.Preferences.enabled = true; Context.Preferences.online = false
            Context.NotchLyricsDownload.requests = []; Context.resetPresentation()
        }
        let service = Context.LookupService()
        service.setCompactVisible(true, playback: playback)
        suite.expect(Context.NotchLyricsDownload.requests.count == 1
                     && Context.NotchLyricsDownload.requests.first?.url == search,
                     "a visible compact QQ strip starts the source-specific lookup without opening the reader")
        Context.NotchLyricsDownload.requests[0].completion(.payload(catalog([record])))
        Context.DispatchQueue.main.drain()
        suite.expect(Context.NotchLyricsDownload.requests.count == 2
                     && Context.NotchLyricsDownload.requests.last?.url == NotchLyricsSupport.qqLyricsURL(songMID: mid),
                     "the real service fetches lyrics only after matching a MID")
        let request = Context.NotchLyricsDownload.requests[1]
        service.update(playback: playback, visible: true)
        service.hide()
        suite.expect(!request.session.cancelled && service.visible && !service.pageVisible,
                     "closing the reader does not cancel a lookup needed by the compact strip")
        request.completion(.payload(payload)); Context.DispatchQueue.main.drain()
        suite.expect(service.state == .ready && service.syncedLyrics(for: playback) == decoded
                     && Context.NotchLyricsDownload.requests.count == 2,
                     "the production QQ pipeline provides synchronized lyrics in exactly two requests")
        service.setCompactVisible(true, playback: playback)
        suite.expect(Context.NotchLyricsDownload.requests.count == 2, "repeated presentation refreshes never refetch the song")
        var sought = playback; sought = NotchPlayback(track: sought.track, isPlaying: false, elapsed: 7, duration: 180,
                                                      rate: 0, sampledAt: .now, canSeek: false, itemIdentifier: sought.itemIdentifier)
        suite.expect(service.syncedLyrics(for: sought)?.activeIndex(at: sought.position(at: .now)) == 1,
                     "pause and seek retain this recording's lyrics and use observed playback position")
        var noPosition = sought; noPosition.hasPosition = false
        suite.expect(service.syncedLyrics(for: noPosition) == nil, "a player without position cannot show a timed compact verse")
        let next = NotchPlayback(track: RadialNowPlayingSnapshot(title: "Next", artist: "Fixture Artist", album: "Fixture Album",
                                                                artworkData: nil, appBundleIdentifier: "com.tencent.QQMusicMac", appPID: 42),
                                 isPlaying: true, elapsed: 0, duration: 180, rate: 1, sampledAt: .now, canSeek: false)
        service.playbackChanged(next)
        request.completion(.payload(payload)); Context.DispatchQueue.main.drain()
        suite.expect(service.lyrics == nil && service.syncedLyrics(for: playback) == nil,
                     "a late QQ result after a track change never displays the old song's verse")
        let nextRequest = Context.NotchLyricsDownload.requests.last!
        nextRequest.completion(.payload(catalog([]))); Context.DispatchQueue.main.drain()
        suite.expect(Context.NotchLyricsDownload.requests.last?.url.host == "lrclib.net",
                     "an unmatched QQ recording falls back to the existing catalog")
        let fallback = Context.NotchLyricsDownload.requests.last!
        service.setCompactVisible(false, playback: next)
        suite.expect(fallback.session.cancelled && !service.visible,
                     "hiding both lyric surfaces cancels every provider's pending work")
        fallback.completion(.payload(payload)); Context.DispatchQueue.main.drain()
        suite.expect(service.lyrics == nil, "a callback after hiding cannot restore obsolete lyrics")
        Context.NotchLyricsDownload.requests = []
        Context.Preferences.online = false
        let offline = Context.LookupService()
        offline.setCompactVisible(true, playback: playback)
        suite.expect(offline.state == .consent && Context.NotchLyricsDownload.requests.isEmpty,
                     "compact lyrics never enable online lookup or send metadata without consent")
        Context.Preferences.online = true
        offline.setCompactVisible(true, playback: playback)
        let onlineRequest = Context.NotchLyricsDownload.requests.last!
        Context.Preferences.online = false
        offline.setCompactVisible(true, playback: playback)
        onlineRequest.completion(.payload(catalog([record]))); Context.DispatchQueue.main.drain()
        suite.expect(onlineRequest.session.cancelled && offline.state == .consent
                     && Context.NotchLyricsDownload.requests.count == 1,
                     "revoking online lookup cancels QQ requests and prevents follow-up lyric downloads")
        Context.Preferences.enabled = false
        offline.setCompactVisible(true, playback: playback)
        suite.expect(!offline.compactVisible && offline.lyrics == nil && offline.track == nil,
                     "disabling lyrics releases both surfaces and their in-memory recording")
        let camera = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                   cameraWidth: 180, menuBarHeight: 24, compactSideRoom: 300)
        func verses(_ texts: [String]) -> NotchLyrics {
            let lines = texts.enumerated().map { NotchLyricLine(time: Double($0.offset * 4), text: $0.element) }
            return NotchLyrics(lines: lines, plain: texts.joined(separator: "\n"), instrumental: false)
        }
        let font = NotchMusicStripLayout.titleFont
        let short = verses(["\u{4E00}", "", "\u{4E00}\u{4E8C}"])
        suite.expect(NotchMusicStripLayout.lyricsWidth(short, font: font)
                     == NotchCapsuleLayout.width(NotchMusicStripLayout.shortestLyric, font: font),
                     "short verses still reserve room for a readable line")
        let typical = String(repeating: "\u{4E00}", count: 10)
        let song = verses(Array(repeating: typical, count: 6) + [String(repeating: "\u{4E00}", count: 40), "\u{4E00}"])
        suite.expect(NotchMusicStripLayout.lyricsWidth(song, font: font)
                     == (NotchCapsuleLayout.width(typical, font: font) * 1.25).rounded(.up),
                     "typical verses get 25 percent more room without letting one outlier size the whole song")
        let wings = NotchMusicStripLayout.lyricWings(song, geometry: camera.compactMusicGeometry, room: 300)
        suite.expect(wings != nil && wings!.leading <= NotchMusicStripLayout.maximumLyricWing
                     && wings!.trailing == camera.compactMusicGeometry.compactActivityWingWidth,
                     "compact lyrics reserve one steady left wing without moving the camera or right bars")
        let narrow = NotchMusicStripLayout.lyricWings(song, geometry: camera.compactMusicGeometry, room: 50)
        suite.expect(narrow == nil || narrow!.leading <= 50, "compact lyrics never extend over measured menu space")
        let timed = verses(["a", "b"])
        let gapped = NotchLyrics(lines: [
            NotchLyricLine(time: 0, text: ""),
            NotchLyricLine(time: 1, text: "Previous verse"),
            NotchLyricLine(time: 4, text: ""),
            NotchLyricLine(time: 8, text: "  \t"),
            NotchLyricLine(time: 25, text: "Next verse"),
            NotchLyricLine(time: 28, text: ""),
        ], plain: "", instrumental: false)
        suite.expect(gapped.compactIndex(at: 0) == nil,
                     "a blank intro cannot show a future verse")
        for position in stride(from: 1.0, to: 25, by: 0.25) {
            suite.expect(gapped.compactIndex(at: position) == 1,
                         "compact lyrics hold the previous verse throughout a long gap, including blank timestamps")
        }
        suite.expect(gapped.compactIndex(at: 25) == 4 && gapped.compactIndex(at: 179) == 4,
                     "only the next actual verse replaces compact text; a blank outro cannot hide it")
        suite.expect(gapped.compactIndex(at: 24, offset: 1) == 1
                     && gapped.compactIndex(at: 26, offset: 1) == 4
                     && gapped.compactIndex(at: 0) == nil && gapped.compactIndex(at: 5) == 1,
                     "timing adjustment and backward seeks recompute the held verse without stale UI state")
        suite.expect(gapped.activeIndex(at: 10) == 3,
                     "the expanded reader still recognizes blank instrumental timestamps")
        suite.expect(gapped.remaining(1, for: playback, offset: 0, at: playback.sampledAt) == 22,
                     "compact scrolling ends at the next words, not an intervening blank timestamp")
        let heldWidth = NotchMusicStripLayout.lyricWings(gapped, geometry: camera.compactMusicGeometry, room: 300)
        for position in [1.0, 4, 8, 15, 24.99, 25, 28, 179] {
            suite.expect(gapped.compactIndex(at: position) != nil
                         && NotchMusicStripLayout.lyricWings(gapped, geometry: camera.compactMusicGeometry, room: 300) == heldWidth,
                         "a compact lyric gap retains its content and song-wide surface width")
        }
        suite.expect(timed.remaining(0, for: playback, offset: 0, at: playback.sampledAt) == 1
                     && timed.remaining(1, for: playback, offset: 0, at: playback.sampledAt) == 177,
                     "a verse scrolls within the time before the next verse or the song's end")
        let paused = NotchPlayback(track: playback.track, isPlaying: false, elapsed: 3, duration: 180, rate: 1,
                                   sampledAt: .now, canSeek: false, itemIdentifier: "system-session-uuid")
        suite.expect(timed.remaining(0, for: paused, offset: 0, at: .now) == nil, "a paused verse does not scroll")
        let capsule = NotchGeometry(screen: camera.screen, safeAreaTop: 0, cameraWidth: 0,
                                    menuBarHeight: 24, compactSideRoom: 300, silhouette: .capsule)
        let lyricSize = NotchCapsuleLayout.musicLyricsSurface(song, geometry: capsule)
        suite.expect(lyricSize.height == capsule.stripHeight
                     && lyricSize.width >= NotchCapsuleLayout.musicSurface(title: nil, geometry: capsule).width
                     && lyricSize.width <= NotchCapsuleLayout.availableWidth(capsule),
                     "capsule lyrics retain a single row and respect the display's available width")
        let longSong = verses([String(repeating: "\u{4E00}", count: 60)])
        let wide = NotchMusicStripLayout.lyricWings(longSong, geometry: camera.compactMusicGeometry, room: 400)
        suite.expect(wide?.leading == 320, "long lyrics can use a wider wing without changing the hover title's 240 point cap")
        suite.expect(NotchCapsuleLayout.musicLyricsSurface(longSong, geometry: capsule).width
                     > NotchCapsuleLayout.musicSurface(title: longSong.lines[0].text, geometry: capsule).width,
                     "capsule lyrics have their own wider cap without changing normal song-title sizing")
    }
}
