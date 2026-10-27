//
//  NexusPVRTests.swift
//  NexusPVRTests
//
//  Created by drvolks on 2026-02-02.
//

import Testing
import Foundation
@testable import NextPVR

struct NexusPVRTests {

    @Test func userPreferencesPrefersMostRecentLocalValue() async throws {
        var local = UserPreferences()
        local.seekForwardSeconds = 45
        local.updatedAt = Date(timeIntervalSince1970: 200)

        var cloud = UserPreferences()
        cloud.seekForwardSeconds = 15
        cloud.updatedAt = Date(timeIntervalSince1970: 100)

        let resolved = UserPreferences.resolvePersistence(local: local, cloud: cloud)

        #expect(resolved?.seekForwardSeconds == 45)
    }

    @Test func userPreferencesFallsBackToLocalWhenLegacyTimestampsAreMissing() async throws {
        var local = UserPreferences()
        local.seekForwardSeconds = 45
        local.updatedAt = .distantPast

        var cloud = UserPreferences()
        cloud.seekForwardSeconds = 15
        cloud.updatedAt = .distantPast

        let resolved = UserPreferences.resolvePersistence(local: local, cloud: cloud)

        #expect(resolved?.seekForwardSeconds == 45)
    }

}
