//
//  NetworkEventLog.swift
//  DispatcherPVR
//
//  Observable event log for HTTP requests to the Dispatcharr backend
//

import Foundation
import Combine

struct NetworkEvent: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int?
    let isSuccess: Bool
    let durationMs: Int
    let responseSize: Int
    let errorDetail: String?
    /// Host the request or stream went to, with a non-default port when one
    /// was used (e.g. "pvr.example.com" or "192.168.1.50:8866"). Tells the
    /// server address and the custom host apart in the log (#165).
    var host: String? = nil
    /// Set on the row that stands for a playback session; the session itself
    /// is in `NetworkEventLog.sessions`.
    var sessionId: UUID? = nil

    /// "host" or "host:port" for `url`; nil when it has no host.
    nonisolated static func hostLabel(for url: URL?) -> String? {
        guard let url, let host = url.host, !host.isEmpty else { return nil }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}

/// Protocol for logging network events — allows test doubles and alternative implementations.
protocol NetworkEventLogging: AnyObject, Sendable {
    nonisolated func log(_ event: NetworkEvent)
    /// Starts, adds to, or ends a playback session. Callable from any thread;
    /// updates are applied in the order they are sent.
    nonisolated func logPlayback(_ update: PlaybackSessionUpdate)
}

extension NetworkEventLogging {
    nonisolated func logPlayback(_ update: PlaybackSessionUpdate) {}
}

/// Concrete observable implementation for network event logging.
@MainActor
final class NetworkEventLog: ObservableObject, NetworkEventLogging {
    @Published private(set) var events: [NetworkEvent] = []
    /// Playback sessions by id, one per `sessionId` row in `events`. Not
    /// published: mpv can log several lines a second, and the Event Log
    /// reads a snapshot when it opens rather than following every line.
    private(set) var sessions: [UUID: PlaybackSession] = [:]
    private let maxEvents = 200
    /// Lines kept across all playback sessions. Each session holds at most
    /// `PlaybackSession.maxLineCount`; past this total the oldest sessions
    /// lose their logs (their rows, counts and outcome stay).
    static let maxPlaybackLines = 5_000
    private(set) var playbackLineCount = 0

    nonisolated init() {}

    nonisolated func log(_ event: NetworkEvent) {
        Task { @MainActor in
            self.append(event)
            #if DEBUG
            if Self.printsToConsole(event) {
                print(Self.consoleLine(for: event))
            }
            #endif
        }
    }

    /// Playback updates come from mpv's event thread; the main queue keeps
    /// them in order, so a session never receives a line before its start.
    nonisolated func logPlayback(_ update: PlaybackSessionUpdate) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.apply(update)
            }
        }
    }

    func apply(_ update: PlaybackSessionUpdate) {
        let id = update.sessionId
        switch update.kind {
        case .start(let title, let host):
            guard sessions[id] == nil else { return }
            sessions[id] = PlaybackSession(id: id, startedAt: update.timestamp, title: title, host: host)
            append(NetworkEvent(
                timestamp: update.timestamp,
                method: "PLAY",
                path: title,
                statusCode: nil,
                isSuccess: true,
                durationMs: 0,
                responseSize: 0,
                errorDetail: nil,
                host: host,
                sessionId: id
            ))
        case .line(let level, let text):
            guard let before = sessions[id]?.lines.count else { return }
            sessions[id]?.append(PlaybackLogLine(timestamp: update.timestamp, level: level, text: text))
            playbackLineCount += (sessions[id]?.lines.count ?? before) - before
            enforcePlaybackLineBudget(sparing: id)
            #if DEBUG
            if level.isProblem { print("PLAYBACK [\(level.tag)] \(text)") }
            #endif
        case .end(let outcome):
            sessions[id]?.finish(outcome, at: update.timestamp)
        }
    }

    /// Empties the oldest sessions' logs until the total is back under
    /// `maxPlaybackLines`. The session being written is trimmed last, and
    /// then only past its first lines.
    private func enforcePlaybackLineBudget(sparing current: UUID) {
        guard playbackLineCount > Self.maxPlaybackLines else { return }
        let oldestFirst = events.compactMap(\.sessionId).filter { $0 != current }
        for id in oldestFirst where playbackLineCount > Self.maxPlaybackLines {
            playbackLineCount -= sessions[id]?.discardLines() ?? 0
        }
        if playbackLineCount > Self.maxPlaybackLines, let lines = sessions[current]?.lines.count {
            let keep = max(0, lines - (playbackLineCount - Self.maxPlaybackLines))
            playbackLineCount -= sessions[current]?.discardLines(keeping: keep) ?? 0
        }
    }

    private func append(_ event: NetworkEvent) {
        events.append(event)
        if events.count > maxEvents {
            let dropped = events.prefix(events.count - maxEvents)
            events.removeFirst(events.count - maxEvents)
            for id in dropped.compactMap(\.sessionId) {
                playbackLineCount -= sessions[id]?.lines.count ?? 0
                sessions[id] = nil
            }
        }
    }

    func clear() {
        events.removeAll()
        sessions.removeAll()
        playbackLineCount = 0
    }

    /// The whole log as shareable text (header, events, full sessions).
    func exportText() -> String {
        EventLogExporter.text(events: events, sessions: sessions)
    }

    /// Only failures go to the console (debug builds). Requests that
    /// succeed, and the "request started" notes, would drown them out; the
    /// in-app Event Log still keeps every event.
    nonisolated static func printsToConsole(_ event: NetworkEvent) -> Bool {
        !event.isSuccess
    }

    nonisolated private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var formattedLog: String {
        events.map { event in
            Self.consoleLine(for: event)
        }.joined(separator: "\n")
    }

    nonisolated static func consoleLine(for event: NetworkEvent) -> String {
        let time = timeFormatter.string(from: event.timestamp)
        let status = event.statusCode.map { " → \($0)" } ?? (event.isSuccess ? "" : " → ERR")
        let duration = event.durationMs > 0 ? " (\(event.durationMs)ms)" : ""
        let host = event.host.map { " [\($0)]" } ?? ""
        var line = "\(time) \(event.method)\(host) \(event.path)\(status)\(duration)"
        if let detail = event.errorDetail {
            line += "\n  \(detail)"
        }
        return line
    }
}
