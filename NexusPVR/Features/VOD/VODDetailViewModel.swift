//
//  VODDetailViewModel.swift
//  DispatcherPVR
//
//  One On Demand title: a movie's details, or a series with its seasons
//  and episodes, plus what has been watched on this device (#17)
//

import Foundation
import Combine

@MainActor
final class VODDetailViewModel: ObservableObject {
    let item: VODItem

    @Published private(set) var movie: VODMovieDetail?
    @Published private(set) var series: VODSeriesDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    /// The season whose episodes are listed.
    @Published var selectedSeasonNumber: Int?
    @Published private(set) var progressStore: VODProgressStore

    private let provider: any VODProviding
    private let defaults: UserDefaults
    /// Demo watch state shown under whatever the device has saved.
    private var seededProgress: [String: VODProgress]

    init(
        item: VODItem,
        provider: any VODProviding,
        seededProgress: [String: VODProgress] = [:],
        defaults: UserDefaults = .standard
    ) {
        self.item = item
        self.provider = provider
        self.seededProgress = seededProgress
        self.defaults = defaults
        self.progressStore = VODProgressStore.load(from: defaults)
    }

    // MARK: - Loading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            switch item.kind {
            case .movies:
                movie = try await provider.getVODMovieDetail(id: item.itemId)
            case .series:
                let detail = try await provider.getVODSeriesDetail(id: item.itemId)
                series = detail
                if selectedSeason == nil {
                    selectedSeasonNumber = nextEpisode.map { max($0.seasonNumber ?? 0, 0) } ?? detail.seasons.first?.number
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Series

    var seasons: [VODSeason] { series?.seasons ?? [] }

    var selectedSeason: VODSeason? {
        seasons.first { $0.number == selectedSeasonNumber }
    }

    /// Where to pick the series up: the episode left part-way, else the one
    /// after the last watched, else the first.
    var nextEpisode: VODEpisode? {
        let episodes = series?.allEpisodes ?? []
        guard let lastTouched = episodes.lastIndex(where: { watchState(for: $0.uuid) != .new }) else {
            return episodes.first
        }
        if watchState(for: episodes[lastTouched].uuid) == .watched {
            return lastTouched + 1 < episodes.count ? episodes[lastTouched + 1] : episodes.first
        }
        return episodes[lastTouched]
    }

    /// Episodes of `season` that have been watched to the end.
    func watchedCount(in season: VODSeason) -> Int {
        season.episodes.filter { watchState(for: $0.uuid) == .watched }.count
    }

    // MARK: - Watch state

    func progress(for uuid: String) -> VODProgress? {
        progressStore[uuid] ?? seededProgress[uuid]
    }

    func watchState(for uuid: String) -> RecordingWatchState {
        progress(for: uuid)?.watchState ?? .new
    }

    /// Seconds to resume from, when the item was left part-way.
    func resumePosition(for uuid: String) -> Int? {
        guard let progress = progress(for: uuid), progress.hasResumePosition else { return nil }
        return progress.position
    }

    /// Picks up positions the player saved while this page was covered.
    func reloadProgress() {
        progressStore = VODProgressStore.load(from: defaults)
    }

    func markWatched(uuid: String, durationSecs: Int?) {
        let duration = max(durationSecs ?? progress(for: uuid)?.duration ?? 0, 60)
        progressStore.record(uuid: uuid, position: duration, duration: duration)
        progressStore.save(to: defaults)
    }

    func markUnwatched(uuid: String) {
        seededProgress.removeValue(forKey: uuid)
        progressStore.clear(uuid: uuid)
        progressStore.save(to: defaults)
    }
}
