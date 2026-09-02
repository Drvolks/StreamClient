//
//  PacketTimeline.swift
//  NexusPVR
//
//  Normalises one stream's packet timestamps while remuxing.
//

import Foundation

/// Rewrites the timestamps of one stream's packets so a muxer will accept
/// them, and so the result measures the programme rather than the source's
/// clock.
///
/// A broadcast recording is not the tidy sequence a synthetic test file is:
///   - its clock starts wherever the mux's clock happened to be (40000 s in,
///     say), so timestamps have to be rebased or the file claims to start
///     eleven hours in;
///   - it contains discontinuities — the timestamps jump backwards or leap
///     forward at ad breaks, splices and PCR wraps — which, taken at face
///     value, both break the muxer's requirement that decode timestamps
///     increase and turn a 40-minute programme into a 65,000-second one;
///   - some packets arrive with no timestamp at all, which the MP4 muxer
///     rejects outright.
///
/// Everything here is in one stream's own tick units; the caller rescales to
/// the output time base afterwards.
nonisolated struct PacketTimeline {

    /// A forward jump larger than this is a break in the source's clock rather
    /// than ordinary progress. Generous enough to survive a sparse subtitle or
    /// audio stream, small enough to catch a real splice.
    static let discontinuityThresholdSeconds: Double = 10

    /// What to write for one packet, in the input stream's tick units.
    struct Timestamps: Equatable {
        var pts: Int64
        var dts: Int64
    }

    private let secondsPerTick: Double
    /// Subtracted from incoming timestamps. Seeded from the first timestamp
    /// seen anywhere in the file so every stream shifts by the same amount and
    /// audio stays in sync with video; re-anchored on a discontinuity.
    private var offset: Int64
    private var lastInputDts: Int64?
    private var lastOutputDts: Int64?

    /// - Parameters:
    ///   - secondsPerTick: this stream's time base as a `Double`.
    ///   - anchor: the first timestamp seen in the file, in this stream's ticks.
    init(secondsPerTick: Double, anchor: Int64) {
        self.secondsPerTick = secondsPerTick
        self.offset = anchor
    }

    /// Final guard, applied *after* rescaling into the output time base.
    ///
    /// The in-timeline guard works in the source's ticks, which isn't enough:
    /// rescaling 90 kHz audio timestamps into a 48 kHz output collapses
    /// adjacent ticks onto the same value, and a muxer rejects a packet whose
    /// decode timestamp doesn't advance ("Invalid argument"). This is the one
    /// that has to hold, because it speaks the muxer's units.
    static func enforcingIncrease(pts: Int64, dts: Int64, after lastDts: Int64?) -> Timestamps {
        var dts = dts
        if let lastDts, dts <= lastDts {
            dts = lastDts + 1
        }
        return Timestamps(pts: max(pts, dts), dts: dts)
    }

    /// Normalises one packet, or returns `nil` if it can't be placed and should
    /// be dropped (only possible before any packet has been written).
    ///
    /// - Parameters:
    ///   - pts / dts: the packet's timestamps, `nil` when absent.
    ///   - duration: the packet's duration in ticks, used to synthesise a
    ///     timestamp for a packet that has none.
    mutating func normalize(pts: Int64?, dts: Int64?, duration: Int64) -> Timestamps? {
        guard let reference = dts ?? pts else {
            // No timestamp at all. Once something has been written we can carry
            // on from there; before that there's nothing to anchor to.
            guard let lastOutputDts else { return nil }
            let synthesized = lastOutputDts + max(1, duration)
            lastInputDts = nil
            self.lastOutputDts = synthesized
            return Timestamps(pts: synthesized, dts: synthesized)
        }

        if let lastInputDts {
            let delta = Double(reference - lastInputDts) * secondsPerTick
            if delta < 0 || delta > Self.discontinuityThresholdSeconds {
                // The source's clock broke. Re-anchor so output time carries on
                // from where it was: the gap is closed rather than recorded.
                let resumeAt = (lastOutputDts ?? 0) + 1
                offset = reference - resumeAt
            }
        }

        var outputDts = reference - offset
        // `pts >= dts` always holds per packet, so shifting both by the same
        // offset keeps the relationship intact.
        var outputPts = (pts ?? reference) - offset

        if let lastOutputDts, outputDts <= lastOutputDts {
            // Strictly increasing is what the muxer demands; a tick is the
            // smallest lie that satisfies it.
            outputDts = lastOutputDts + 1
        }
        outputPts = max(outputPts, outputDts)

        lastInputDts = reference
        lastOutputDts = outputDts
        return Timestamps(pts: outputPts, dts: outputDts)
    }
}
