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
        prefs.deinterlaceMode = .on
        prefs.preferredSubtitleLanguage = "eng"
        prefs.landingTab = .channels
        prefs.hideRecordings = true
        prefs.theme = .light
        prefs.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)

        #expect(decoded.keywords == prefs.keywords)
        #expect(decoded.seekBackwardSeconds == prefs.seekBackwardSeconds)
        #expect(decoded.seekForwardSeconds == prefs.seekForwardSeconds)
        #expect(decoded.audioChannels == prefs.audioChannels)
        #expect(decoded.subtitleSize == prefs.subtitleSize)
        #expect(decoded.subtitleBackground == prefs.subtitleBackground)
        #expect(decoded.deinterlaceMode == prefs.deinterlaceMode)
        #expect(decoded.preferredSubtitleLanguage == prefs.preferredSubtitleLanguage)
        #expect(decoded.landingTab == prefs.landingTab)
        #expect(decoded.landingTabRawValue == prefs.landingTabRawValue)
        #expect(decoded.hideRecordings == prefs.hideRecordings)
        #expect(decoded.theme == prefs.theme)
        #expect(decoded.themeRawValue == prefs.themeRawValue)
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
        #expect(prefs.deinterlaceMode == .auto)
        #expect(prefs.preferredSubtitleLanguage == nil)
        #expect(prefs.landingTab == .guide)
        #expect(prefs.landingTabRawValue == LandingTabOption.guide.rawValue)
        #expect(prefs.hideRecordings == false)
        #expect(prefs.theme == .system)
        #expect(prefs.themeRawValue == AppTheme.system.rawValue)
        #expect(prefs.updatedAt == .distantPast)
    }

    @Test("Decoding prefs written before deinterlacing defaults to Automatic")
    func decodeLegacyWithoutDeinterlaceMode() throws {
        // Blobs saved before #142 carry no `deinterlaceMode`; existing users
        // get the recommended automatic mode rather than a decode failure.
        let json = #"{"keywords": ["news"], "audioChannels": "stereo"}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.deinterlaceMode == .auto)
    }

    @Test("DeinterlaceMode maps to the matching mpv option value")
    func deinterlaceModeMpvValues() {
        #expect(DeinterlaceMode.off.mpvValue == "no")
        #expect(DeinterlaceMode.auto.mpvValue == "auto")
        #expect(DeinterlaceMode.on.mpvValue == "yes")
    }

    @Test("Decoding legacy JSON without landingTab defaults to Guide")
    func decodeLegacyWithoutLandingTab() throws {
        // Pre-landingTab JSON blobs should still decode cleanly to the
        // default landing page (Guide) rather than failing.
        let json = #"{"keywords": ["news"]}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.keywords == ["news"])
        #expect(prefs.landingTab == .guide)
    }

    @Test("LandingTabOption round-trips through the raw value")
    func landingTabRoundTrips() throws {
        for option in LandingTabOption.allCases {
            var prefs = UserPreferences()
            prefs.landingTab = option
            let data = try JSONEncoder().encode(prefs)
            let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
            #expect(decoded.landingTab == option)
        }
    }

    @Test("AppTheme round-trips through the raw value")
    func themeRoundTrips() throws {
        for option in AppTheme.allCases {
            var prefs = UserPreferences()
            prefs.theme = option
            let data = try JSONEncoder().encode(prefs)
            let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
            #expect(decoded.theme == option)
            #expect(decoded.themeRawValue == option.rawValue)
        }
    }

    @Test("Decoding legacy JSON without a theme defaults to System")
    func decodeLegacyWithoutTheme() throws {
        let json = #"{"keywords": ["news"]}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.theme == .system)
    }

    @Test("An unknown persisted theme falls back to System")
    func decodeUnknownTheme() throws {
        let json = #"{"themeRawValue": "Sepia"}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.theme == .system)
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

    // MARK: - Guide group sidebar preferences (#158)

    @Test("Guide group sidebar preferences survive a Codable round-trip")
    func guideGroupPreferencesRoundTrip() throws {
        var prefs = UserPreferences()
        prefs.guideShowGroupsInSidebar = true
        prefs.guideGroupIds = [
            ChannelGroup.stableId(forName: "Sports"),
            ChannelGroup.stableId(forName: "News")
        ]

        let decoded = try JSONDecoder().decode(
            UserPreferences.self,
            from: try JSONEncoder().encode(prefs)
        )

        #expect(decoded.guideShowGroupsInSidebar)
        #expect(decoded.guideGroupIds == prefs.guideGroupIds)
    }

    @Test("Preferences saved before the group feature decode with defaults")
    func guideGroupPreferencesBackwardCompatible() throws {
        // A payload from a build that never wrote the group keys.
        let json = #"{"keywords": ["news"], "seekBackwardSeconds": 10}"#
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))

        #expect(decoded.guideShowGroupsInSidebar == false)
        #expect(decoded.guideGroupIds.isEmpty)
    }

    @Test("Name-derived group ids round-trip through JSON unchanged")
    func nameDerivedGroupIdsSurviveEncoding() throws {
        let ids = ["Sports", "News", "Kids", "Documentary & Lifestyle"]
            .map(ChannelGroup.stableId(forName:))
        var prefs = UserPreferences()
        prefs.guideGroupIds = ids

        let decoded = try JSONDecoder().decode(
            UserPreferences.self,
            from: try JSONEncoder().encode(prefs)
        )

        #expect(decoded.guideGroupIds == ids)
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
