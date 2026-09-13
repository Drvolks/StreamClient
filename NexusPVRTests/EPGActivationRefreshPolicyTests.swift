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

    private func shouldRefresh(
        isConfigured: Bool = true,
        hasLoaded: Bool = true,
        isLoading: Bool = false,
        isRefreshing: Bool = false,
        hasActiveLiveStream: Bool = false
    ) -> Bool {
        EPGActivationRefreshPolicy.shouldRefresh(
            isConfigured: isConfigured,
            hasLoaded: hasLoaded,
            isLoading: isLoading,
            isRefreshing: isRefreshing,
            hasActiveLiveStream: hasActiveLiveStream
        )
    }

    @Test("Activation refreshes a loaded, idle cache")
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

    @Test("A fresh cache is not eligible for an activation refresh")
    func freshCacheIsNotEligible() {
        let cache = EPGCache()
        #expect(!EPGActivationRefreshPolicy.shouldRefresh(
            isConfigured: true,
            hasLoaded: cache.hasLoaded,
            isLoading: cache.isLoading,
            isRefreshing: cache.isRefreshing,
            hasActiveLiveStream: false
        ))
    }
}
