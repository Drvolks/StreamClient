//
//  CatchupAvailability.swift
//  nextpvr-apple-client
//
//  Pure gating math for whether a given program can be played back via
//  Dispatcharr catch-up (#119), factored out of the Guide so it can be
//  exercised without EPGCache/GuideViewModel plumbing.
//

import Foundation

nonisolated enum CatchupAvailability {
    /// Whether `program` can be requested via `DispatcherClient.startCatchupSession`.
    ///
    /// Mirrors the server-side checks in `CatchupSessionCreateAPIView`
    /// (issue #119's pinned comment, §1): the channel must be catch-up
    /// capable, the program must already have aired, and its start must
    /// fall within the channel's rolling `catchup_days` archive window.
    /// The server is still the source of truth — a `true` here is a UI
    /// hint (show the badge / enable the button), not a guarantee the
    /// mint call will succeed, since the archive window is measured from
    /// `now` on the server rather than pinned at EPG-load time.
    static func isAvailable(
        program: Program,
        channelIsCatchup: Bool,
        catchupDays: Int,
        now: Date = Date()
    ) -> Bool {
        guard channelIsCatchup, catchupDays > 0 else { return false }
        // Only aired programs have an archive to fetch.
        guard program.endDate <= now else { return false }
        guard let earliestStart = Calendar.current.date(byAdding: .day, value: -catchupDays, to: now) else {
            return false
        }
        return program.startDate >= earliestStart
    }

    /// Whether a **currently airing** `program` can be restarted from its
    /// scheduled start via catch-up (#143).
    ///
    /// Same channel/window gating as `isAvailable`, but for the live case:
    /// the program must have started and not yet ended. The archive segment
    /// for the already-aired portion is what the mint call asks for, so the
    /// start still has to fall inside the rolling `catchup_days` window.
    /// As with `isAvailable`, the server remains the source of truth.
    static func isAvailableFromStart(
        program: Program,
        channelIsCatchup: Bool,
        catchupDays: Int,
        now: Date = Date()
    ) -> Bool {
        guard channelIsCatchup, catchupDays > 0 else { return false }
        // Only the live window — ended programs go through `isAvailable`.
        guard program.startDate <= now, now < program.endDate else { return false }
        guard let earliestStart = Calendar.current.date(byAdding: .day, value: -catchupDays, to: now) else {
            return false
        }
        return program.startDate >= earliestStart
    }

    /// Filters a channel's cached EPG down to playable archive entries and
    /// orders the list newest-first for the channel catch-up browser.
    static func availablePrograms(
        from programs: [Program],
        channelIsCatchup: Bool,
        catchupDays: Int,
        now: Date = Date()
    ) -> [Program] {
        programs
            .filter {
                isAvailable(
                    program: $0,
                    channelIsCatchup: channelIsCatchup,
                    catchupDays: catchupDays,
                    now: now
                )
            }
            .sorted { $0.startDate > $1.startDate }
    }
}
