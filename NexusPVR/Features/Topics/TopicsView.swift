//
//  TopicsView.swift
//  nextpvr-apple-client
//
//  Shows upcoming programs matching user's topic keywords
//

import SwiftUI

struct TopicsView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var epgCache: EPGCache
    @StateObject private var viewModel = TopicsViewModel()
    @State private var selectedProgramDetail: ProgramTopicDetail?
    @State private var refreshTrigger = UUID()
    @State private var selectedKeyword: String = ""
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS) || os(tvOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif
    #if os(macOS)
    @State private var streamError: String?
    #endif
    #if os(tvOS)
    @Environment(\.requestSidebarFocus) private var requestSidebarFocus
    #endif

    private var filteredPrograms: [MatchingProgram] {
        let nonScheduled = viewModel.matchingPrograms.filter { $0.matchedKeyword != MatchingProgram.scheduledKeyword }
        #if os(tvOS)
        let keyword = appState.selectedTopicKeyword
        guard !keyword.isEmpty else { return nonScheduled }
        return nonScheduled.filter { $0.matchedKeyword == keyword }
        #else
        guard !selectedKeyword.isEmpty else { return nonScheduled }
        return nonScheduled.filter { $0.matchedKeyword == selectedKeyword }
        #endif
    }

    #if os(iOS)
    private func updateKeywordsWithMatches() {
        var counts: [String: Int] = [:]
        for program in viewModel.matchingPrograms where program.matchedKeyword != MatchingProgram.scheduledKeyword {
            counts[program.matchedKeyword, default: 0] += 1
        }
        appState.topicKeywordMatchCounts = counts
    }
    #endif

    private func syncTopicSelection(with keywords: [String], preferFirst: Bool = false) {
        appState.topicKeywords = keywords

        guard let first = keywords.first else {
            selectedKeyword = ""
            appState.selectedTopicKeyword = ""
            return
        }

        let selection = appState.selectedTopicKeyword
        let resolved = preferFirst ? first : (keywords.contains(selection) && !selection.isEmpty ? selection : first)

        if selectedKeyword != resolved {
            selectedKeyword = resolved
        }
        if appState.selectedTopicKeyword != resolved {
            appState.selectedTopicKeyword = resolved
        }
    }

    var body: some View {
        Group {
            #if os(tvOS)
            NavigationView {
                topicsContent
            }
            #elseif os(macOS)
            topicsContent
            #else
            NavigationStack {
                topicsContent
            }
            #endif
        }
        #if os(tvOS)
        .background(MidnightGradients.ground(colorScheme))
        .onMoveCommand { direction in
            if direction == .left { requestSidebarFocus() }
        }
        .onExitCommand {
            requestSidebarFocus()
        }
        #elseif os(macOS)
        .background(MidnightGradients.ground(colorScheme))
        .alert("Error", isPresented: Binding(get: { streamError != nil }, set: { if !$0 { streamError = nil } })) {
            Button("OK") { streamError = nil }
        } message: {
            if let streamError { Text(streamError) }
        }
        #else
        .background(Theme.background)
        #endif
        #if os(macOS)
        .onChange(of: appState.showingCalendar) { _ in
            if appState.showingCalendar {
                viewModel.epgCache = epgCache
                viewModel.client = client
                Task { await viewModel.loadData() }
            }
        }
        .sheet(isPresented: $appState.showingCalendar) {
            CalendarView(programs: viewModel.matchingPrograms)
                .environmentObject(client)
                .environmentObject(appState)
                .frame(minWidth: 700, minHeight: 500)
        }
        #endif
        .task {
            viewModel.epgCache = epgCache
            viewModel.client = client
            await viewModel.loadData()
            #if os(iOS)
            let hasValidSelection = !appState.selectedTopicKeyword.isEmpty &&
                viewModel.keywords.contains(appState.selectedTopicKeyword)
            syncTopicSelection(with: viewModel.keywords, preferFirst: !hasValidSelection)
            updateKeywordsWithMatches()
            #elseif !os(tvOS)
            syncTopicSelection(with: viewModel.keywords)
            #else
            appState.topicKeywords = viewModel.keywords
            if appState.selectedTopicKeyword.isEmpty || !viewModel.keywords.contains(appState.selectedTopicKeyword) {
                appState.selectedTopicKeyword = viewModel.keywords.first ?? ""
            }
            #endif
        }
        #if os(iOS)
        .onAppear {
            // Only sync if keywords are already loaded; otherwise .task will handle it
            guard !viewModel.keywords.isEmpty else { return }
            let hasValidSelection = !appState.selectedTopicKeyword.isEmpty &&
                viewModel.keywords.contains(appState.selectedTopicKeyword)
            syncTopicSelection(with: viewModel.keywords, preferFirst: !hasValidSelection)
        }
        #endif
        #if !os(tvOS)
        .onChange(of: appState.selectedTopicKeyword) { _ in
            if selectedKeyword != appState.selectedTopicKeyword {
                selectedKeyword = appState.selectedTopicKeyword
            }
        }
        #endif
        .onChange(of: scenePhase) { _ in
            if scenePhase == .active {
                Task {
                    await viewModel.loadData()
                    #if os(iOS)
                    updateKeywordsWithMatches()
                    #endif
                }
            }
        }
        // Opened before the EPG finished loading: `loadData` found nothing
        // to match against, so match again once it has.
        .onChange(of: epgCache.hasLoaded) { _ in
            guard epgCache.hasLoaded else { return }
            Task {
                await viewModel.loadData()
                #if os(iOS)
                updateKeywordsWithMatches()
                #endif
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingsDidChange)) { _ in
            Task {
                await viewModel.loadData()
                #if os(iOS)
                updateKeywordsWithMatches()
                #endif
            }
        }
        #if os(iOS)
        .onChange(of: appState.selectedTab) { _ in
            guard appState.selectedTab == .topics else { return }
            let hasValidSelection = !appState.selectedTopicKeyword.isEmpty &&
                viewModel.keywords.contains(appState.selectedTopicKeyword)
            syncTopicSelection(with: viewModel.keywords, preferFirst: !hasValidSelection)
        }
        #endif
    }

    @ViewBuilder
    private var topicsContent: some View {
        VStack(spacing: 0) {
            // macOS topic selection is driven by the sidebar sub-rows.
            #if os(macOS)
            MacTopicsHeader(
                title: selectedKeyword.isEmpty ? "Topics" : selectedKeyword,
                programCount: filteredPrograms.count
            )
            #elseif os(tvOS)
            TVPageHeader(
                kicker: "Topics",
                title: appState.selectedTopicKeyword.isEmpty ? "Topics" : appState.selectedTopicKeyword,
                readout: "\(filteredPrograms.count) program\(filteredPrograms.count == 1 ? "" : "s")"
            )
            #endif

            // Content
            Group {
                contentView
            }
            .accessibilityIdentifier("topics-view")
            #if os(iOS)
            .sidebarMenuToolbar()
            .navigationTitle(appState.selectedTopicKeyword.isEmpty ? "Topics" : appState.selectedTopicKeyword)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(item: $selectedProgramDetail) { detail in
                ProgramDetailView(
                    program: detail.program,
                    channel: detail.channel,
                    initialRecordingId: detail.recordingId,
                    initialCompletedRecording: detail.completedRecording,
                    onRecordingChanged: {
                        refreshTrigger = UUID()
                    }
                )
                .environmentObject(client)
                .environmentObject(appState)
            }
            .onChange(of: viewModel.keywords) { _ in
                #if os(tvOS)
                appState.topicKeywords = viewModel.keywords
                if appState.selectedTopicKeyword.isEmpty || !viewModel.keywords.contains(appState.selectedTopicKeyword) {
                    appState.selectedTopicKeyword = viewModel.keywords.first ?? ""
                }
                #else
                syncTopicSelection(with: viewModel.keywords)
                #endif
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        #if os(tvOS)
        if viewModel.isLoading && viewModel.matchingPrograms.isEmpty {
            loadingView
        } else if let error = viewModel.error {
            errorView(error)
        } else if filteredPrograms.isEmpty {
            noMatchesView
        } else {
            programsList
        }
        #else
        if viewModel.isLoading && viewModel.matchingPrograms.isEmpty {
            loadingView
        } else if let error = viewModel.error {
            errorView(error)
        } else if filteredPrograms.isEmpty {
            noMatchesView
        } else {
            programsList
        }
        #endif
    }

    private var loadingView: some View {
        VStack(spacing: Theme.spacingMD) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.accent)
            Text("Finding matching programs...")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.warning)
            Text("Unable to load programs")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesView: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text("No Matching Programs")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            #if os(tvOS)
            Text("No upcoming programs match: \(appState.selectedTopicKeyword.isEmpty ? viewModel.keywords.joined(separator: ", ") : appState.selectedTopicKeyword)")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            #else
            Text("No upcoming programs match: \(appState.selectedTopicKeyword.isEmpty ? viewModel.keywords.joined(separator: ", ") : appState.selectedTopicKeyword)")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tvOSFocusableEmptyState()
        .accessibilityIdentifier("topics-empty")
    }

    private var programsList: some View {
        #if os(tvOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(TopicDaySection.grouped(filteredPrograms)) { section in
                    MidnightSectionHeader(
                        title: section.title,
                        meta: "\(section.programs.count) program\(section.programs.count == 1 ? "" : "s")"
                    )
                    ForEach(section.programs) { item in
                        TVTopicProgramRow(
                            program: item.program,
                            channel: item.channel,
                            onRecordingChanged: { refreshTrigger = UUID() },
                            onShowDetails: {
                                selectedProgramDetail = ProgramTopicDetail(program: item.program, channel: item.channel)
                            }
                        )
                        .id("\(item.id)-\(refreshTrigger)")
                    }
                }
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingMD)
        }
        #elseif os(macOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(TopicDaySection.grouped(filteredPrograms)) { section in
                    MidnightSectionHeader(
                        title: section.title,
                        meta: "\(section.programs.count) program\(section.programs.count == 1 ? "" : "s")"
                    )
                    ForEach(section.programs) { item in
                        MacTopicProgramRow(
                            program: item.program,
                            channel: item.channel,
                            onWatch: { playLive(item.channel, program: item.program) },
                            onRecordingChanged: { refreshTrigger = UUID() },
                            onShowDetails: { recordingId, completedRecording in
                                selectedProgramDetail = ProgramTopicDetail(
                                    program: item.program,
                                    channel: item.channel,
                                    recordingId: recordingId,
                                    completedRecording: completedRecording
                                )
                            }
                        )
                        .id("\(item.id)-\(refreshTrigger)")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Theme.spacingLG)
        }
        #else
        List {
            ForEach(filteredPrograms) { item in
                TopicProgramRow(
                    program: item.program,
                    channel: item.channel,
                    matchedKeyword: item.matchedKeyword,
                    onRecordingChanged: {
                        refreshTrigger = UUID()
                    },
                    onShowDetails: { recordingId, completedRecording in
                        selectedProgramDetail = ProgramTopicDetail(
                            program: item.program,
                            channel: item.channel,
                            recordingId: recordingId,
                            completedRecording: completedRecording
                        )
                    }
                )
                .contentShape(Rectangle())
                .listRowBackground(Theme.surface)
                .id("\(item.id)-\(refreshTrigger)")
            }
            #if os(iOS)
            Color.clear
                .frame(height: 96)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            #endif
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadData()
        }
        #endif
    }

    #if os(macOS)
    private func playLive(_ channel: Channel, program: Program) {
        Task {
            do {
                let url = try await appState.preparingStream {
                    try await client.liveStreamURL(channelId: channel.id)
                }
                appState.playStream(url: url, title: "\(channel.name) - \(program.name)", channelId: channel.id, channelName: channel.name)
            } catch {
                streamError = error.localizedDescription
            }
        }
    }
    #endif

}

// Helper struct for sheet binding
struct ProgramTopicDetail: Identifiable {
    var id: String { "\(program.id)-\(channel.id)" }
    let program: Program
    let channel: Channel
    var recordingId: Int? = nil
    var completedRecording: Recording? = nil
}

#Preview {
    TopicsView()
        .environmentObject(PVRClient())
        .environmentObject(AppState())
        .environmentObject(EPGCache())
        .preferredColorScheme(.dark)
}
