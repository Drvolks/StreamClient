//
//  NexusPVRTests.swift
//  NexusPVRTests
//
//  Created by drvolks on 2026-02-02.
//

import Testing

struct NexusPVRTests {

    @Test func userPreferencesPrefersMostRecentLocalValue() async throws {
        var local = UserPreferences()
        local.tvosGPUAPI = .pixelbuffer
        local.updatedAt = Date(timeIntervalSince1970: 200)

        var cloud = UserPreferences()
        cloud.tvosGPUAPI = .metal
        cloud.updatedAt = Date(timeIntervalSince1970: 100)

        let resolved = UserPreferences.resolvePersistence(local: local, cloud: cloud)

        #expect(resolved?.tvosGPUAPI == .pixelbuffer)
    }

    @Test func userPreferencesFallsBackToLocalWhenLegacyTimestampsAreMissing() async throws {
        var local = UserPreferences()
        local.tvosGPUAPI = .pixelbuffer
        local.updatedAt = .distantPast

        var cloud = UserPreferences()
        cloud.tvosGPUAPI = .metal
        cloud.updatedAt = .distantPast

        let resolved = UserPreferences.resolvePersistence(local: local, cloud: cloud)

        #expect(resolved?.tvosGPUAPI == .pixelbuffer)
    }

}
