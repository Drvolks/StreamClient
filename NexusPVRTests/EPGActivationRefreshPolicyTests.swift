//
//  EPGActivationRefreshPolicyTests.swift
//  NexusPVRTests
//
//  When returning to the foreground refreshes the Channels page EPG (issue #166).
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct EPGActivationRefreshPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func shouldRefresh(
        isConfigured: Bool = true,
        hasLoaded: Bool = true,
        isLoading: Bool = false,
        isRefreshing: Bool = false,
        hasActiveLiveStream: Bool = false,
        refreshedSecondsAgo: TimeInterval? = 3600
    ) -> Bool {
        EPGActivationRefreshPolicy.shouldRefresh(
            isConfigured: isConfigured,
            hasLoaded: hasLoaded,
            isLoading: isLoading,
            isRefreshing: isRefreshing,
            hasActiveLiveStream: hasActiveLiveStream,
            lastRefreshDate: refreshedSecondsAgo.map { now.addingTimeInterval(-$0) },
            now: now
        )
    }

    @Test("Activation refreshes a loaded, idle, stale cache")
    func refreshesLoadedIdleCache() {
        #expect(shouldRefresh())
    }

    @Test("Activation during an in-flight refresh is coalesced into it")
    func coalescesWithInFlightRefresh() {
        #expect(!shouldRefresh(isRefreshing: true))
    }

    @Test("Activation before the first load leaves loadData in charge")
    func skipsBeforeFirstLoad() {
        #expect(!shouldRefresh(hasLoaded: false))
        #expect(!shouldRefresh(isLoading: true))
    }

    @Test("Activation does not refresh while a live stream is open")
    func skipsDuringLiveStream() {
        #expect(!shouldRefresh(hasActiveLiveStream: true))
    }

    @Test("Activation does not refresh an unconfigured server")
    func skipsUnconfiguredServer() {
        #expect(!shouldRefresh(isConfigured: false))
    }

    @Test("Activation soon after a fetch does not download the EPG again")
    func skipsRecentlyRefreshedData() {
        #expect(!shouldRefresh(refreshedSecondsAgo: 30))
        #expect(!shouldRefresh(refreshedSecondsAgo: EPGActivationRefreshPolicy.minimumInterval - 1))
    }

    @Test("Activation refreshes once the minimum interval has elapsed")
    func refreshesAtMinimumInterval() {
        #expect(shouldRefresh(refreshedSecondsAgo: EPGActivationRefreshPolicy.minimumInterval))
    }

    @Test("Activation retries when no fetch has succeeded yet")
    func retriesWithoutSuccessfulFetch() {
        #expect(shouldRefresh(refreshedSecondsAgo: nil))
    }

    @Test("An unloaded cache is not eligible for an activation refresh")
    func unloadedCacheIsNotEligible() {
        let cache = EPGCache()
        #expect(cache.lastRefreshDate == nil)
        #expect(!cache.shouldRefreshOnActivation(
            using: PVRClient(config: ServerConfig(host: "pvr.local", pin: "1234", useHTTPS: false))
        ))
    }

    @Test("invalidate forgets the last refresh date")
    func invalidateClearsLastRefreshDate() {
        let cache = EPGCache()
        cache.invalidate()
        #expect(cache.lastRefreshDate == nil)
    }
}
