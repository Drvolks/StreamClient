//
//  CatchupContinuation.swift
//  nextpvr-apple-client
//
//  Pure decision math for keeping catch-up playback going past the live edge
//  that existed when the session was minted (issue #150).
//

import Foundation

/// A catch-up session's archive is cut at the live edge as it stood when the
/// session was minted: `POST /api/catchup/sessions/` fixes `start`, and the
/// upstream URL it builds carries the duration `now - start` baked in. For a
/// programme that is still airing that edge is not the end of the show, so
/// playback used to end roughly `now - start` seconds in (#150).
///
/// The fix is to mint a fresh session at the point playback reached and reload,
/// which is what this enum decides. Each continuation covers exactly the wall
/// clock that elapsed while the previous one played, so the viewer keeps a
/// constant distance behind live and no interval is skipped.
nonisolated enum CatchupContinuation {
    /// Minting a session whose archive is only a few seconds long buys one
    /// reload's worth of buffering for almost no content, so hold off until at
    /// least this much unplayed programme has aired.
    static let minimumLeadSeconds: Double = 20

    /// A continuation that plays less than this before hitting EOF again hasn't
    /// really advanced — count it towards giving up rather than looping.
    static let minimumSessionProgressSeconds: Double = 3

    /// How many consecutive short sessions to tolerate before letting playback
    /// end normally. Guards against an EOF that isn't the archive edge at all
    /// (a dead upstream, say) turning into an endless remint loop.
    static let maxConsecutiveShortSessions = 3

    enum Decision: Equatable {
        /// The whole programme has been played — let playback end.
        case finished
        /// Mint a new session starting at this wall-clock instant.
        case resume(start: Date)
        /// Too little new programme has aired; re-decide after this delay.
        case wait(seconds: Double)
    }

    /// - Parameters:
    ///   - programStart: the programme's scheduled start, i.e. the `start` of
    ///     the very first session in the chain.
    ///   - programEnd: the programme's scheduled end.
    ///   - playedSeconds: seconds of the programme played so far, summed across
    ///     every session in the chain.
    ///   - now: current wall clock.
    static func decide(
        programStart: Date,
        programEnd: Date,
        playedSeconds: Double,
        now: Date = Date()
    ) -> Decision {
        // Playback reached this instant of the broadcast, so it is where the
        // next session has to pick up.
        let resumeStart = programStart.addingTimeInterval(max(0, playedSeconds))
        // Past programmes end up here too: their archive runs well beyond the
        // programme, so by the time it EOFs `resumeStart` is past `programEnd`
        // and playback ends exactly as it did before (#150 acceptance).
        guard resumeStart < programEnd else { return .finished }

        let lead = now.timeIntervalSince(resumeStart)
        guard lead >= minimumLeadSeconds else {
            return .wait(seconds: minimumLeadSeconds - lead)
        }
        return .resume(start: resumeStart)
    }

    /// Whether the continuation chain has stopped making progress and should be
    /// abandoned.
    static func shouldGiveUp(consecutiveShortSessions: Int) -> Bool {
        consecutiveShortSessions >= maxConsecutiveShortSessions
    }

    /// Whether a session that played `seconds` before EOF counts as progress.
    static func isShortSession(playedSeconds: Double) -> Bool {
        playedSeconds < minimumSessionProgressSeconds
    }
}
