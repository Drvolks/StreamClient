//
//  LiveStreamKeepaliveOwnershipTests.swift
//  NexusPVRTests
//
//  Ownership of the live renewal loop across the native PiP lifecycle (issue #133).
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct LiveStreamKeepaliveOwnershipTests {

    private let streamA = URL(string: "http://pvr.local:8866/live?channeloid=1&sid=abc")!
    private let streamB = URL(string: "http://pvr.local:8866/live?channeloid=2&sid=abc")!

    /// Counts occurrences and lets a test await the first one, so no test has to
    /// sleep out the 5s renewal cadence. Main-actor confined in practice — the
    /// keepalive only ever calls back on the main actor.
    @MainActor
    private final class Signal {
        private(set) var count = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func fire() {
            count += 1
            let pending = waiters
            waiters = []
            for waiter in pending { waiter.resume() }
        }

        func wait() async {
            guard count == 0 else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func makeInfo(durationMs: Int64 = 60_000, length: Int64 = 30_000_000) -> LiveStreamInfo {
        LiveStreamInfo(streamDurationMs: durationMs, streamLength: length, isComplete: false)
    }

    @Test("Starting renews and reports buffer state")
    func startRenewsAndReports() async {
        let keepalive = LiveStreamKeepalive()
        let reported = Signal()
        var received: LiveStreamInfo?
        let info = makeInfo()

        keepalive.start(
            streamKey: streamA,
            renew: { info },
            onInfo: { value, _ in received = value; reported.fire() }
        )
        await reported.wait()

        #expect(keepalive.isRunning)
        #expect(keepalive.activeStreamKey == streamA)
        #expect(received == info)
        keepalive.stop()
    }

    /// The PiP restore path: PlayerView is destroyed and recreated while the same
    /// stream keeps playing. Exactly one loop must survive that.
    @Test("Restarting for the same stream adopts the running loop")
    func sameStreamAdoptsExistingLoop() async {
        let keepalive = LiveStreamKeepalive()
        let renewed = Signal()

        keepalive.start(
            streamKey: streamA,
            renew: { renewed.fire(); return nil },
            onInfo: { _, _ in }
        )
        await renewed.wait()
        #expect(keepalive.startCount == 1)

        // View recreated after the PiP restore posts .restoreFromPiP.
        keepalive.start(
            streamKey: streamA,
            renew: { renewed.fire(); return nil },
            onInfo: { _, _ in }
        )

        #expect(keepalive.startCount == 1)
        #expect(keepalive.isRunning(for: streamA))
        keepalive.stop()
    }

    @Test("Adopting replays the buffer state the previous view gathered")
    func adoptingReplaysLatestInfo() async {
        let keepalive = LiveStreamKeepalive()
        let reported = Signal()
        let info = makeInfo(durationMs: 120_000, length: 60_000_000)

        keepalive.start(
            streamKey: streamA,
            renew: { info },
            onInfo: { _, _ in reported.fire() }
        )
        await reported.wait()

        var replayed: LiveStreamInfo?
        var replayedAt: Date?
        keepalive.start(
            streamKey: streamA,
            renew: { nil },
            onInfo: { value, at in replayed = value; replayedAt = at }
        )

        #expect(replayed == info)
        #expect(replayedAt == keepalive.latestInfoAt)
        keepalive.stop()
    }

    @Test("Switching streams replaces the loop instead of stacking one")
    func differentStreamReplacesLoop() async {
        let keepalive = LiveStreamKeepalive()
        let renewed = Signal()

        keepalive.start(streamKey: streamA, renew: { renewed.fire(); return nil }, onInfo: { _, _ in })
        await renewed.wait()
        keepalive.start(streamKey: streamB, renew: { nil }, onInfo: { _, _ in })

        #expect(keepalive.startCount == 2)
        #expect(keepalive.activeStreamKey == streamB)
        #expect(!keepalive.isRunning(for: streamA))
        keepalive.stop()
    }

    /// PlayerView.onDisappear takes this path when it's dismissing for PiP: the
    /// view stops listening, but the server-side stream must keep being renewed.
    @Test("Detaching keeps the loop running")
    func detachKeepsLoopAlive() async {
        let keepalive = LiveStreamKeepalive()
        let reported = Signal()
        let info = makeInfo()

        keepalive.start(
            streamKey: streamA,
            renew: { info },
            onInfo: { _, _ in reported.fire() }
        )
        await reported.wait()

        keepalive.detach()

        #expect(keepalive.isRunning(for: streamA))
        #expect(keepalive.latestInfo == info)
        keepalive.stop()
    }

    @Test("Stopping cancels the loop and clears its state")
    func stopClearsEverything() async {
        let keepalive = LiveStreamKeepalive()
        let reported = Signal()

        keepalive.start(
            streamKey: streamA,
            renew: { self.makeInfo() },
            onInfo: { _, _ in reported.fire() }
        )
        await reported.wait()
        keepalive.stop()

        #expect(!keepalive.isRunning)
        #expect(keepalive.activeStreamKey == nil)
        #expect(keepalive.latestInfo == nil)
        #expect(keepalive.latestInfoAt == .distantPast)
        #expect(!keepalive.isRunning(for: streamA))
    }

    @Test("Renewal cadence stays well under NextPVR's 15s expiry")
    func cadenceIsSafelyUnderExpiry() {
        #expect(LiveStreamKeepalive.interval < .seconds(15))
    }

    // MARK: - Foreground re-authentication

    /// Re-auth rotates the SID that owns the `/live` handle. Backgrounding while
    /// PiP plays makes the foreground re-auth fire mid-stream, which orphaned the
    /// handle and let NextPVR delete the timeshift buffer ~15s later.
    @Test("Foreground re-auth is skipped while a live stream is open")
    func foregroundAuthSkippedDuringLiveStream() {
        #expect(!ForegroundAuthPolicy.shouldReauthenticate(isConfigured: true, hasActiveLiveStream: true))
        #expect(ForegroundAuthPolicy.shouldReauthenticate(isConfigured: true, hasActiveLiveStream: false))
        #expect(!ForegroundAuthPolicy.shouldReauthenticate(isConfigured: false, hasActiveLiveStream: false))
        #expect(!ForegroundAuthPolicy.shouldReauthenticate(isConfigured: false, hasActiveLiveStream: true))
    }

    @Test("A client with no live stream open reports none")
    func clientReportsNoLiveStreamWhenIdle() async throws {
        let client = NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
        try await client.authenticate()
        #expect(!client.hasActiveLiveStream)
    }
}
