//
//  LiveStreamKeepalive.swift
//  PVR Client
//
//  Single owner of the server-side live stream renewal loop (issues #120, #133).
//

import Foundation

/// Owns the one renewal loop that keeps a server-side live stream alive.
///
/// The loop can't live in `PlayerView`'s `@State`: entering native PiP dismisses
/// the player, so SwiftUI destroys the view while mpv keeps feeding the PiP
/// window. A view-owned `Task` is then neither cancellable nor reachable — it
/// leaked, and restoring from PiP started a second loop alongside it (#133).
///
/// Keyed by the stream URL, so re-entering the player for the same live stream
/// (the PiP restore path) adopts the running loop, while switching channels
/// replaces it.
@MainActor
final class LiveStreamKeepalive {
    /// Renewal cadence. Well under NextPVR's ~15s expiry so one slow or failed
    /// renewal can't lose the stream.
    static let interval: Duration = .seconds(5)

    private var task: Task<Void, Never>?
    private var streamKey: URL?
    private var onInfo: (@MainActor (LiveStreamInfo, Date) -> Void)?

    /// Latest buffer state, replayed to a view that adopts a running loop so the
    /// live edge doesn't reset to zero across a PiP restore.
    private(set) var latestInfo: LiveStreamInfo?
    private(set) var latestInfoAt: Date = .distantPast

    /// Number of loops actually created — stays put when a start call adopts the
    /// running loop. Asserted by the tests that guard "exactly one renewal loop".
    private(set) var startCount = 0

    var isRunning: Bool { task != nil }

    /// Stream the running loop is renewing, if any.
    var activeStreamKey: URL? { task == nil ? nil : streamKey }

    init() {}

    func isRunning(for key: URL) -> Bool { task != nil && streamKey == key }

    /// Starts renewing `key`, or adopts the loop already renewing it.
    ///
    /// `onInfo` always becomes the current observer, so the view recreated after a
    /// PiP restore receives buffer state even though it did not start the loop.
    func start(
        streamKey key: URL,
        renew: @MainActor @escaping () async -> LiveStreamInfo?,
        onInfo: @MainActor @escaping (LiveStreamInfo, Date) -> Void
    ) {
        if isRunning(for: key) {
            self.onInfo = onInfo
            if let latestInfo { onInfo(latestInfo, latestInfoAt) }
            return
        }
        stop()
        streamKey = key
        self.onInfo = onInfo
        startCount += 1
        task = Task { [weak self] in
            while !Task.isCancelled {
                let info = await renew()
                guard !Task.isCancelled else { return }
                if let info { self?.publish(info) }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Drops the observer while leaving the loop running — the player view is going
    /// away for PiP, but the server-side stream still has to be renewed.
    func detach() {
        onInfo = nil
    }

    /// Cancels the loop. The caller releases the server-side stream separately.
    func stop() {
        task?.cancel()
        task = nil
        streamKey = nil
        onInfo = nil
        latestInfo = nil
        latestInfoAt = .distantPast
    }

    private func publish(_ info: LiveStreamInfo) {
        latestInfo = info
        latestInfoAt = Date()
        onInfo?(info, latestInfoAt)
    }
}

/// Whether the app should opportunistically re-authenticate when it returns to
/// the foreground.
///
/// Re-authenticating rotates the NextPVR SID, and the SID that opened `/live` is
/// the one that owns the server-side handle — renewals sent under a fresh SID
/// don't reach it, so NextPVR expires the stream and deletes the timeshift buffer
/// 15 seconds later. Native PiP makes this routine: the app is backgrounded while
/// playback continues, and the stream dies shortly after the user comes back
/// (#133).
enum ForegroundAuthPolicy {
    static func shouldReauthenticate(isConfigured: Bool, hasActiveLiveStream: Bool) -> Bool {
        isConfigured && !hasActiveLiveStream
    }
}
