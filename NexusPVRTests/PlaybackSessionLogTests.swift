//
//  PlaybackSessionLogTests.swift
//  NexusPVRTests
//
//  Playback sessions in the Event Log: line folding and cap, outcome,
//  filter, export and redaction.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct PlaybackSessionLogTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func line(_ text: String, _ level: PlaybackLogLevel = .info, at offset: TimeInterval = 0) -> PlaybackLogLine {
        PlaybackLogLine(timestamp: t0.addingTimeInterval(offset), level: level, text: text)
    }

    private func request(success: Bool) -> NetworkEvent {
        NetworkEvent(
            timestamp: t0, method: "GET", path: "/api/channels", statusCode: success ? 200 : 500,
            isSuccess: success, durationMs: 5, responseSize: 0, errorDetail: nil
        )
    }

    // MARK: - PlaybackSession

    @Test("Identical consecutive lines fold into one with a repeat count")
    func foldsRepeats() {
        var session = PlaybackSession(id: UUID(), startedAt: t0, title: "/live")
        session.append(line("same", .warn))
        session.append(line("same", .warn))
        session.append(line("other"))
        #expect(session.lines.count == 2)
        #expect(session.lines[0].repeatCount == 2)
        #expect(session.warningCount == 2)
    }

    @Test("Past the cap the head is kept and lines after it are dropped")
    func capKeepsHeadAndTail() {
        var session = PlaybackSession(id: UUID(), startedAt: t0, title: "/live")
        let total = PlaybackSession.maxLineCount + 10
        for i in 0..<total { session.append(line("line \(i)")) }
        #expect(session.lines.count == PlaybackSession.maxLineCount)
        #expect(session.omittedLineCount == 10)
        #expect(session.lines.first?.text == "line 0")
        #expect(session.lines[PlaybackSession.headLineCount - 1].text == "line \(PlaybackSession.headLineCount - 1)")
        #expect(session.lines[PlaybackSession.headLineCount].text == "line \(PlaybackSession.headLineCount + 10)")
        #expect(session.lines.last?.text == "line \(total - 1)")
        #expect(session.omissionIndex == PlaybackSession.headLineCount)
    }

    @Test("Errors count even when the cap drops their lines, and make a problem")
    func errorsMakeProblem() {
        var session = PlaybackSession(id: UUID(), startedAt: t0, title: "/live")
        #expect(!session.hasProblems)
        session.append(line("boom", .error))
        #expect(session.errorCount == 1)
        #expect(session.hasProblems)
    }

    @Test("A failure stays the outcome when the player is closed afterwards")
    func failureSticks() {
        var session = PlaybackSession(id: UUID(), startedAt: t0, title: "/live")
        session.finish(.failed("loading failed"), at: t0.addingTimeInterval(2))
        session.finish(.ended("Closed"), at: t0.addingTimeInterval(9))
        #expect(session.outcome == .failed("loading failed"))
        #expect(session.duration() == 2)
    }

    @Test("A normal close ends the session")
    func normalClose() {
        var session = PlaybackSession(id: UUID(), startedAt: t0, title: "/live")
        session.finish(.ended("Closed"), at: t0.addingTimeInterval(30))
        #expect(session.outcome == .ended("Closed"))
        #expect(!session.hasProblems)
        #expect(session.duration(now: t0.addingTimeInterval(999)) == 30)
    }

    @Test("mpv level strings map to log levels")
    func levels() {
        #expect(PlaybackLogLevel(mpvLevel: "v") == .verbose)
        #expect(PlaybackLogLevel(mpvLevel: "fatal").isProblem)
        #expect(!PlaybackLogLevel(mpvLevel: "warn").isProblem)
        #expect(PlaybackLogLevel(mpvLevel: "nonsense") == .info)
    }

    // MARK: - NetworkEventLog

    @Test("Starting a session adds one PLAY row linked to it")
    func startAddsRow() {
        let log = NetworkEventLog()
        let id = UUID()
        log.apply(PlaybackSessionUpdate(sessionId: id, timestamp: t0, kind: .start(title: "/proxy/ts/stream/abc", host: "tv:9191")))
        log.apply(PlaybackSessionUpdate(sessionId: id, timestamp: t0, kind: .start(title: "dup", host: nil)))
        log.apply(PlaybackSessionUpdate(sessionId: id, timestamp: t0, kind: .line(.info, "hello")))
        log.apply(PlaybackSessionUpdate(sessionId: id, timestamp: t0, kind: .end(.failed("x"))))
        #expect(log.events.count == 1)
        #expect(log.events[0].sessionId == id)
        #expect(log.events[0].path == "/proxy/ts/stream/abc")
        #expect(log.sessions[id]?.lines.map(\.text) == ["hello"])
        #expect(log.sessions[id]?.outcome == .failed("x"))
    }

    @Test("Lines for an unknown or cleared session are ignored")
    func clearedSessionIgnoresLines() {
        let log = NetworkEventLog()
        let id = UUID()
        log.apply(PlaybackSessionUpdate(sessionId: id, timestamp: t0, kind: .start(title: "/live", host: nil)))
        log.clear()
        log.apply(PlaybackSessionUpdate(sessionId: id, timestamp: t0, kind: .line(.error, "late")))
        #expect(log.events.isEmpty)
        #expect(log.sessions.isEmpty)
    }

    @Test("Sessions whose rows fall off the capped log are dropped too")
    func cappingDropsSessions() async throws {
        let log = NetworkEventLog()
        let id = UUID()
        log.apply(PlaybackSessionUpdate(sessionId: id, timestamp: t0, kind: .start(title: "/live", host: nil)))
        for _ in 0..<200 { log.log(request(success: true)) }
        for _ in 0..<50 where log.events.count < 200 || log.sessions[id] != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(log.events.count == 200)
        #expect(log.sessions[id] == nil)
    }

    // MARK: - Filter

    @Test("Problems shows failed requests and sessions with problems only")
    func problemsFilter() {
        let ok = request(success: true)
        let failed = request(success: false)
        var playback = NetworkEvent(timestamp: t0, method: "PLAY", path: "/live", statusCode: nil,
                                    isSuccess: true, durationMs: 0, responseSize: 0, errorDetail: nil)
        playback.sessionId = UUID()
        var clean = PlaybackSession(id: playback.sessionId!, startedAt: t0, title: "/live")
        var broken = clean
        broken.append(line("bad", .error))

        #expect(!EventLogFilter.problems.includes(ok, session: nil))
        #expect(EventLogFilter.problems.includes(failed, session: nil))
        #expect(!EventLogFilter.problems.includes(playback, session: clean))
        #expect(EventLogFilter.problems.includes(playback, session: broken))
        #expect(EventLogFilter.playback.includes(playback, session: clean))
        #expect(!EventLogFilter.playback.includes(failed, session: nil))
        #expect(EventLogFilter.all.includes(ok, session: nil))
        clean.append(line("fine"))
        #expect(!EventLogFilter.problems.includes(playback, session: clean))
    }

    // MARK: - Export

    @Test("Export lists requests and each session's full log, redacted")
    func exportIncludesSessions() {
        let id = UUID()
        var session = PlaybackSession(id: id, startedAt: t0, title: "/live?client=abc123", host: "tv:8866")
        session.append(line("Opening http://tv:8866/live?channel=5&sid=SECRET", .event))
        session.append(line("Failed to open", .error))
        session.append(line("Failed to open", .error))
        var row = NetworkEvent(timestamp: t0, method: "PLAY", path: session.title, statusCode: nil,
                               isSuccess: true, durationMs: 0, responseSize: 0, errorDetail: nil)
        row.sessionId = id

        let text = EventLogExporter.text(
            events: [request(success: false), row],
            sessions: [id: session],
            header: ["Header line"],
            now: t0.addingTimeInterval(5)
        )
        #expect(text.hasPrefix("Header line\n"))
        #expect(text.contains("GET /api/channels → 500"))
        #expect(text.contains("=== Playback [tv:8866]"))
        #expect(text.contains("[ERROR] Failed to open (×2)"))
        #expect(text.contains("2 error(s)"))
        #expect(!text.contains("SECRET"))
        #expect(text.contains("channel=5"))
    }

    @Test("Export marks where lines were omitted")
    func exportOmissionMarker() {
        var session = PlaybackSession(id: UUID(), startedAt: t0, title: "/live")
        for i in 0..<(PlaybackSession.maxLineCount + 3) { session.append(line("l\(i)")) }
        let text = EventLogExporter.text(session: session, header: [])
        #expect(text.contains("… 3 line(s) omitted …"))
    }

    @Test("Durations read as seconds, minutes or hours")
    func durations() {
        #expect(EventLogExporter.formatDuration(4.4) == "4s")
        #expect(EventLogExporter.formatDuration(125) == "2m 5s")
        #expect(EventLogExporter.formatDuration(7_260) == "2h 1m")
    }

    @Test("Shared file name has no spaces")
    func fileName() {
        let name = EventLogExporter.fileName(now: t0)
        #expect(name.hasSuffix(".txt"))
        #expect(!name.contains(" "))
    }

    // MARK: - mpv lines

    @Test("Option echoes that carry the Authorization header stay out of the session")
    func mpvLineFilter() {
        #expect(!MPVPlayerCore.belongsInPlaybackLog("Set property: http-header-fields=Authorization: Bearer x"))
        #expect(!MPVPlayerCore.belongsInPlaybackLog("Option http-header-fields: Authorization: Bearer x"))
        #expect(!MPVPlayerCore.belongsInPlaybackLog(""))
        #expect(MPVPlayerCore.belongsInPlaybackLog("AO: [avfoundation] 48000Hz stereo 2ch floatp"))
    }
}
