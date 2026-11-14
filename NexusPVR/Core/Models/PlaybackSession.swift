//
//  PlaybackSession.swift
//  PVR Client
//
//  Everything one player instance logged, shown as a single Event Log row.
//

import Foundation

/// The log of one player lifetime: from the first URL mpv is asked to open
/// until the player is closed. Shown as one row in the Event Log; selecting
/// it shows the lines below.
///
/// Holds at most `maxLineCount` lines. The first `headLineCount` (how the
/// stream opened) are always kept; past the cap the oldest line after them
/// is dropped, so the log keeps both the start and the latest lines.
nonisolated struct PlaybackSession: Identifiable, Sendable, Equatable {
    static let maxLineCount = 600
    static let headLineCount = 150
    /// Longer lines (an mpv dump, a huge URL) are cut to this many characters.
    static let maxLineLength = 2_000

    let id: UUID
    let startedAt: Date
    var title: String
    var host: String?
    private(set) var endedAt: Date?
    private(set) var outcome: PlaybackSessionOutcome = .inProgress
    private(set) var lines: [PlaybackLogLine] = []
    /// Lines dropped from after the first `headLineCount` to respect the cap.
    private(set) var omittedLineCount = 0
    /// Fatal and error lines, including ones dropped by the cap.
    private(set) var errorCount = 0
    /// Warning lines, including ones dropped by the cap.
    private(set) var warningCount = 0

    init(id: UUID, startedAt: Date, title: String, host: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.title = title
        self.host = host
    }

    var hasProblems: Bool {
        errorCount > 0 || outcome.isFailure
    }

    /// Where the "lines omitted" marker goes in `lines`, when lines were
    /// dropped; equal to `lines.count` when the marker goes after the last line.
    var omissionIndex: Int? {
        omittedLineCount > 0 ? min(Self.headLineCount, lines.count) : nil
    }

    /// Seconds from start to end, or to `now` while still in progress.
    func duration(now: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    mutating func append(_ line: PlaybackLogLine) {
        var line = line
        if line.text.count > Self.maxLineLength {
            line = PlaybackLogLine(
                id: line.id,
                timestamp: line.timestamp,
                level: line.level,
                text: String(line.text.prefix(Self.maxLineLength)) + " … (truncated)",
                repeatCount: line.repeatCount
            )
        }
        if line.level.isProblem { errorCount += 1 }
        if line.level == .warn { warningCount += 1 }

        if let last = lines.indices.last,
           lines[last].level == line.level,
           lines[last].text == line.text {
            lines[last].repeatCount += 1
            return
        }
        if lines.count >= Self.maxLineCount {
            lines.remove(at: Self.headLineCount)
            omittedLineCount += 1
        }
        lines.append(line)
    }

    /// Drops every line after the first `keeping`, to keep the whole Event
    /// Log under its line budget. Counts and the outcome stay. Returns how
    /// many lines were dropped.
    @discardableResult
    mutating func discardLines(keeping: Int = 0) -> Int {
        let keep = max(0, min(keeping, lines.count))
        let dropped = lines.count - keep
        guard dropped > 0 else { return 0 }
        lines.removeSubrange(keep...)
        omittedLineCount += dropped
        return dropped
    }

    /// Records the end. An earlier failure stays the outcome when the player
    /// is closed afterwards; only the first end time is kept.
    mutating func finish(_ outcome: PlaybackSessionOutcome, at date: Date) {
        if endedAt == nil { endedAt = date }
        guard !self.outcome.isFailure else { return }
        self.outcome = outcome
    }
}
