//
//  RecordingPositionStoreTests.swift
//  NexusPVRTests
//
//  Dispatcharr recording resume positions synced through iCloud (#183):
//  newest-wins merging, "from the beginning" as an entry, the legacy
//  per-recording keys, the size cap, and reconciling with the iCloud copy.
//

import Testing
import Foundation
@testable import NextPVR

struct RecordingPositionStoreTests {

    private func scratchDefaults() -> UserDefaults {
        let suite = "RecordingPositionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func store(_ entries: [(id: Int, position: Int, at: TimeInterval)]) -> RecordingPositionStore {
        var store = RecordingPositionStore()
        for entry in entries {
            store.set(recordingId: entry.id, position: entry.position, at: date(entry.at))
        }
        return store
    }

    // MARK: - Positions

    @Test("A saved position is the resume position")
    func resumePosition() {
        let positions = store([(id: 7, position: 600, at: 0)])
        #expect(positions.resumePosition(for: 7) == 600)
        #expect(positions.resumePosition(for: 8) == nil)
    }

    @Test("Watch from beginning is kept as an entry with no resume position")
    func resetIsAnEntry() {
        let positions = store([(id: 7, position: 600, at: 0), (id: 7, position: 0, at: 10)])
        #expect(positions[7]?.position == 0)
        #expect(positions.resumePosition(for: 7) == nil)
    }

    @Test("A negative position is stored as 0")
    func clampsNegativePosition() {
        #expect(store([(id: 7, position: -5, at: 0)])[7]?.position == 0)
    }

    // MARK: - Merging

    @Test("Merging keeps the newer entry per recording, from either side")
    func mergeKeepsNewer() {
        var local = store([(id: 1, position: 100, at: 10), (id: 2, position: 200, at: 50)])
        let cloud = store([(id: 1, position: 900, at: 20), (id: 2, position: 50, at: 5), (id: 3, position: 300, at: 1)])
        local.merge(cloud)
        #expect(local.resumePosition(for: 1) == 900)
        #expect(local.resumePosition(for: 2) == 200)
        #expect(local.resumePosition(for: 3) == 300)
    }

    @Test("A newer watch-from-beginning overrides another device's position")
    func mergePropagatesReset() {
        var local = store([(id: 1, position: 1500, at: 10)])
        local.merge(store([(id: 1, position: 0, at: 20)]))
        #expect(local.resumePosition(for: 1) == nil)
        #expect(local[1]?.position == 0)
    }

    @Test("Merging gives the same result in either direction, ties included")
    func mergeIsCommutative() {
        let a = store([(id: 1, position: 100, at: 10), (id: 2, position: 40, at: 5)])
        let b = store([(id: 1, position: 700, at: 10), (id: 3, position: 9, at: 1)])
        var ab = a
        ab.merge(b)
        var ba = b
        ba.merge(a)
        #expect(ab == ba)
        #expect(ab.resumePosition(for: 1) == 700)
    }

    // MARK: - Size cap

    @Test("Past the cap the oldest entries are dropped")
    func prunesOldest() {
        var positions = RecordingPositionStore()
        for id in 0..<(RecordingPositionStore.maxEntries + 20) {
            positions.set(recordingId: id, position: 60, at: date(TimeInterval(id)))
        }
        #expect(positions.entries.count == RecordingPositionStore.maxEntries)
        #expect(positions[19] == nil)
        #expect(positions[20] != nil)
    }

    @Test("A full store stays far below the iCloud key-value limits")
    func encodedSizeIsSmall() throws {
        var positions = RecordingPositionStore()
        for id in 0..<RecordingPositionStore.maxEntries {
            positions.set(recordingId: 1_000_000 + id, position: 36_000, at: Date())
        }
        let size = try #require(positions.encoded).count
        #expect(size < 100_000)
    }

    // MARK: - Legacy keys

    @Test("Legacy per-recording keys are imported once and left in place")
    func importsLegacyKeys() {
        let defaults = scratchDefaults()
        defaults.set(420, forKey: "recording_position_11")
        defaults.set(0, forKey: "recording_position_12")
        defaults.set("x", forKey: "recording_position_abc")

        let positions = RecordingPositionStore.load(from: defaults, cloudData: nil)
        #expect(positions.resumePosition(for: 11) == 420)
        #expect(positions[12] == nil)
        #expect(positions.entries.count == 1)
        #expect(defaults.integer(forKey: "recording_position_11") == 420)

        // A later change to the old key no longer counts.
        defaults.set(999, forKey: "recording_position_11")
        defaults.set(50, forKey: "recording_position_13")
        let again = RecordingPositionStore.load(from: defaults, cloudData: nil)
        #expect(again.resumePosition(for: 11) == 420)
        #expect(again[13] == nil)
    }

