//
//  EventLogExporter.swift
//  PVR Client
//
//  Plain-text form of the Event Log and of playback sessions, for sharing.
//

import Foundation

/// Builds the text that is shared or copied: a header with app and device
/// facts, then the events oldest first, each playback session followed by
/// its full log. Everything passes through `LogRedactor`.
nonisolated enum EventLogExporter {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func text(
        events: [NetworkEvent],
        sessions: [UUID: PlaybackSession],
        header: [String] = DiagnosticsInfo.headerLines(),
        now: Date = Date()
    ) -> String {
        var out = header
        out.append("")
        if events.isEmpty {
            out.append("No events recorded.")
        }
        for event in events {
            if let id = event.sessionId, let session = sessions[id] {
                out.append("")
                out.append(contentsOf: sessionBlock(session, now: now))
                out.append("")
            } else {
                out.append(NetworkEventLog.consoleLine(for: event))
            }
        }
        return LogRedactor.redact(out.joined(separator: "\n")) + "\n"
    }

    static func text(
        session: PlaybackSession,
        header: [String] = DiagnosticsInfo.headerLines(),
        now: Date = Date()
    ) -> String {
        let out = header + [""] + sessionBlock(session, now: now)
        return LogRedactor.redact(out.joined(separator: "\n")) + "\n"
    }

    /// Summary line, then one line per log line, with the omission marker.
    static func sessionBlock(_ session: PlaybackSession, now: Date = Date()) -> [String] {
        var out: [String] = []
        let host = session.host.map { " [\($0)]" } ?? ""
        out.append("=== Playback\(host) \(session.title)")
        out.append("    Started \(timeFormatter.string(from: session.startedAt)), "
                   + "\(formatDuration(session.duration(now: now))), "
                   + "\(session.outcome.summary), "
                   + "\(session.errorCount) error(s), \(session.warningCount) warning(s)")
        for (index, line) in session.lines.enumerated() {
            if index == session.omissionIndex {
                out.append("    … \(session.omittedLineCount) line(s) omitted …")
            }
            out.append("    " + lineText(line))
        }
        out.append("=== End of playback")
        return out
    }

    static func lineText(_ line: PlaybackLogLine) -> String {
        let repeats = line.repeatCount > 1 ? " (×\(line.repeatCount))" : ""
        return "\(timeFormatter.string(from: line.timestamp)) [\(line.level.tag)] \(line.text)\(repeats)"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// File name for a shared log, e.g. "StreamClient-Log-2026-11-14-1137.txt".
    static func fileName(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let app = String(Brand.appName.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII
        }.map(Character.init))
        return "\(app)-Log-\(f.string(from: now)).txt"
    }
}
