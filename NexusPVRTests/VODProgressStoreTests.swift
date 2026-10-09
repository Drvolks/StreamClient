//
//  VODProgressStoreTests.swift
//  NexusPVRTests
//
//  VOD playback positions (#17): what counts as started and watched, the
//  size cap, persistence, and merging with the iCloud copy (#183).
//

import Testing
import Foundation
@testable import NextPVR

struct VODProgressStoreTests {

    private func scratchDefaults() -> UserDefaults {
        let suite = "VODProgressStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("A position part-way through is a resume point")
    func recordsResumePosition() {
        var store = VODProgressStore()
        store.record(uuid: "m1", position: 600, duration: 6000)
        let progress = store["m1"]
        #expect(progress?.position == 600)
        #expect(progress?.hasResumePosition == true)
        #expect(progress?.isWatched == false)
        #expect(progress?.watchState == .resume(progress: 0.1))
    }

    @Test("The first seconds of an accidental play are not recorded")
    func ignoresTrivialPositions() {
        var store = VODProgressStore()
        store.record(uuid: "m1", position: 10, duration: 6000)
        store.record(uuid: "", position: 600, duration: 6000)
        #expect(store.entries.isEmpty)
    }

    @Test("Stopping in the last half minute counts as watched to the end")
    func nearEndIsWatched() {
        var store = VODProgressStore()
        store.record(uuid: "m1", position: 5985, duration: 6000)
        #expect(store["m1"]?.position == 6000)
        #expect(store["m1"]?.isWatched == true)
        #expect(store["m1"]?.hasResumePosition == false)
        #expect(store["m1"]?.watchState == .watched)
    }

    @Test("Ninety percent is watched, like a recording")
    func ninetyPercentIsWatched() {
        let almost = VODProgress(position: 5399, duration: 6000, updatedAt: Date())
        let there = VODProgress(position: 5400, duration: 6000, updatedAt: Date())
        #expect(almost.isWatched == false)
        #expect(there.isWatched == true)
    }

    @Test("An unknown duration can be resumed but never counts as watched")
    func unknownDuration() {
        var store = VODProgressStore()
        store.record(uuid: "m1", position: 900, duration: 0)
        #expect(store["m1"]?.isWatched == false)
        #expect(store["m1"]?.hasResumePosition == true)
        #expect(store["m1"]?.fraction == 0)
    }

    @Test("Clearing forgets the item, keeping a position-0 entry to sync")
    func clear() {
        var store = VODProgressStore()
        store.record(uuid: "m1", position: 600, duration: 6000)
        store.clear(uuid: "m1")
        store.clear(uuid: "never-played")
        #expect(store["m1"] == nil)
        #expect(store.entries["m1"]?.position == 0)
        #expect(store.entries["m1"]?.watchState == .new)
        #expect(store.entries["never-played"] == nil)
    }

    @Test("Past the cap, the oldest positions are dropped")
    func capsEntries() {
        var store = VODProgressStore()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<(VODProgressStore.maxEntries + 3) {
            store.record(uuid: "item-\(index)", position: 100, duration: 1000, at: start.addingTimeInterval(Double(index)))
        }
        #expect(store.entries.count == VODProgressStore.maxEntries)
        #expect(store["item-0"] == nil)
        #expect(store["item-2"] == nil)
        #expect(store["item-3"] != nil)
    }

    @Test("Positions survive a save and load")
    func persists() {
        let defaults = scratchDefaults()
        var store = VODProgressStore()
        store.record(uuid: "e1", position: 1200, duration: 2700)
        store.save(to: defaults)
        #expect(VODProgressStore.load(from: defaults)["e1"]?.position == 1200)
    }

    @Test("Nothing saved, or garbage, loads as empty")
    func loadsEmpty() {
        let defaults = scratchDefaults()
        #expect(VODProgressStore.load(from: defaults).entries.isEmpty)
        defaults.set(Data("not json".utf8), forKey: VODProgressStore.storageKey)
        #expect(VODProgressStore.load(from: defaults).entries.isEmpty)
    }

    // MARK: - iCloud sync (#183)

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    @Test("Merging keeps the newer entry per item, from either side")
    func mergeKeepsNewer() {
        var local = VODProgressStore()
        local.record(uuid: "a", position: 100, duration: 6000, at: date(10))
        local.record(uuid: "b", position: 200, duration: 6000, at: date(50))
        var cloud = VODProgressStore()
        cloud.record(uuid: "a", position: 900, duration: 6000, at: date(20))
        cloud.record(uuid: "b", position: 50, duration: 6000, at: date(5))
        cloud.record(uuid: "c", position: 300, duration: 6000, at: date(1))

        local.merge(cloud)
        #expect(local["a"]?.position == 900)
        #expect(local["b"]?.position == 200)
        #expect(local["c"]?.position == 300)
    }

    @Test("Marking unwatched on one device overrides another device's older position")
    func mergePropagatesClear() {
        var here = VODProgressStore()
        here.record(uuid: "a", position: 6000, duration: 6000, at: date(10))
        var there = here
        there.clear(uuid: "a", at: date(20))

        here.merge(there)
        #expect(here["a"] == nil)

        // And a later play on the first device wins back.
        var later = VODProgressStore()
        later.record(uuid: "a", position: 400, duration: 6000, at: date(30))
        here.merge(later)
        #expect(here["a"]?.position == 400)
    }

    @Test("Merging gives the same result in either direction, ties included")
    func mergeIsCommutative() {
        var a = VODProgressStore()
        a.record(uuid: "x", position: 100, duration: 6000, at: date(10))
        a.record(uuid: "y", position: 40, duration: 6000, at: date(5))
        var b = VODProgressStore()
        b.record(uuid: "x", position: 700, duration: 6000, at: date(10))
        b.record(uuid: "z", position: 90, duration: 6000, at: date(1))
        var ab = a
        ab.merge(b)
        var ba = b
        ba.merge(a)
        #expect(ab == ba)
        #expect(ab["x"]?.position == 700)
    }

    @Test("Loading merges the iCloud copy and writes the result back locally")
    func loadMergesCloud() {
        let defaults = scratchDefaults()
        var local = VODProgressStore()
        local.record(uuid: "a", position: 100, duration: 6000, at: date(10))
        local.save(to: defaults)
        var cloud = VODProgressStore()
        cloud.record(uuid: "a", position: 800, duration: 6000, at: date(30))
        cloud.record(uuid: "b", position: 60, duration: 6000, at: date(5))

        let merged = VODProgressStore.load(from: defaults, cloudData: cloud.encoded)
        #expect(merged["a"]?.position == 800)
        #expect(merged["b"]?.position == 60)
        #expect(VODProgressStore.load(from: defaults) == merged)
    }

    @Test("Reconcile reports progress arriving from another device")
    func reconcileDetectsIncoming() {
        let defaults = scratchDefaults()
        var shared = VODProgressStore()
        shared.record(uuid: "a", position: 100, duration: 6000, at: date(10))
        shared.save(to: defaults)
        var cloud = shared
        cloud.record(uuid: "b", position: 300, duration: 6000, at: date(20))

        let result = VODProgressStore.reconcile(defaults: defaults, cloudData: cloud.encoded)
        #expect(result.localChanged)
        #expect(!result.cloudIsBehind)
        #expect(result.store["b"]?.position == 300)
    }

    @Test("Reconcile reports when this device holds entries iCloud lacks, then settles")
    func reconcileDetectsCloudBehind() {
        let defaults = scratchDefaults()
        var local = VODProgressStore()
        local.record(uuid: "a", position: 100, duration: 6000, at: date(10))
        local.record(uuid: "b", position: 300, duration: 6000, at: date(20))
        local.save(to: defaults)
        var cloud = VODProgressStore()
        cloud.record(uuid: "a", position: 100, duration: 6000, at: date(10))

        let result = VODProgressStore.reconcile(defaults: defaults, cloudData: cloud.encoded)
        #expect(!result.localChanged)
        #expect(result.cloudIsBehind)

        let settled = VODProgressStore.reconcile(defaults: defaults, cloudData: result.store.encoded)
        #expect(!settled.localChanged)
        #expect(!settled.cloudIsBehind)
    }
}