    @Test("An imported legacy position loses to any synced entry")
    func legacyLosesToSynced() {
        let defaults = scratchDefaults()
        defaults.set(420, forKey: "recording_position_11")
        let cloud = store([(id: 11, position: 0, at: 0)])

        let positions = RecordingPositionStore.load(from: defaults, cloudData: cloud.encoded)
        #expect(positions.resumePosition(for: 11) == nil)
    }

    // MARK: - Persistence and sync

    @Test("Loading merges the iCloud copy and writes the result back locally")
    func loadMergesCloud() {
        let defaults = scratchDefaults()
        store([(id: 1, position: 100, at: 10)]).saveLocally(to: defaults)
        let cloud = store([(id: 1, position: 800, at: 30), (id: 2, position: 60, at: 5)])

        let positions = RecordingPositionStore.load(from: defaults, cloudData: cloud.encoded)
        #expect(positions.resumePosition(for: 1) == 800)
        #expect(positions.resumePosition(for: 2) == 60)
        #expect(RecordingPositionStore.load(from: defaults, cloudData: nil) == positions)
    }

    @Test("Unreadable data is treated as empty")
    func ignoresGarbage() {
        let defaults = scratchDefaults()
        defaults.set(Data("nope".utf8), forKey: RecordingPositionStore.storageKey)
        let positions = RecordingPositionStore.load(from: defaults, cloudData: Data("nope".utf8))
        #expect(positions.entries.isEmpty)
    }

    @Test("Reconcile reports positions arriving from another device")
    func reconcileDetectsIncoming() {
        let defaults = scratchDefaults()
        let shared = store([(id: 1, position: 100, at: 10)])
        shared.saveLocally(to: defaults)
        var cloud = shared
        cloud.set(recordingId: 2, position: 300, at: date(20))

        let result = RecordingPositionStore.reconcile(defaults: defaults, cloudData: cloud.encoded)
        #expect(result.localChanged)
        #expect(!result.cloudIsBehind)
        #expect(result.store.resumePosition(for: 2) == 300)
    }

    @Test("Reconcile reports when this device holds entries iCloud lacks")
    func reconcileDetectsCloudBehind() {
        let defaults = scratchDefaults()
        store([(id: 1, position: 100, at: 10), (id: 2, position: 300, at: 20)]).saveLocally(to: defaults)
        // Another device published without having seen recording 2.
        let cloud = store([(id: 1, position: 100, at: 10)])

        let result = RecordingPositionStore.reconcile(defaults: defaults, cloudData: cloud.encoded)
        #expect(!result.localChanged)
        #expect(result.cloudIsBehind)
        #expect(result.store.resumePosition(for: 2) == 300)
    }

    @Test("Reconcile settles once both copies match")
    func reconcileSettles() {
        let defaults = scratchDefaults()
        let shared = store([(id: 1, position: 100, at: 10)])
        shared.saveLocally(to: defaults)
        _ = RecordingPositionStore.load(from: defaults, cloudData: nil)

        let result = RecordingPositionStore.reconcile(defaults: defaults, cloudData: shared.encoded)
        #expect(!result.localChanged)
        #expect(!result.cloudIsBehind)
    }

    // MARK: - Recording mapping

    @Test("A Dispatcharr recording takes its resume position from the store")
    func recordingUsesStore() throws {
        let json = """
        {"id": 42, "start_time": "2026-01-01T10:00:00Z", "end_time": "2026-01-01T11:00:00Z", "channel": 3}
        """
        let item = try JSONDecoder().decode(DispatcharrRecording.self, from: Data(json.utf8))
        #expect(item.toRecording(positions: store([(id: 42, position: 900, at: 0)])).playbackPosition == 900)
        #expect(item.toRecording(positions: store([(id: 42, position: 0, at: 0)])).playbackPosition == nil)
        #expect(item.toRecording(positions: RecordingPositionStore()).playbackPosition == nil)
    }
}
