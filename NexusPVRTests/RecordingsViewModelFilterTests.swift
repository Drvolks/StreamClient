//
//  RecordingsViewModelFilterTests.swift
//  NexusPVRTests
//
//  Pure-logic tests for RecordingsViewModel filtering/grouping computed
//  properties. We inject a NextPVRClient with a demo ServerConfig (which
//  never hits the network) and populate the @Published arrays directly to
//  exercise filteredRecordings, seriesGroups, and recordingsSeriesSummaries.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct RecordingsViewModelFilterTests {

    private func makeClient() -> NextPVRClient {
        NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
    }

    private func makeVM() -> RecordingsViewModel {
        RecordingsViewModel(client: makeClient())
    }

    private func rec(
        id: Int,
        name: String,
        startTime: Int,
        duration: Int = 3600,
        status: String = "ready",
        season: Int? = nil,
        episode: Int? = nil,
        subtitle: String? = nil,
        seriesBannerURL: String? = nil
    ) -> Recording {
        Recording(
            id: id,
            name: name,
            subtitle: subtitle,
            desc: nil,
            startTime: startTime,
            duration: duration,
            channel: "CH",
            channelId: 1,
            status: status,
            file: nil,
            recurring: 0,
            recurringParent: nil,
            epgEventId: nil,
            size: nil,
            quality: nil,
            genres: nil,
            playbackPosition: nil,
            prePadding: nil,
            postPadding: nil,
            season: season,
            episode: episode,
            seriesBannerURL: seriesBannerURL
        )
    }

    // MARK: - hasActiveRecordings

    @Test("hasActiveRecordings reflects whether activeRecordings is non-empty")
    func hasActiveRecordings() {
        let vm = makeVM()
        #expect(vm.hasActiveRecordings == false)
        vm.activeRecordings = [rec(id: 1, name: "Live", startTime: 0, status: "recording")]
        #expect(vm.hasActiveRecordings)
    }

    // MARK: - filteredRecordings sort order

    @Test("filteredRecordings for .completed sorts newest first")
    func completedSortedNewestFirst() {
        let vm = makeVM()
        vm.filter = .completed
        vm.completedRecordings = [
            rec(id: 1, name: "Old", startTime: 1_000),
            rec(id: 2, name: "New", startTime: 2_000),
            rec(id: 3, name: "Mid", startTime: 1_500)
        ]
        let ids = vm.filteredRecordings.map(\.id)
        #expect(ids == [2, 3, 1])
    }

    @Test("filteredRecordings for .scheduled sorts oldest first (next up at the top)")
    func scheduledSortedOldestFirst() {
        let vm = makeVM()
        vm.filter = .scheduled
        vm.scheduledRecordings = [
            rec(id: 10, name: "Later", startTime: 3_000, status: "pending"),
            rec(id: 20, name: "Soon", startTime: 2_000, status: "pending"),
            rec(id: 30, name: "Now", startTime: 1_000, status: "pending")
        ]
        let ids = vm.filteredRecordings.map(\.id)
        #expect(ids == [30, 20, 10])
    }

    @Test("filteredRecordings for .recording sorts newest first")
    func recordingSortedNewestFirst() {
        let vm = makeVM()
        vm.filter = .recording
        vm.activeRecordings = [
            rec(id: 1, name: "A", startTime: 100, status: "recording"),
            rec(id: 2, name: "B", startTime: 200, status: "recording")
        ]
        let ids = vm.filteredRecordings.map(\.id)
        #expect(ids == [2, 1])
    }

    @Test("standaloneRecordings mirrors filteredRecordings")
    func standaloneMirrorsFiltered() {
        let vm = makeVM()
        vm.filter = .completed
        vm.completedRecordings = [
            rec(id: 1, name: "X", startTime: 500),
            rec(id: 2, name: "Y", startTime: 1000)
        ]
        #expect(vm.standaloneRecordings.map(\.id) == vm.filteredRecordings.map(\.id))
    }

    // MARK: - seriesGroups

    @Test("seriesGroups groups by series name and excludes non-series recordings")
    func seriesGroupsPartition() {
        let vm = makeVM()
        vm.filter = .completed
        vm.completedRecordings = [
            rec(id: 1, name: "Standalone Movie", startTime: 1000),
            rec(id: 2, name: "My Show", startTime: 2000, season: 1, episode: 1),
            rec(id: 3, name: "My Show", startTime: 3000, season: 1, episode: 2),
            rec(id: 4, name: "Other Show", startTime: 4000, season: 2, episode: 5)
        ]
        let groups = vm.seriesGroups
        // Two groups (Movie has no series info)
        #expect(groups.count == 2)
        // Alphabetical by series name
        #expect(groups.map(\.seriesName) == ["My Show", "Other Show"])
        // "My Show" group sorted newest-first by start date
        #expect(groups[0].recordings.map(\.id) == [3, 2])
    }

    @Test("seriesGroups tie-breaker falls back to season/episode when start dates match")
    func seriesGroupsTieBreaker() {
        let vm = makeVM()
        vm.filter = .completed
        // Two episodes with the same startTime — sort should fall through
        // to season/episode comparison (higher season/episode first).
        vm.completedRecordings = [
            rec(id: 1, name: "Show", startTime: 1000, season: 1, episode: 1),
            rec(id: 2, name: "Show", startTime: 1000, season: 1, episode: 3),
            rec(id: 3, name: "Show", startTime: 1000, season: 2, episode: 1)
        ]
        let groups = vm.seriesGroups
        #expect(groups.count == 1)
        #expect(groups[0].recordings.map(\.id) == [3, 2, 1])
    }

    @Test("seriesGroups is empty when filter has no matching recordings")
    func seriesGroupsEmpty() {
        let vm = makeVM()
        vm.filter = .completed
        #expect(vm.seriesGroups.isEmpty)
    }

    // MARK: - recordingsSeriesSummaries

    @Test("recordingsSeriesSummaries aggregates across active, completed, and scheduled buckets")
    func summariesAcrossBuckets() {
        let vm = makeVM()
        vm.completedRecordings = [
            rec(id: 1, name: "Show", startTime: 1000, season: 1, episode: 1),
            rec(id: 2, name: "Show", startTime: 2000, season: 1, episode: 2)
        ]
        vm.activeRecordings = [
            rec(id: 3, name: "Show", startTime: 3000, status: "recording", season: 1, episode: 3)
        ]
        vm.scheduledRecordings = [
            rec(id: 4, name: "Show", startTime: 4000, status: "pending", season: 1, episode: 4)
        ]
        let summaries = vm.recordingsSeriesSummaries
        #expect(summaries.count == 1)
        let summary = summaries[0]
        #expect(summary.name == "Show")
        #expect(summary.completed.count == 2)
        #expect(summary.active.count == 1)
        #expect(summary.scheduled.count == 1)
    }

    @Test("recordingsSeriesSummaries excludes non-series recordings")
    func summariesExcludeStandalone() {
        let vm = makeVM()
        vm.completedRecordings = [
            rec(id: 1, name: "Solo Movie", startTime: 1000) // no season/episode → no series
        ]
        #expect(vm.recordingsSeriesSummaries.isEmpty)
    }

    @Test("recordingsSeriesSummaries picks the first seriesBannerURL it finds across buckets")
    func summariesBannerSelection() {
        let vm = makeVM()
        // Active bucket has a banner — completed doesn't. The summary builder
        // walks active + completed + scheduled and takes the first non-nil.
        vm.activeRecordings = [
            rec(id: 1, name: "Show", startTime: 1000, status: "recording",
                season: 1, episode: 1, seriesBannerURL: "http://banner")
        ]
        vm.completedRecordings = [
            rec(id: 2, name: "Show", startTime: 500, season: 1, episode: 2)
        ]
        let summaries = vm.recordingsSeriesSummaries
        #expect(summaries.first?.bannerURL == "http://banner")
    }

    @Test("seriesSummary(named:) looks up a series by name")
    func seriesSummaryLookup() {
        let vm = makeVM()
        vm.completedRecordings = [
            rec(id: 1, name: "My Show", startTime: 1000, season: 1, episode: 1)
        ]
        #expect(vm.seriesSummary(named: "My Show")?.name == "My Show")
        #expect(vm.seriesSummary(named: "Not Present") == nil)
    }

    @Test("recordingsSeriesSummaries sorts alphabetically, case-insensitive")
    func summariesSortedAlphabetically() {
        let vm = makeVM()
        vm.completedRecordings = [
            rec(id: 1, name: "zebra show", startTime: 1000, season: 1, episode: 1),
            rec(id: 2, name: "Apple Show", startTime: 2000, season: 1, episode: 1),
            rec(id: 3, name: "Banana Show", startTime: 3000, season: 1, episode: 1)
        ]
        let names = vm.recordingsSeriesSummaries.map(\.name)
        #expect(names == ["Apple Show", "Banana Show", "zebra show"])
    }
}
