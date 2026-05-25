//
//  PlayerStatsExtraTests.swift
//  NexusPVRTests
//
//  Additional tests for PlayerStats load() and save() persistence.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct PlayerStatsExtraTests {

    @Test("PlayerStats save and load round-trip preserves values")
    func saveAndLoadRoundTrip() throws {
        var original = PlayerStats()
        original.avgFps = 59.94
        original.avgBitrateKbps = 12_000
        original.totalDroppedFrames = 17
        original.totalDecoderDroppedFrames = 3
        original.totalVoDelayedFrames = 9
        original.maxAvsync = 0.042

        original.save()
        let loaded = PlayerStats.load()

        #expect(loaded.avgFps == original.avgFps)
        #expect(loaded.avgBitrateKbps == original.avgBitrateKbps)
        #expect(loaded.totalDroppedFrames == original.totalDroppedFrames)
        #expect(loaded.totalDecoderDroppedFrames == original.totalDecoderDroppedFrames)
        #expect(loaded.totalVoDelayedFrames == original.totalVoDelayedFrames)
        #expect(loaded.maxAvsync == original.maxAvsync)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "PlayerStats")
    }

    @Test("PlayerStats load returns default when no data stored")
    func loadReturnsDefaultWhenNoData() {
        UserDefaults.standard.removeObject(forKey: "PlayerStats")
        let loaded = PlayerStats.load()
        #expect(loaded.avgFps == 0)
        #expect(loaded.avgBitrateKbps == 0)
    }

    @Test("PlayerStats save overwrites previous data")
    func saveOverwritesPrevious() {
        var stats1 = PlayerStats()
        stats1.avgFps = 30
        stats1.save()

        var stats2 = PlayerStats()
        stats2.avgFps = 60
        stats2.save()

        let loaded = PlayerStats.load()
        #expect(loaded.avgFps == 60)

        UserDefaults.standard.removeObject(forKey: "PlayerStats")
    }
}
