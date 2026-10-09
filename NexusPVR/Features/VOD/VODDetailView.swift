//
//  VODDetailView.swift
//  DispatcherPVR
//
//  The page of one On Demand title (#17), laid out like a recorded series:
//  the poster on its fanart, then for a movie what it is about, for a series
//  its seasons and episodes.
//

#if DISPATCHERPVR
import SwiftUI

struct VODDetailView: View {
    @ObservedObject var client: PVRClient
    @ObservedObject var appState: AppState
    @StateObject private var viewModel: VODDetailViewModel
    /// The part-watched episode waiting for "Resume" or "Watch from Beginning".
    @State private var resumeCandidate: VODPlayable?
    @State private var playError: String?
    #if os(tvOS)
    @FocusState private var isPrimaryActionFocused: Bool
    #endif

    init(item: VODItem, client: PVRClient, appState: AppState) {
        self.client = client
        self.appState = appState
        self._viewModel = StateObject(wrappedValue: VODDetailViewModel(
            item: item,
            provider: client,
            seededProgress: client.config.isDemoMode ? DemoVODLibrary.seededProgress : [:]
        ))
    }

    private var item: VODItem { viewModel.item }

    #if os(tvOS)
    private let horizontalPadding = Theme.spacingLG
    private let rowSpacing: CGFloat = 10
    private let bodyFont = Font.archivo(Theme.scaledFont(20))
    private let labelSize = Theme.scaledFont(13)
    #elseif os(macOS)
    private let horizontalPadding: CGFloat = 20
    private let rowSpacing: CGFloat = 0
    private let bodyFont = Font.archivo(13.5)
    private let labelSize: CGFloat = 9.5
    #else
    private let horizontalPadding: CGFloat = 16
    private let rowSpacing: CGFloat = 0
    private let bodyFont = Font.archivo(14)
    private let labelSize: CGFloat = 9.5
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: rowSpacing) {
                #if os(iOS)
                backButton
                #endif
                hero
                    .padding(.top, 14)
                actions
                    .padding(.top, 14)
                if let error = viewModel.error {
                    errorNote(error)
                }
                overview
                switch item.kind {
                case .movies: credits
                case .series: episodes
                }
                #if os(iOS)
                // Clears the floating bottom bar.
                Color.clear.frame(height: 96)
                #else
                Color.clear.frame(height: Theme.spacingLG)
                #endif
            }
            .padding(.horizontal, horizontalPadding)
        }
        .accessibilityIdentifier("vod-detail")
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vodProgressDidChange)) { _ in
            viewModel.reloadProgress()
        }
        .confirmationDialog(
            "Resume Playback",
            isPresented: Binding(get: { resumeCandidate != nil }, set: { if !$0 { resumeCandidate = nil } }),
            presenting: resumeCandidate
        ) { playable in
            Button("Resume") { play(playable) }
            Button("Watch from Beginning") { play(playable, fromBeginning: true) }
            Button("Cancel", role: .cancel) {}
        } message: { playable in
            if let position = viewModel.resumePosition(for: playable.uuid) {
                Text("\(playable.title)\nStopped at \(Self.clock(position))")
            }
        }
        .alert("Error", isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
            Button("OK") { playError = nil }
        } message: {
            Text(playError ?? "")
        }
        #if os(tvOS)
        .onAppear {
            DispatchQueue.main.async { isPrimaryActionFocused = true }
        }
        #endif
    }

    // MARK: - Hero

    private var hero: some View {
        PosterHero(
            posterURL: client.vodImageURL(
                viewModel.movie?.cover ?? viewModel.series?.cover?.preferredURLString ?? item.logo?.preferredURLString
            ),
            fanartURL: client.vodImageURL(viewModel.movie?.backdrops.first ?? viewModel.series?.backdrops.first)
        ) { scale in
            HStack(alignment: .top, spacing: 26 * scale) {
                ForEach(facts, id: \.label) { fact in
                    PosterHeroFact(label: fact.label, value: fact.value, scale: scale)
                }
            }
            if let tagline {
                Text(tagline)
                    .midnightMeta(12.5 * scale, weight: .semibold)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(2)
            }
        }
    }

    private var facts: [(label: String, value: String)] {
        var facts: [(label: String, value: String)] = []
        switch item.kind {
        case .movies:
            if let year = viewModel.movie?.year ?? item.year { facts.append(("Year", String(year))) }
            if let seconds = viewModel.movie?.durationSecs ?? item.durationSecs {
                facts.append(("Runtime", formatDuration(seconds)))
            }
            if let rating = viewModel.movie?.rating ?? item.rating { facts.append(("Rating", rating)) }
        case .series:
            if let series = viewModel.series, !series.seasons.isEmpty {
                facts.append(("Season\(series.seasons.count == 1 ? "" : "s")", String(series.seasons.count)))
                facts.append(("Episodes", String(series.episodeCount)))
            } else if let count = item.episodeCount, count > 0 {
                facts.append(("Episodes", String(count)))
            }
            if let year = viewModel.series?.year ?? item.year { facts.append(("Year", String(year))) }
        }
        return facts
    }

    /// Under the figures: the genre, led by a series' rating (a movie's
    /// rating is one of the figures).
    private var tagline: String? {
        var parts: [String] = []
        if item.kind == .series, let rating = viewModel.series?.rating ?? item.rating { parts.append(rating) }
        if let genre = viewModel.movie?.genre ?? viewModel.series?.genre ?? item.genre { parts.append(genre) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Actions

    /// What the main button plays: the movie, or the episode to pick the
    /// series up at.
    private var primaryPlayable: VODPlayable? {
        switch item.kind {
        case .movies:
            return .movie(uuid: viewModel.movie?.uuid ?? item.uuid, name: item.name)
        case .series:
            return viewModel.nextEpisode.map { .episode($0, seriesName: item.name) }
        }
    }

    private var primaryTitle: String {
        guard let playable = primaryPlayable else { return "Play" }
        let verb = viewModel.resumePosition(for: playable.uuid) != nil ? "Resume" : "Play"
        guard item.kind == .series, let code = viewModel.nextEpisode?.code else { return verb }
        return "\(verb) \(code)"
    }

    @ViewBuilder
    private var actions: some View {
        if let playable = primaryPlayable {
            let state = viewModel.watchState(for: playable.uuid)
            HStack(spacing: 10) {
                actionButton(primaryTitle, systemImage: "play.fill", isPrimary: true) {
                    play(playable)
                }
                .accessibilityIdentifier("vod-play-button")
                #if os(tvOS)
                .focused($isPrimaryActionFocused)
                #endif

                if item.kind == .movies, state != .new {
                    actionButton("Start over", systemImage: "gobackward", isPrimary: false) {
                        play(playable, fromBeginning: true)
                    }
                }
                if let remaining = remainingText(for: playable.uuid) {
                    Text(remaining)
                        .midnightMeta(labelSize + 2)
                        .foregroundStyle(MidnightPalette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        #if os(tvOS)
        Button(action: action) {
            TVMidnightOutlineLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(TVMidnightButtonStyle(focusScale: 1.04))
        #else
        if isPrimary {
            Button(action: action) {
                Label(title, systemImage: systemImage).textCase(.uppercase)
            }
            .buttonStyle(MidnightFieldButtonStyle())
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage).textCase(.uppercase)
            }
            .buttonStyle(MidnightOutlineButtonStyle())
        }
        #endif
    }

    /// "42 min left" beside a part-watched title.
    private func remainingText(for uuid: String) -> String? {
        guard let progress = viewModel.progress(for: uuid), progress.hasResumePosition else { return nil }
        let minutes = max((progress.duration - progress.position) / 60, 1)
        return "\(minutes) min left"
    }

    // MARK: - Overview

    @ViewBuilder
    private var overview: some View {
        if let text = viewModel.movie?.plot ?? viewModel.series?.description ?? item.description {
            MidnightSectionHeader(title: "Overview", meta: "")
            Text(text)
                .font(bodyFont)
                .foregroundStyle(MidnightPalette.inkSoft)
                .lineSpacing(3)
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.top, 10)
                .accessibilityIdentifier("vod-overview")
        }
    }

    @ViewBuilder
    private var credits: some View {
        if let movie = viewModel.movie {
            let rows = [
                ("Director", movie.director),
                ("Cast", movie.actors),
                ("Country", movie.country)
            ].compactMap { label, value in value.map { (label: label, value: $0) } }
            if !rows.isEmpty {
                MidnightSectionHeader(title: "Credits", meta: "")
                ForEach(rows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.label)
                            .midnightKicker(labelSize)
                            .foregroundStyle(MidnightPalette.accent)
                        Text(row.value)
                            .font(bodyFont)
                            .foregroundStyle(MidnightPalette.ink)
                    }
                    .padding(.top, 10)
                }
            }
        } else if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacingLG)
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private var episodes: some View {
        if viewModel.series == nil {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacingLG)
            }
        } else if viewModel.seasons.isEmpty {
            // The server fetches a series' episodes from the provider the
            // first time it is opened; that can still be under way.
            VStack(alignment: .leading, spacing: 10) {
                Text("No episodes yet. The server may still be fetching them from the provider.")
                    .font(bodyFont)
                    .foregroundStyle(MidnightPalette.inkSoft)
                actionButton("Check again", systemImage: "arrow.clockwise", isPrimary: false) {
                    Task { await viewModel.load() }
                }
            }
            .padding(.top, Theme.spacingMD)
            .accessibilityIdentifier("vod-episodes-empty")
        } else {
            if viewModel.seasons.count > 1 {
                VODSeasonPicker(seasons: viewModel.seasons, selection: $viewModel.selectedSeasonNumber)
                    .padding(.top, 16)
            }
            if let season = viewModel.selectedSeason {
                MidnightSectionHeader(title: season.title, meta: seasonMeta(season))
                ForEach(season.episodes) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private func seasonMeta(_ season: VODSeason) -> String {
        let count = "\(season.episodes.count) episode\(season.episodes.count == 1 ? "" : "s")"
        let watched = viewModel.watchedCount(in: season)
        return watched > 0 ? "\(count) · \(watched) watched" : count
    }

    private func episodeRow(_ episode: VODEpisode) -> some View {
        let state = viewModel.watchState(for: episode.uuid)
        let playable = VODPlayable.episode(episode, seriesName: item.name)
        let isUpNext = episode.id == viewModel.nextEpisode?.id
        return Button {
            if viewModel.resumePosition(for: episode.uuid) != nil {
                resumeCandidate = playable
            } else {
                play(playable, fromBeginning: true)
            }
        } label: {
            #if os(tvOS)
            TVVODEpisodeRow(episode: episode, watchState: state, isUpNext: isUpNext)
            #else
            VODEpisodeRow(episode: episode, watchState: state, isUpNext: isUpNext)
            #endif
        }
        #if os(tvOS)
        .buttonStyle(TVMidnightButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .contextMenu {
            if state != .new {
                Button {
                    play(playable, fromBeginning: true)
                } label: {
                    Label("Watch from Beginning", systemImage: "arrow.counterclockwise")
                }
            }
            if state == .watched {
                Button {
                    viewModel.markUnwatched(uuid: episode.uuid)
                } label: {
                    Label("Mark as Unwatched", systemImage: "circle")
                }
            } else {
                Button {
                    viewModel.markWatched(uuid: episode.uuid, durationSecs: episode.durationSecs)
                } label: {
                    Label("Mark as Watched", systemImage: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - Pieces

    #if os(iOS)
    private var backButton: some View {
        Button {
            appState.selectedVODItem = nil
        } label: {
            Label("All \(item.kind.title.lowercased())", systemImage: "chevron.left")
                .font(.archivo(12.5, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vod-back-button")
        .padding(.top, 10)
    }
    #endif

    private func errorNote(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(bodyFont)
                .foregroundStyle(Theme.warning)
            actionButton("Try again", systemImage: "arrow.clockwise", isPrimary: false) {
                Task { await viewModel.load() }
            }
        }
        .padding(.top, Theme.spacingMD)
        .accessibilityIdentifier("vod-detail-error")
    }

    private func play(_ playable: VODPlayable, fromBeginning: Bool = false) {
        do {
            let url = try playable.isEpisode
                ? client.vodEpisodeStreamURL(uuid: playable.uuid)
                : client.vodMovieStreamURL(uuid: playable.uuid)
            // The demo clip is shorter than the positions the demo library
            // pretends to have saved.
            let resume = fromBeginning || client.config.isDemoMode ? nil : viewModel.resumePosition(for: playable.uuid)
            appState.playStream(url: url, title: playable.title, resumePosition: resume, vodId: playable.uuid)
        } catch {
            playError = error.localizedDescription
        }
    }

    /// "1:05:09" or "5:09".
    private static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
#endif
