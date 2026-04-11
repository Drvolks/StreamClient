//
//  UserPreferencesTests.swift
//  NexusPVRTests
//
//  Tests for UserPreferences Codable round-trip, legacy migration, and
//  persistence resolution logic.
//

import Testing
import Foundation
@testable import NextPVR

struct UserPreferencesTests {

    // MARK: - Codable round-trip

    @Test("UserPreferences Codable round-trip preserves all fields")
    func roundTrip() throws {
        var prefs = UserPreferences()
        prefs.keywords = ["news", "sports"]
        prefs.seekBackwardSeconds = 15
        prefs.seekForwardSeconds = 45
        prefs.audioChannels = "stereo"
        prefs.subtitleSize = .large
        prefs.subtitleBackground = false
        prefs.preferredSubtitleLanguage = "eng"
        prefs.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)

        #expect(decoded.keywords == prefs.keywords)
        #expect(decoded.seekBackwardSeconds == prefs.seekBackwardSeconds)
        #expect(decoded.seekForwardSeconds == prefs.seekForwardSeconds)
        #expect(decoded.audioChannels == prefs.audioChannels)
        #expect(decoded.subtitleSize == prefs.subtitleSize)
        #expect(decoded.subtitleBackground == prefs.subtitleBackground)
        #expect(decoded.preferredSubtitleLanguage == prefs.preferredSubtitleLanguage)
        #expect(decoded.updatedAt == prefs.updatedAt)
    }

    @Test("Decoding empty JSON applies defaults")
    func decodeDefaults() throws {
        let data = Data("{}".utf8)
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: data)
        #expect(prefs.keywords.isEmpty)
        #expect(prefs.seekBackwardSeconds == 10)
        #expect(prefs.seekForwardSeconds == 30)
        #expect(prefs.audioChannels == "auto")
        #expect(prefs.subtitleSize == .medium)
        #expect(prefs.subtitleBackground == true)
        #expect(prefs.preferredSubtitleLanguage == nil)
        #expect(prefs.updatedAt == .distantPast)
    }

    @Test("Decoding legacy seekTimeSeconds migrates to seekForwardSeconds")
    func migratesLegacySeekTime() throws {
        let json = #"{"seekTimeSeconds": 25}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.seekForwardSeconds == 25)
    }

    @Test("Explicit seekForwardSeconds wins over legacy seekTimeSeconds")
    func explicitSeekBeatsLegacy() throws {
        let json = #"{"seekTimeSeconds": 25, "seekForwardSeconds": 45}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.seekForwardSeconds == 45)
    }

    // MARK: - resolvePersistence

    @Test("resolvePersistence returns nil when both inputs are nil")
    func resolve_bothNil() {
        #expect(UserPreferences.resolvePersistence(local: nil, cloud: nil) == nil)
    }

    @Test("resolvePersistence returns local when only local is present")
    func resolve_localOnly() {
        var local = UserPreferences()
        local.keywords = ["local"]
        let resolved = UserPreferences.resolvePersistence(local: local, cloud: nil)
        #expect(resolved?.keywords == ["local"])
    }

    @Test("resolvePersistence returns cloud when only cloud is present")
    func resolve_cloudOnly() {
        var cloud = UserPreferences()
        cloud.keywords = ["cloud"]
        let resolved = UserPreferences.resolvePersistence(local: nil, cloud: cloud)
        #expect(resolved?.keywords == ["cloud"])
    }

    @Test("resolvePersistence picks the newer updatedAt when both present")
    func resolve_newerWins() {
        var local = UserPreferences()
        local.keywords = ["local"]
        local.updatedAt = Date(timeIntervalSince1970: 100)

        var cloud = UserPreferences()
        cloud.keywords = ["cloud"]
        cloud.updatedAt = Date(timeIntervalSince1970: 200)

        let resolved = UserPreferences.resolvePersistence(local: local, cloud: cloud)
        #expect(resolved?.keywords == ["cloud"])
    }

    // MARK: - currentGPUAPI

    @Test("currentGPUAPI picks the per-platform GPU setting")
    func currentGPUAPI_perPlatform() {
        var prefs = UserPreferences()
        prefs.iosGPUAPI = .metal
        prefs.tvosGPUAPI = .opengl
        prefs.macosGPUAPI = .pixelbuffer

        #if os(tvOS)
        #expect(prefs.currentGPUAPI == .opengl)
        #elseif os(macOS)
        #expect(prefs.currentGPUAPI == .pixelbuffer)
        #else
        #expect(prefs.currentGPUAPI == .metal)
        #endif
    }

    @Test("resolvePersistence prefers local when both timestamps are distantPast")
    func resolve_tieGoesToLocal() {
        var local = UserPreferences()
        local.keywords = ["local"]

        var cloud = UserPreferences()
        cloud.keywords = ["cloud"]

        let resolved = UserPreferences.resolvePersistence(local: local, cloud: cloud)
        #expect(resolved?.keywords == ["local"])
    }
}
