//
//  StalledRecordingRecovery.swift
//  nextpvr-apple-client
//
//  When to reopen an in-progress recording that has stalled at the write edge
//  (issue #127).
//

import Foundation

/// Fast-forwarding an in-progress recording can park playback right on the
/// server's write edge. The demuxer runs with `stream-lavf-growing-file` and
/// `demuxer-force-retry-eof`, so instead of ending it retries the read forever:
/// playback rebuffers, briefly resumes, hits the edge again, and never settles.
/// The 15s margin baked into the reported duration is meant to keep seeks short
/// of the edge, but it's derived from a bitrate-extrapolated size estimate, so it
/// can't be relied on to be accurate enough on its own.
///
/// The recovery is what a user does by hand today — reopen the stream a bit
/// behind the edge — done automatically.
nonisolated enum StalledRecordingRecovery {
    /// How long playback must sit at one position before it counts as stalled
    /// rather than briefly rebuffering.
    static let stallThreshold: TimeInterval = 2

    /// A reopen costs several seconds (reconnect, seek, decoder init), so
    /// retrying sooner than this just builds a reload loop.
    static let reloadCooldown: TimeInterval = 20

    /// How far behind the known edge to reopen, so there is decodable content at
    /// the target instead of another EOF.
    static let edgeBackoff: Double = 30

    /// Two reopens closer together than this would land on the same content — a
    /// sign the reopen isn't helping, so stop rather than loop.
    static let minimumRepeatDistance: Double = 5

    /// Whether a stall at `position` should trigger a reopen.
    ///
    /// - Parameters:
    ///   - position: current playback position, seconds.
    ///   - knownEnd: best estimate of how much has been recorded, seconds.
    ///   - stalledFor: how long the position has not advanced.
    ///   - sinceLastReload: time since the last reopen.
    ///   - lastReloadTarget: where the last reopen aimed, or nil if there wasn't one.
    static func shouldReload(
        position: Double,
        knownEnd: Double,
        stalledFor: TimeInterval,
        sinceLastReload: TimeInterval,
        lastReloadTarget: Double?
    ) -> Bool {
        // Startup isn't a stall, and there's nothing to recover to unless the
        // server is known to have content ahead of us.
        guard position > 10, knownEnd > position + 5 else { return false }
        guard stalledFor >= stallThreshold else { return false }
        guard sinceLastReload >= reloadCooldown else { return false }
        if let lastReloadTarget,
           abs(reloadTarget(position: position, knownEnd: knownEnd) - lastReloadTarget) < minimumRepeatDistance {
            return false
        }
        return true
    }

    /// Where to reopen: back off from the edge, but never seek forward past where
    /// the viewer already is.
    static func reloadTarget(position: Double, knownEnd: Double) -> Double {
        guard knownEnd > edgeBackoff else { return max(0, position) }
        return max(0, min(position, knownEnd - edgeBackoff))
    }
}
