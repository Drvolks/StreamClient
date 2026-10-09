//
//  VODDetailViewModelTests.swift
//  NexusPVRTests
//
//  A title's page (#17): loading a movie or a multi-season series, where to
//  pick a series up, and watch state kept on the device.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct VODDetailViewModelTests {

    private func scratchDefaults() -> UserDefaults {
        let suite = "VODDetailViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let seriesItem = VODItem(itemId: 7, uuid: "series-7", name: "Show", kind: .series)

    /// Two seasons of three episodes: s1e1…s1e3, s2e1…s2e3.
    private func makeSeriesProvider() -> FakeVODProvider {
        let provider = FakeVODProvider()
        let episodes = (1...2).flatMap { season in
            (1...3).map { episode in
                VODEpisode(
                    id: season * 10 + episode, uuid: "s\(season)e\(episode)", name: "Episode \(episode)",
                    seasonNumber: season, episodeNumber: episode, durationSecs: 1800
                )
            }
        }
        provider.seriesDetails[7] = VODSeriesDetail(id: 7, name: "Show", episodes: episodes)
        return provider
    }

    private func makeSeriesModel(
        seeded: [String: VODProgress] = [:],
        defaults: UserDefaults? = nil
    ) async -> VODDetailViewModel {
        let model = VODDetailViewModel(
            item: seriesItem,
            provider: makeSeriesProvider(),
            seededProgress: seeded,
            defaults: defaults ?? scratchDefaults()
        )
        await model.load()
        return model
    }

    private func watched(_ duration: Int = 1800) -> VODProgress {
        VODProgress(position: duration, duration: duration, updatedAt: Date())
    }

    // MARK: - Loading

    @Test("A movie loads its details")
    func loadsMovie() async {
        let provider = FakeVODProvider()
        provider.movieDetails[3] = VODMovieDetail(id: 3, uuid: "m3", name: "Heat", plot: "A heist.")
        let model = VODDetailViewModel(
            item: VODItem(itemId: 3, uuid: "m3", name: "Heat", kind: .movies),
            provider: provider,
            defaults: scratchDefaults()
        )
        await model.load()
        #expect(model.movie?.plot == "A heist.")
        #expect(model.series == nil)
        #expect(model.error == nil)
        #expect(model.isLoading == false)
    }

    @Test("A series loads its seasons and opens on the first")
    func loadsSeries() async {
        let model = await makeSeriesModel()
        #expect(model.seasons.map(\.number) == [1, 2])
        #expect(model.selectedSeasonNumber == 1)
        #expect(model.selectedSeason?.episodes.count == 3)
        #expect(model.nextEpisode?.uuid == "s1e1")
    }

    @Test("A failed load reports the error, and a retry recovers")
    func loadFailure() async {
        let provider = makeSeriesProvider()
        provider.nextError = PVRClientError.invalidResponse
        let model = VODDetailViewModel(item: seriesItem, provider: provider, defaults: scratchDefaults())
        await model.load()
        #expect(model.error != nil)
        #expect(model.seasons.isEmpty)
        await model.load()
        #expect(model.error == nil)
        #expect(model.seasons.count == 2)
    }

    // MARK: - Where to pick up

    @Test("A part-watched episode is the one to resume")
    func resumesPartWatched() async {
        let model = await makeSeriesModel(seeded: [
            "s1e1": watched(),
            "s1e2": VODProgress(position: 600, duration: 1800, updatedAt: Date()),
        ])
        #expect(model.nextEpisode?.uuid == "s1e2")
        #expect(model.resumePosition(for: "s1e2") == 600)
        #expect(model.resumePosition(for: "s1e1") == nil)
    }

    @Test("After a watched episode comes the next one, across seasons")
    func continuesIntoNextSeason() async {
        let model = await makeSeriesModel(seeded: ["s1e1": watched(), "s1e2": watched(), "s1e3": watched()])
        #expect(model.nextEpisode?.uuid == "s2e1")
        // The page opens on the season it will continue in.
        #expect(model.selectedSeasonNumber == 2)
        #expect(model.watchedCount(in: model.seasons[0]) == 3)
        #expect(model.watchedCount(in: model.seasons[1]) == 0)
    }

    @Test("A finished series starts over from the first episode")
    func finishedSeriesStartsOver() async {
        let all = Dictionary(uniqueKeysWithValues: ["s1e1", "s1e2", "s1e3", "s2e1", "s2e2", "s2e3"].map { ($0, watched()) })
        let model = await makeSeriesModel(seeded: all)
        #expect(model.nextEpisode?.uuid == "s1e1")
    }

    // MARK: - Watch state

    @Test("Positions saved on the device win over seeded ones")
    func savedProgressWins() async {
        let defaults = scratchDefaults()
        var store = VODProgressStore()
        store.record(uuid: "s1e1", position: 300, duration: 1800)
        store.save(to: defaults)
        let model = await makeSeriesModel(seeded: ["s1e1": watched()], defaults: defaults)
        #expect(model.watchState(for: "s1e1") == .resume(progress: 300.0 / 1800.0))
    }

    @Test("Marking watched and unwatched persists, and unwatching clears a seeded state too")
    func markWatchedAndUnwatched() async {
        let defaults = scratchDefaults()
        let model = await makeSeriesModel(seeded: ["s1e2": watched()], defaults: defaults)

        model.markWatched(uuid: "s1e1", durationSecs: 1800)
        #expect(model.watchState(for: "s1e1") == .watched)
        #expect(VODProgressStore.load(from: defaults)["s1e1"]?.isWatched == true)

        model.markUnwatched(uuid: "s1e1")
        model.markUnwatched(uuid: "s1e2")
        #expect(model.watchState(for: "s1e1") == .new)
        #expect(model.watchState(for: "s1e2") == .new)
        #expect(VODProgressStore.load(from: defaults).entries.isEmpty)
    }

    @Test("An item with no known runtime can still be marked watched")
    func markWatchedWithoutDuration() async {
        let model = await makeSeriesModel()
        model.markWatched(uuid: "s2e3", durationSecs: nil)
        #expect(model.watchState(for: "s2e3") == .watched)
    }

    @Test("Positions the player saved are picked up on reload")
    func reloadProgress() async {
        let defaults = scratchDefaults()
        let model = await makeSeriesModel(defaults: defaults)
        #expect(model.watchState(for: "s1e1") == .new)

        var store = VODProgressStore.load(from: defaults)
        store.record(uuid: "s1e1", position: 900, duration: 1800)
        store.save(to: defaults)
        model.reloadProgress()
        #expect(model.watchState(for: "s1e1") == .resume(progress: 0.5))
        #expect(model.nextEpisode?.uuid == "s1e1")
    }
}
