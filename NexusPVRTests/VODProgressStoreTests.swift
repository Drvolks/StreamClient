//
//  VODProgressStoreTests.swift
//  NexusPVRTests
//
//  Device-local VOD playback positions (#17): what counts as started and
//  watched, the size cap, and persistence.
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

    @Test("Clearing forgets the item")
    func clear() {
        var store = VODProgressStore()
        store.record(uuid: "m1", position: 600, duration: 6000)
        store.clear(uuid: "m1")
        #expect(store["m1"] == nil)
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
}
