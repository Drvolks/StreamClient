//
//  GuideView.swift
//  nextpvr-apple-client
//
//  EPG grid view
//

import SwiftUI
#if os(iOS) || os(tvOS)
import UIKit
#endif


struct GuideView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var epgCache: EPGCache
    #if os(tvOS)
    @Environment(\.requestSidebarFocus) private var requestSidebarFocus
    #endif
    #if os(iOS) || os(macOS)
    @EnvironmentObject var viewModel: GuideViewModel
    #else
    @StateObject private var viewModel = GuideViewModel()
    #endif

    #if os(tvOS)
    /// Callback to request focus move to nav bar (called when pressing up at top row)
    var onRequestNavBarFocus: (() -> Void)? = nil
    #endif

    @State private var selectedProgramDetail: (program: Program, channel: Channel)?
    @State private var streamError: String?
    /// Captured when the player is presented, before `stopPlayback()` clears
    /// its catch-up session id. While true, automatic "back to now" hooks must
    /// leave the guide's selected day and horizontal position untouched.
    @State private var preservesGuidePositionAfterCatchup = false

    // Keywords for pre-computing matches
    @State private var keywords: [String] = []

    #if !os(tvOS)
    @StateObject private var calendarViewModel = TopicsViewModel()
    #endif

    #if os(macOS)
    // Midnight guide: 5pt per minute, so a half-hour cell (150pt) clears the
    // width at which times keep AM/PM and badges show; a logo-first channel
    // column.
    private let hourWidth: CGFloat = 300
    private let channelWidth: CGFloat = 194
    private let rowHeight: CGFloat = 58
    /// The program shown in the detail bar under the grid.
    @State private var macSelection: ProgramDetail?
    @Environment(\.colorScheme) private var colorScheme
    #else
    private let hourWidth: CGFloat = Theme.hourColumnWidth
    private let channelWidth: CGFloat = Theme.channelColumnWidth
    private let rowHeight: CGFloat = Theme.cellHeight
    #endif
    #if os(tvOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif

    private var hasFilterData: Bool {
        !epgCache.channelProfiles.isEmpty || hasPopulatedGroups
    }

    private var hasPopulatedGroups: Bool {
        epgCache.hasPopulatedChannelGroups
    }

    /// Groups the filter surfaces offer — empty groups are hidden, since
    /// picking one would leave the guide blank.
    private var populatedGroups: [ChannelGroup] {
        epgCache.populatedChannelGroups
    }

    var body: some View {
        // The modifier chain is split across small generic helpers so the Swift
        // type checker doesn't have to solve one enormous expression.
        lifecycleHandlers(filterHandlers(presentationLayer(contentView)))
    }

    private func presentationLayer<Content: View>(_ content: Content) -> some View {
        content
            .accessibilityIdentifier("guide-view")
            #if os(macOS) || os(tvOS)
            .background(MidnightGradients.ground(colorScheme))
            #else
            .background(.ultraThinMaterial)
            #endif
            .sheet(item: programDetailBinding, onDismiss: onDismissDetail) { detail in
                programDetailSheet(detail)
            }
            .alert("Error", isPresented: .constant(streamError != nil)) {
                Button("OK") { streamError = nil }
            } message: {
                streamErrorMessage
            }
            #if os(macOS)
            .onChange(of: appState.showingCalendar) {
                if appState.showingCalendar {
                    calendarViewModel.epgCache = epgCache
                    calendarViewModel.client = client
                    Task { await calendarViewModel.loadData() }
                }
            }
            .sheet(isPresented: $appState.showingCalendar) {
                CalendarView(programs: calendarViewModel.matchingPrograms)
                    .environmentObject(client)
                    .environmentObject(appState)
                    .frame(minWidth: 700, minHeight: 500)
            }
            #endif
    }

    private func filterHandlers<Content: View>(_ content: Content) -> some View {
        content
            .task {
                keywords = UserPreferences.load().keywords
                await viewModel.loadData(using: client, epgCache: epgCache)
                viewModel.updateKeywordMatches(keywords: keywords)
                if !appState.guideChannelFilter.isEmpty {
                    viewModel.channelSearchText = appState.guideChannelFilter
                }
                if let groupId = appState.guideGroupFilter {
                    viewModel.selectedGroupId = groupId
                }
                if let profileId = appState.guideProfileFilter {
                    viewModel.selectedProfileId = profileId
                }
            }
            .onChange(of: viewModel.channelSearchText) {
                Task { viewModel.updateKeywordMatches(keywords: keywords) }
            }
            .onChange(of: epgCache.isFullyLoaded) {
                Task { viewModel.updateKeywordMatches(keywords: keywords) }
                if epgCache.isFullyLoaded {
                    viewModel.clampSelectedDateToAvailableEPG()
                }
            }
            .onChange(of: epgCache.earliestEPGDate) { _, earliestEPGDate in
                guard earliestEPGDate != nil, epgCache.isFullyLoaded else { return }
                viewModel.clampSelectedDateToAvailableEPG()
            }
            .onChange(of: appState.guideChannelFilter) {
                Task { viewModel.channelSearchText = appState.guideChannelFilter }
            }
            .onChange(of: appState.guideGroupFilter) {
                let newGroup = appState.guideGroupFilter
                Task {
                    viewModel.selectedGroupId = newGroup
                    if newGroup != nil {
                        viewModel.selectedProfileId = nil
                    }
                }
            }
            .onChange(of: appState.guideProfileFilter) {
                Task { viewModel.selectedProfileId = appState.guideProfileFilter }
            }
            .onChange(of: viewModel.selectedGroupId) { _, groupId in
                if groupId != nil {
                    viewModel.selectedProfileId = nil
                    appState.guideProfileFilter = nil
                }
                appState.guideGroupFilter = groupId
            }
            #if DISPATCHERPVR
            .onChange(of: viewModel.selectedProfileId) { _, profileId in
                Task {
                    await epgCache.reloadData(using: client, profileId: profileId)
                    viewModel.showChannelSearch = epgCache.channels.count > 25
                    viewModel.updateKeywordMatches(keywords: keywords)
                    if profileId != nil {
                        viewModel.selectedGroupId = nil
                        appState.guideGroupFilter = nil
                    }
                    appState.guideProfileFilter = profileId
                }
            }
            #endif
    }

    private func lifecycleHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: scenePhase) {
                handleScenePhaseChange()
            }
            .onChange(of: appState.isShowingPlayer) { _, isShowing in
                handlePlayerPresentationChange(isShowing: isShowing)
            }
    }

    private func handleScenePhaseChange() {
        guard scenePhase == .active else { return }
        #if os(tvOS)
        // Re-fetch a stale EPG under the same rules as the Channels page
        // (#166); the full refresh reloads recordings too.
        if epgCache.shouldRefreshOnActivation(using: client) {
            Task { await refreshGuide() }
        } else {
            Task { await refreshRecordings() }
        }
        // Resync the guide start time so the visible window matches
        // the ViewModel's timelineStart (which uses current time),
        // unless returning to the catch-up program the user chose.
        if !preservesGuidePositionAfterCatchup {
            resyncGuideStartToNow()
        }
        #else
        Task { await refreshRecordings() }
        #endif
    }

    private func handlePlayerPresentationChange(isShowing: Bool) {
        if isShowing {
            // Capture this before PlayerView teardown calls
            // stopPlayback(), which clears the session id.
            preservesGuidePositionAfterCatchup = appState.currentlyPlayingCatchupSessionId != nil
            return
        }

        #if os(tvOS)
        // The player is presented as a .fullScreenCover, which keeps
        // scenePhase == .active, so the scenePhase resync never fires on
        // dismissal. Re-anchor normal playback on "now", but keep the
        // exact day/time/focus window that launched catch-up playback.
        if !preservesGuidePositionAfterCatchup {
            resyncGuideStartToNow()
            viewModel.scrollToNow()
        }
        Task { await refreshRecordings() }
        #endif
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var rootLeadingSafeArea: CGFloat = 0
    @State private var rootTopSafeArea: CGFloat = 0

    private var contentView: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            macOSGuideHeader
            if viewModel.showFilters && hasFilterData {
                filterPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            #endif
            Group {
                if let error = epgCache.error {
                    errorView(error)
                } else if !epgCache.isFullyLoaded {
                    loadingView
                } else if let error = viewModel.error, viewModel.channels.isEmpty {
                    errorView(error)
                } else if viewModel.hasLoaded && viewModel.channels.isEmpty {
                    emptyView
                } else {
                    guideContent
                }
            }
            .frame(maxHeight: .infinity)
            #if os(macOS)
            macOSDetailBar
            #endif
        }
        #if os(iOS)
        .overlay(alignment: .top) {
            if viewModel.showFilters && hasFilterData {
                filterPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #endif
        .background(GeometryReader { geo in
            Color.clear
                .onAppear {
                    rootLeadingSafeArea = geo.safeAreaInsets.leading
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom != .phone {
                        rootTopSafeArea = geo.safeAreaInsets.top
                    }
                    #else
                    rootTopSafeArea = geo.safeAreaInsets.top
                    #endif
                }
                .onChange(of: geo.safeAreaInsets.leading) { _, new in
                    rootLeadingSafeArea = new
                }
                .onChange(of: geo.safeAreaInsets.top) { _, new in
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom != .phone {
                        rootTopSafeArea = new
                    }
                    #else
                    rootTopSafeArea = new
                    #endif
                }
        })
        #if os(iOS)
        .onAppear {
            schedulePhoneSafeAreaRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            schedulePhoneSafeAreaRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            schedulePhoneSafeAreaRefresh()
        }
        .onChange(of: horizontalSizeClass) {
            schedulePhoneSafeAreaRefresh()
        }
        .onChange(of: verticalSizeClass) {
            schedulePhoneSafeAreaRefresh()
        }
        #endif
        #if os(iOS)
        .safeAreaPadding(.top, 0)
        #endif
    }

    private var programDetailBinding: Binding<ProgramDetail?> {
        Binding(
            get: { selectedProgramDetail.map { ProgramDetail(program: $0.program, channel: $0.channel) } },
            set: { selectedProgramDetail = $0.map { ($0.program, $0.channel) } }
        )
    }

    private func programDetailSheet(_ detail: ProgramDetail) -> some View {
        ProgramDetailView(
            program: detail.program,
            channel: detail.channel,
            catchupGuideReturnTime: detail.program.startDate,
            initialRecordingId: viewModel.recordingId(for: detail.program)
        )
        .environmentObject(client)
        .environmentObject(appState)
    }

    private func onDismissDetail() {
        Task {
            await refreshRecordings()
        }
    }

    @ViewBuilder
    private var streamErrorMessage: some View {
        if let error = streamError {
            Text(error)
        }
    }

    private func playLiveChannel(_ channel: Channel) {
        Task {
            do {
                let url = try await appState.preparingStream {
                    try await client.liveStreamURL(channelId: channel.id)
                }
                appState.playStream(url: url, title: channel.name, channelId: channel.id, channelName: channel.name)
            } catch {
                streamError = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    private func schedulePhoneSafeAreaRefresh() {
        // Rotation can report stale insets for a short window. Refresh a few times.
        refreshPhoneSafeAreasFromWindow()
        DispatchQueue.main.async {
            refreshPhoneSafeAreasFromWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            refreshPhoneSafeAreasFromWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            refreshPhoneSafeAreasFromWindow()
        }
    }

    private func refreshPhoneSafeAreasFromWindow() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        let insets = window.safeAreaInsets
        // Use live per-orientation values (do not keep stale larger inset)
        rootLeadingSafeArea = insets.left
        // Visual compensation: raw top inset sits slightly too low for the guide header.
        rootTopSafeArea = (verticalSizeClass == .some(.compact)) ? 0 : max(0, insets.top - 40)
    }
    #endif

    #if os(macOS)
    private var macOSGuideTitle: String {
        if let groupId = viewModel.selectedGroupId,
           let group = epgCache.channelGroups.first(where: { $0.id == groupId }) {
            return group.name
        }
        if let profileId = viewModel.selectedProfileId,
           let profile = epgCache.channelProfiles.first(where: { $0.id == profileId }) {
            return profile.name
        }
        return "All Channels"
    }

    private var macOSGuideHeader: some View {
        MacGuideHeader(
            title: macOSGuideTitle,
            selectedDate: viewModel.selectedDate,
            canGoToPreviousDay: viewModel.canGoToPreviousDay,
            isRefreshing: epgCache.isRefreshing,
            showsFilterButton: hasFilterData,
            hasActiveFilters: viewModel.hasActiveFilters,
            onPreviousDay: {
                viewModel.previousDay()
                Task { await viewModel.navigateToDate(using: client) }
            },
            onNextDay: {
                viewModel.nextDay()
                Task { await viewModel.navigateToDate(using: client) }
            },
            onNow: {
                viewModel.scrollToNow()
                Task { await viewModel.navigateToDate(using: client) }
                updateScrollTarget()
            },
            onTopics: {
                appState.requestedSettingsCategory = .topics
                appState.selectedTab = .settings
            },
            onRefresh: {
                Task { await refreshGuide() }
            },
            onToggleFilters: {
                withAnimation(.easeInOut(duration: Theme.animationDuration)) {
                    viewModel.showFilters.toggle()
                }
            }
        )
    }

    private var macOSDetailBar: some View {
        let program = macSelection?.program
        let channel = macSelection?.channel
        return MacGuideDetailBar(
            program: program,
            channel: channel,
            primaryAction: program.flatMap { program in channel.flatMap { macPrimaryAction(program: program, channel: $0) } },
            recordTitle: program.flatMap(macRecordTitle(for:)),
            onPrimary: {
                guard let program, let channel else { return }
                if program.isCurrentlyAiring {
                    playLiveChannel(channel)
                } else {
                    playCatchup(program: program, channel: channel)
                }
            },
            onRecord: {
                guard let program, let channel else { return }
                toggleRecording(program: program, channel: channel)
            },
            onDetails: {
                guard let program, let channel else { return }
                selectedProgramDetail = (program: program, channel: channel)
            },
            onClear: {
                macSelection = nil
            }
        )
    }

    private func macPrimaryAction(program: Program, channel: Channel) -> MacGuideDetailBar.PrimaryAction? {
        if program.isCurrentlyAiring { return .watchLive }
        #if DISPATCHERPVR
        if program.hasEnded && viewModel.isCatchupAvailable(program, on: channel) { return .watchReplay }
        #endif
        return nil
    }

    private func macRecordTitle(for program: Program) -> String? {
        guard !appState.hideRecordings, !program.hasEnded else { return nil }
        return viewModel.isScheduledRecording(program) ? "Cancel Recording" : "Record"
    }

    private func playCatchup(program: Program, channel: Channel) {
        #if DISPATCHERPVR
        Task {
            do {
                try await CatchupPlayback.start(
                    program: program,
                    channel: channel,
                    client: client,
                    appState: appState,
                    guideReturnTime: program.startDate
                )
            } catch {
                streamError = error.localizedDescription
            }
        }
        #endif
    }
    #endif

    #if !os(tvOS)

    private var guideTopPadding: CGFloat {
        // iOS overlays the filter panel on the grid, so the rows start below
        // it; the macOS panel sits in the layout flow and needs no room here.
        #if os(iOS)
        guard viewModel.showFilters && hasFilterData else { return 0 }
        var extra: CGFloat = 8 // top/bottom padding
        if !epgCache.channelProfiles.isEmpty { extra += 36 }
        if hasPopulatedGroups { extra += 36 }
        return extra
        #else
        return 0
        #endif
    }
    #endif

    @ViewBuilder
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            #if DISPATCHERPVR
            if !epgCache.channelProfiles.isEmpty {
                filterRow(label: "Profile", items: epgCache.channelProfiles.map { (id: $0.id, name: $0.name) },
                          selectedId: viewModel.selectedProfileId) { id in
                    viewModel.selectedProfileId = id
                }
            }
            #endif
            if !populatedGroups.isEmpty {
                filterRow(label: "Group", items: populatedGroups.map { (id: $0.id, name: $0.name) },
                          selectedId: viewModel.selectedGroupId) { id in
                    viewModel.selectedGroupId = id
                }
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private func filterRow(label: String, items: [(id: Int, name: String)], selectedId: Int?, onSelect: @escaping (Int?) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 48, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterPill("All", isSelected: selectedId == nil) {
                        onSelect(nil)
                    }
                    ForEach(items, id: \.id) { item in
                        filterPill(item.name, isSelected: selectedId == item.id) {
                            onSelect(item.id)
                        }
                    }
                }
            }
        }
        .frame(height: 32)
    }

    private func filterPill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Theme.accent : Theme.surfaceHighlight)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: Theme.spacingMD) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.accent)
            Text("Loading guide...")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.warning)
            Text("Unable to load guide")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.loadData(using: client, epgCache: epgCache) }
            }
            .buttonStyle(AccentButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        Group {
            if viewModel.hasActiveFilters || !viewModel.channelSearchText.isEmpty {
                VStack(spacing: Theme.spacingMD) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No channels match filters")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Button("Clear Filters") {
                        viewModel.selectedGroupId = nil
                        viewModel.selectedProfileId = nil
                        viewModel.channelSearchText = ""
                        appState.guideChannelFilter = ""
                        appState.guideGroupFilter = nil
                        appState.guideProfileFilter = nil
                    }
                    .buttonStyle(AccentButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: Theme.spacingMD) {
                    Image(systemName: "tv")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No channels available")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(Brand.configureServerMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tvOSFocusableEmptyState()
            }
        }
        #if os(tvOS)
        .onExitCommand {
            requestSidebarFocus()
        }
        .onMoveCommand { direction in
            if direction == .left {
                onRequestNavBarFocus?()
                requestSidebarFocus()
            }
        }
        #endif
    }

    @State private var currentTimelineHour: Date?
    @State private var scrollTargetId: String?
    /// The time `scrollTargetId` stands for.
    @State private var scrollTargetTime: Date?
    #if os(macOS)
    /// Drives the macOS grid's scroll by absolute offset (see `scrollGrid(to:)`).
    @State private var gridScrollPosition = ScrollPosition()
    #endif
    @State private var gridHorizontalOffset: CGFloat = 0
    #if os(iOS)
    @State private var lastScrollDirectionChangeY: CGFloat = 0
    #endif
    @Environment(\.scenePhase) private var scenePhase

    #if os(tvOS)
    // tvOS manual focus tracking (like Rivulet approach)
    @FocusState private var gridHasFocus: Bool
    @State private var isTVSearchFieldFocused = false
    @State private var requestTVSearchKeyboard = false
    @State private var focusedRow: Int = 0
    @State private var focusedColumn: Int = 0
    @State private var scrollTopRow: Int = 0
    @State private var focusedHeaderItem: TVGuideHeaderItem = .search
    @State private var timeOffset: Int = 0  // 30-minute increments from now
    @State private var guideStartTime: Date = {
        // Start from current time, rounded down to nearest 30 minutes
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let roundedMinute = (minute / 30) * 30
        return calendar.date(bySettingHour: calendar.component(.hour, from: now),
                            minute: roundedMinute,
                            second: 0,
                            of: now) ?? now
    }()


    // Visible time window: 3 hours
    private let visibleHours: Double = 3.0
    private var visibleMinutes: Double { visibleHours * 60 }

    private var visibleStart: Date {
        guideStartTime.addingTimeInterval(Double(timeOffset * 30 * 60))
    }

    private var visibleEnd: Date {
        visibleStart.addingTimeInterval(visibleMinutes * 60)
    }

    /// Earliest 30-minute window tvOS may navigate to. Dispatcharr catch-up
    /// can move backward from the current-time anchor as far as midnight;
    /// NextPVR retains its existing no-past-navigation behavior.
    private var minimumTimeOffset: Int {
        let calendar = Calendar.current
        guard viewModel.allowsPastDates,
              calendar.isDateInToday(viewModel.selectedDate) else { return 0 }
        let startOfDay = calendar.startOfDay(for: guideStartTime)
        let halfHoursSinceMidnight = Int(guideStartTime.timeIntervalSince(startOfDay) / (30 * 60))
        return -max(0, halfHoursSinceMidnight)
    }

    // Re-anchor the visible timeline on the current half-hour bucket.
    private func resyncGuideStartToNow() {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let roundedMinute = (minute / 30) * 30
        if let newStart = calendar.date(bySettingHour: calendar.component(.hour, from: now),
                                        minute: roundedMinute, second: 0, of: now) {
            guideStartTime = newStart
            timeOffset = 0
        }
    }
    #endif

    private var guideContent: some View {
        #if os(tvOS)
        tvOSGuideContent
        #else
        iOSMacOSGuideContent
        #endif
    }

    #if !os(tvOS)
    @State private var scrollViewHeight: CGFloat = 0
    @State private var scrollViewWidth: CGFloat = 0
    /// Hour offsets from `timelineStart` currently worth rendering (#141).
    /// `nil` until the scroll view reports its size — every program is drawn
    /// until then, so the grid is never blank on first paint.
    @State private var visibleHourWindow: ClosedRange<Int>?
    /// Guards the once-per-appearance current-time positioning (#140).
    @State private var hasCompletedInitialScroll = false
    @State private var initialScrollTask: Task<Void, Never>?

    /// Recomputes which hour slots the grid should render, quantized to whole
    /// hours with one hour of slack on each side (#141).
    ///
    /// Rows are positioned by offset inside a full-width ZStack, so nothing
    /// vertical or horizontal shifts when the window narrows — the cells
    /// outside it simply are not built. Quantizing matters: keying the filter
    /// on the raw offset would rebuild every row on every scroll frame, which
    /// costs more than it saves. This only changes state when the scroll
    /// crosses an hour boundary.
    private func updateVisibleHourWindow() {
        guard scrollViewWidth > 0, hourWidth > 0 else { return }

        // Content x of the timeline's first hour, past the channel column.
        let timelineOriginX = channelWidth
        let leadingHour = Int(floor((gridHorizontalOffset - timelineOriginX) / hourWidth)) - 1
        let trailingHour = Int(ceil((gridHorizontalOffset + scrollViewWidth - timelineOriginX) / hourWidth)) + 1
        let window = max(0, leadingHour)...max(0, trailingHour)

        if visibleHourWindow != window {
            visibleHourWindow = window
        }
    }

    /// Narrows a row's programs to the ones intersecting the rendered window.
    /// Cells are absolutely positioned, so dropping the rest changes nothing
    /// about where the survivors land (#141).
    private func renderedPrograms(from programs: [Program]) -> [Program] {
        guard let window = visibleTimeWindow else { return programs }
        return programs.filter { $0.endDate > window.start && $0.startDate < window.end }
    }

    /// The time span the grid is currently rendering, or `nil` for "everything".
    private var visibleTimeWindow: (start: Date, end: Date)? {
        guard let visibleHourWindow else { return nil }
        let timelineStart = viewModel.timelineStart
        return (
            start: timelineStart.addingTimeInterval(Double(visibleHourWindow.lowerBound) * 3600),
            end: timelineStart.addingTimeInterval(Double(visibleHourWindow.upperBound + 1) * 3600)
        )
    }

    /// Positions the timeline on the current half-hour when the guide appears.
    ///
    /// Catch-up builds keep the whole day in the timeline, so the grid starts
    /// at midnight and only reaches "now" by scrolling. A single scroll
    /// request issued before the rows have landed is silently dropped, which
    /// left the guide sitting at 00:00 on first launch (#140) — so this
    /// retries until the observed offset shows the scroll took effect.
    /// Navigating the timeline afterwards moves the offset too, which ends the
    /// retries as well: the guide never yanks itself back.
    private func startInitialScroll(using proxy: ScrollViewProxy) {
        guard !hasCompletedInitialScroll, initialScrollTask == nil else { return }

        #if os(macOS)
        let hasCatchupReturnTarget = appState.catchupGuideReturnTime != nil
        #else
        let hasCatchupReturnTarget = false
        #endif
        guard !hasCatchupReturnTarget, !preservesGuidePositionAfterCatchup else { return }

        // Nothing to scroll against until the grid has rows.
        guard !viewModel.channels.isEmpty else { return }

        initialScrollTask = Task { @MainActor in
            defer { initialScrollTask = nil }
            hasCompletedInitialScroll = true

            guard let targetId = updateScrollTarget() else { return }
            #if os(macOS)
            _ = targetId
            if let time = scrollTargetTime {
                await scrollGrid(to: time)
            }
            #else
            let expectedOffset = GuideScrollHelper.expectedScrollOffsetX(
                timelineStart: viewModel.timelineStart,
                scrollTarget: currentTimelineHour ?? viewModel.timelineStart,
                hourWidth: hourWidth
            )

            for attempt in 0..<8 {
                proxy.scrollTo(targetId, anchor: gridScrollAnchor)
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 150 : 300))
                guard !Task.isCancelled else { return }
                // `anchor` leaves the target inset from the leading edge, so
                // compare against a fraction of the expected distance rather
                // than the exact value.
                if expectedOffset <= 1 || gridHorizontalOffset > expectedOffset * 0.5 {
                    return
                }
            }
            #endif
        }
    }

    #if os(macOS)
    /// Scrolls the grid so `time` sits just past the pinned channel column.
    ///
    /// Uses an absolute content offset rather than a fractional anchor: an
    /// anchor is resolved against the viewport width at the moment of the
    /// request, and right after launch that width can still be settling, which
    /// left the guide opened an hour or more short of "now". The scroll view
    /// also clamps to the content laid out so far, so this retries until the
    /// offset is exactly where it was asked to be.
    private func scrollGrid(to time: Date) async {
        let targetX = GuideScrollHelper.contentOffsetX(
            timelineStart: viewModel.timelineStart,
            target: time,
            hourWidth: hourWidth,
            inset: Theme.spacingLG
        )
        for attempt in 0..<8 {
            gridScrollPosition.scrollTo(point: CGPoint(x: targetX, y: 0))
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 150 : 300))
            guard !Task.isCancelled else { return }
            if abs(gridHorizontalOffset - targetX) <= 1 { return }
        }
    }
    #endif

    /// Where a scroll-to-time target lands in the viewport (iOS; macOS scrolls
    /// by absolute offset, see `scrollGrid(to:)`).
    private var gridScrollAnchor: UnitPoint {
        UnitPoint(x: 0.10, y: 0)
    }

    #if os(macOS)
    private var gridRowSpacing: CGFloat { 0 }
    private var gridPinnedViews: PinnedScrollableViews { [.sectionHeaders] }
    #else
    private var gridRowSpacing: CGFloat { 1 }
    private var gridPinnedViews: PinnedScrollableViews { [] }
    #endif

    private var iOSMacOSGuideContent: some View {
        // Main grid — single LazyVStack for guaranteed lazy rendering
        // Channel cells pinned to left edge by counteracting horizontal scroll
        ScrollViewReader { programProxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                LazyVStack(spacing: gridRowSpacing, pinnedViews: gridPinnedViews) {
                  Section {
                    // Invisible scroll anchors for scroll-to-time
                    HStack(spacing: 0) {
                        Color.clear.frame(width: channelWidth, height: 1)
                        ForEach(viewModel.hoursToShow, id: \.self) { hour in
                            HStack(spacing: 0) {
                                Color.clear
                                    .frame(width: hourWidth / 2, height: 1)
                                    .id("scroll-\(hour.timeIntervalSince1970)")
                                Color.clear
                                    .frame(width: hourWidth / 2, height: 1)
                                    .id("scroll-\(hour.timeIntervalSince1970 + 1800)")
                            }
                        }
                    }
                    .frame(height: 0)

                    #if !os(tvOS)
                    // Top padding so first row isn't behind the floating date pill + filter panel
                    Color.clear.frame(height: guideTopPadding)
                    #endif

                    ForEach(viewModel.channels) { channel in
                        ZStack(alignment: .leading) {
                            // Programs (scroll with content)
                            HStack(spacing: 0) {
                                Color.clear.frame(width: channelWidth, height: rowHeight)
                                programsRow(channel)
                                    .frame(height: rowHeight)
                                    #if os(macOS)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
                                    }
                                    #else
                                    .background(Theme.surface)
                                    #endif
                            }

                            // Channel cell pinned to visible left edge (after safe area)
                            channelCell(channel)
                                .frame(width: channelWidth, height: rowHeight)
                                .offset(x: gridHorizontalOffset + rootLeadingSafeArea)
                                .zIndex(1)
                        }
                    }

                  } header: {
                    #if os(macOS)
                    MacGuideTimeRuler(
                        timelineStart: viewModel.timelineStart,
                        hourCount: viewModel.hoursToShow.count,
                        hourWidth: hourWidth,
                        channelWidth: channelWidth,
                        horizontalOffset: gridHorizontalOffset + rootLeadingSafeArea
                    )
                    #endif
                  }
                }
                .frame(minHeight: scrollViewHeight, alignment: .top)
                #if os(iOS)
                .background(ScrollViewDirectionalLock())
                #endif
                #if os(macOS)
                .modifier(MacScrollDirectionalLockModifier())
                #endif
            }
            #if os(macOS)
            .scrollPosition($gridScrollPosition)
            #endif
            .refreshable {
                await refreshGuide()
            }
            .onScrollGeometryChange(for: CGSize.self) { geo in
                geo.containerSize
            } action: { _, new in
                scrollViewHeight = new.height
                scrollViewWidth = new.width
                updateVisibleHourWindow()
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x
            } action: { _, new in
                gridHorizontalOffset = new
                updateVisibleHourWindow()
            }
            #if os(iOS)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { old, new in
                if appState.isUITesting {
                    if appState.isBottomBarHidden {
                        appState.isBottomBarHidden = false
                    }
                    return
                }

                let delta = new - old
                if delta > 5 && !appState.isBottomBarHidden {
                    // Scrolling down — hide immediately
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appState.isBottomBarHidden = true
                    }
                    lastScrollDirectionChangeY = new
                } else if delta < -5 && appState.isBottomBarHidden {
                    // Scrolling up — only show after sustained upward scroll
                    let upDistance = lastScrollDirectionChangeY - new
                    if upDistance > 80 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appState.isBottomBarHidden = false
                        }
                    }
                }
                // Track where direction last changed to down
                if delta > 5 {
                    lastScrollDirectionChangeY = new
                }
            }
            #endif
            .onAppear {
                startInitialScroll(using: programProxy)
            }
            .onChange(of: viewModel.channels.count) {
                // The first rows can land after the grid appears; a scroll
                // requested against an empty grid never sticks (#140).
                startInitialScroll(using: programProxy)
            }
            .onChange(of: epgCache.isFullyLoaded) {
                startInitialScroll(using: programProxy)
            }
            .onDisappear {
                initialScrollTask?.cancel()
                initialScrollTask = nil
                hasCompletedInitialScroll = false
            }
            #if os(macOS)
            .task {
                guard let catchupReturnTime = appState.catchupGuideReturnTime else { return }

                // MacOSNavigation keeps the ViewModel alive, but reconstructs
                // the ScrollView after PlayerView disappears. Keep the target
                // pending and retry after layout: the first scroll request can
                // arrive before SwiftUI has installed the horizontal anchors.
                if !Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: catchupReturnTime) {
                    viewModel.selectedDate = catchupReturnTime
                }

                await Task.yield()
                guard !Task.isCancelled,
                      updateScrollTarget(preferredTime: catchupReturnTime) != nil,
                      let time = scrollTargetTime else { return }

                await scrollGrid(to: time)
                guard !Task.isCancelled else { return }

                appState.clearCatchupGuideReturnTime(ifMatching: catchupReturnTime)
            }
            #endif
            .onChange(of: viewModel.selectedDate) {
                updateScrollTarget()
            }
            .onChange(of: scrollTargetId) { _, newValue in
                #if os(macOS)
                if newValue != nil, let time = scrollTargetTime {
                    Task { await scrollGrid(to: time) }
                }
                #else
                if let targetId = newValue {
                    programProxy.scrollTo(targetId, anchor: gridScrollAnchor)
                }
                #endif
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active
                && !preservesGuidePositionAfterCatchup
                && appState.catchupGuideReturnTime == nil {
                viewModel.scrollToNow()
                updateScrollTarget()
            }
        }
    }
    #endif

    private let filterRowIndex = -1

    #if os(tvOS)
    private enum TVGuideHeaderItem: Int, CaseIterable {
        case previousDay
        case nextDay
        case search
        case group
        #if DISPATCHERPVR
        case profile
        #endif
        case refresh
    }

    private var tvHeaderItems: [TVGuideHeaderItem] {
        var items: [TVGuideHeaderItem] = [.previousDay, .nextDay, .search]
        if hasPopulatedGroups { items.append(.group) }
        #if DISPATCHERPVR
        items.append(.profile)
        #endif
        items.append(.refresh)
        return items
    }

    /// `.profile` is only ever opened in the Dispatcharr build — channel
    /// profiles have no NextPVR equivalent.
    private enum TVGuideDrawerKind {
        case group
        case profile
    }

    private struct TVGuideDrawerItem: Identifiable {
        let id: String
        let label: String
        let value: Int?
    }

    @State private var headerDrawerKind: TVGuideDrawerKind? = nil
    @State private var drawerSelectionIndex: Int = 0

    private var isHeaderDrawerOpen: Bool { headerDrawerKind != nil }

    private var currentDrawerItems: [TVGuideDrawerItem] {
        switch headerDrawerKind {
        case .group:
            return [TVGuideDrawerItem(id: "group-all", label: "All Groups", value: nil)] +
                   populatedGroups.map { TVGuideDrawerItem(id: "group-\($0.id)", label: $0.name, value: $0.id) }
        case .profile:
            #if DISPATCHERPVR
            return [TVGuideDrawerItem(id: "profile-all", label: "All Profiles", value: nil)] +
                   epgCache.channelProfiles.map { TVGuideDrawerItem(id: "profile-\($0.id)", label: $0.name, value: $0.id) }
            #else
            return []
            #endif
        case .none:
            return []
        }
    }

    private var tvOSGuideContent: some View {
        GeometryReader { geometry in
            let gridWidth = geometry.size.width - channelWidth
            let pxPerMinute = gridWidth / visibleMinutes
            let filterRowHeight: CGFloat = 70
            let drawerContentHeight = 60 + CGFloat(currentDrawerItems.count) * 52
            let drawerHeight: CGFloat = isHeaderDrawerOpen ? min(320, max(170, drawerContentHeight)) : 0
            let rulerHeight = TVGuideTimeRuler.height

            // Grid — manual offset driven by scrollTopRow (keep-in-view scrolling)
            let totalRows = viewModel.channels.count
            let visibleRows = Int((geometry.size.height - filterRowHeight - drawerHeight - rulerHeight) / rowHeight)
            let scrollOffset = CGFloat(scrollTopRow) * rowHeight

            // Virtualization: only render visible rows + buffer
            let buffer = 3
            let firstRow = max(0, scrollTopRow - buffer)
            let lastRow = min(totalRows - 1, scrollTopRow + visibleRows - 1 + buffer)

            VStack(spacing: 0) {
                // Filter row (row -1)
                tvOSFilterRow(
                    isFocused: gridHasFocus && focusedRow == filterRowIndex,
                    focusedItem: focusedHeaderItem
                )
                .frame(height: filterRowHeight)
                if isHeaderDrawerOpen {
                    tvOSHeaderDrawer
                        .frame(height: drawerHeight)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                TVGuideTimeRuler(
                    windowStart: visibleStart,
                    windowMinutes: visibleMinutes,
                    channelWidth: channelWidth,
                    gridWidth: gridWidth
                )

                // Channel rows
                VStack(spacing: 0) {
                    if totalRows > 0 {
                        Color.clear.frame(height: CGFloat(firstRow) * rowHeight)
                        ForEach(firstRow...lastRow, id: \.self) { rowIndex in
                            tvOSChannelRow(
                                channel: viewModel.channels[rowIndex],
                                rowIndex: rowIndex,
                                gridWidth: gridWidth,
                                pxPerMinute: pxPerMinute
                            )
                            .id(viewModel.channels[rowIndex].id)
                        }
                        Color.clear.frame(height: CGFloat(max(0, totalRows - 1 - lastRow)) * rowHeight)
                    }
                }
                .offset(y: -scrollOffset)
                .animation(.easeInOut(duration: 0.15), value: scrollTopRow)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
                .overlay(alignment: .topLeading) {
                    tvOSNowLine(channelWidth: channelWidth, pxPerMinute: pxPerMinute)
                }
            }
            .contentShape(Rectangle())
            .focusable(true)
            .onChange(of: focusedRow) { _, newRow in
                guard newRow >= 0 else { return }
                // Only scroll when focused row would be outside visible area
                let maxTopRow = max(0, viewModel.channels.count - visibleRows)
                if newRow < scrollTopRow {
                    scrollTopRow = max(0, newRow)
                } else if newRow >= scrollTopRow + visibleRows {
                    scrollTopRow = min(maxTopRow, newRow - visibleRows + 1)
                }
            }
            .focused($gridHasFocus)
            .onTapGesture {
                handleTVSelect()
            }
            .onMoveCommand { direction in
                handleTVNavigation(direction)
            }
            .onPlayPauseCommand {
                handleTVSelect()
            }
        }
        .onChange(of: viewModel.selectedDate) { oldDate, newDate in
            // Reset grid time window when date changes
            let calendar = Calendar.current
            if calendar.isDateInToday(newDate) {
                // Today: start from current time rounded to 30 min
                let now = Date()
                let minute = calendar.component(.minute, from: now)
                let roundedMinute = (minute / 30) * 30
                guideStartTime = calendar.date(bySettingHour: calendar.component(.hour, from: now),
                                               minute: roundedMinute, second: 0, of: now) ?? now
            } else {
                // Other days: start from midnight
                guideStartTime = calendar.startOfDay(for: newDate)
            }
            timeOffset = 0
            if calendar.isDate(oldDate, inSameDayAs: newDate) {
                // Same-day refresh (e.g. returning from the player via
                // scrollToNow()): keep focus on the previously focused channel
                // row instead of jumping back to the first channel. The time
                // window was re-anchored to now, so the old column index no
                // longer maps to the same program — reset it to the leftmost.
                focusedColumn = 0
            } else {
                // Real day change: start fresh at the top of the grid.
                focusedRow = 0
                focusedColumn = 0
                scrollTopRow = 0
            }
            endTVSearchEditing()
            closeHeaderDrawer()
        }
    }

    private func tvOSChannelRow(channel: Channel, rowIndex: Int, gridWidth: CGFloat, pxPerMinute: CGFloat) -> some View {
        let isRowFocused = gridHasFocus && rowIndex == focusedRow
        let programs = tvOSVisiblePrograms(for: channel)

        return HStack(spacing: 0) {
            // Channel cell
            tvOSChannelCell(channel: channel, isSelected: isRowFocused)

            // Programs row
            ZStack(alignment: .leading) {
                if programs.isEmpty {
                    // Show channel name as tappable placeholder so user can still play
                    let isFocused = isRowFocused && focusedColumn == 0
                    Text(channel.name)
                        .font(.archivo(Theme.scaledFont(19), .extraBold))
                        .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.inkFaint)
                        .padding(.leading, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(isFocused ? MidnightPalette.selectedBg : Color.clear)
                } else {
                    ForEach(Array(programs.enumerated()), id: \.element.id) { colIndex, program in
                        let isFocused = isRowFocused && colIndex == focusedColumn
                        tvOSProgramCell(
                            program: program,
                            channel: channel,
                            isFocused: isFocused,
                            gridWidth: gridWidth,
                            pxPerMinute: pxPerMinute
                        )
                    }
                }
            }
            // Leading-aligned: cells are positioned by offset from the row start.
            .frame(width: gridWidth, height: rowHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
    }

    /// The accent now-line through the rows, while now is in the window.
    private func tvOSNowLine(channelWidth: CGFloat, pxPerMinute: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            let minutes = context.date.timeIntervalSince(visibleStart) / 60
            if minutes >= 0, minutes < visibleMinutes {
                Rectangle()
                    .fill(MidnightPalette.accent)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .offset(x: channelWidth + CGFloat(minutes) * pxPerMinute - 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func tvOSChannelCell(channel: Channel, isSelected: Bool) -> some View {
        MidnightChannelPlate(
            channel: channel,
            iconURL: try? client.channelIconURL(channelId: channel.id),
            logoInsets: EdgeInsets(top: 14, leading: 30, bottom: 14, trailing: 24),
            nameSize: Theme.scaledFont(20)
        )
        .frame(width: channelWidth, height: rowHeight)
        // The focused row's channel gets the accent bar.
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(MidnightPalette.accent).frame(width: 6)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(MidnightPalette.line).frame(width: 1)
        }
    }

    private func tvOSProgramCell(program: Program, channel: Channel, isFocused: Bool, gridWidth: CGFloat, pxPerMinute: CGFloat) -> some View {
        let (xPos, cellWidth) = tvOSProgramPosition(program: program, pxPerMinute: pxPerMinute)
        let isAiring = program.isCurrentlyAiring
        let isScheduled = viewModel.isScheduledRecording(program)
        let isRecording = isScheduled && isAiring && viewModel.recordingStatus(program) == .recording
        #if DISPATCHERPVR
        let catchupAvailable = CatchupAvailability.isAvailable(
            program: program,
            channelIsCatchup: channel.isCatchup,
            catchupDays: channel.catchupDays
        )
        #else
        let catchupAvailable = false
        #endif

        return TVProgramCell(
            program: program,
            width: cellWidth,
            height: rowHeight - 1,
            isFocused: isFocused,
            isScheduled: isScheduled,
            isRecording: isRecording,
            isCatchupAvailable: catchupAvailable,
            matchedTopic: viewModel.keywordMatchByProgramId[program.id]
        )
        .offset(x: xPos + 1)
    }

    private func tvOSProgramPosition(program: Program, pxPerMinute: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let progVisibleStart = max(program.startDate, visibleStart)
        let progVisibleEnd = min(program.endDate, visibleEnd)

        let x = CGFloat(progVisibleStart.timeIntervalSince(visibleStart) / 60) * pxPerMinute
        let width = max(CGFloat(progVisibleEnd.timeIntervalSince(progVisibleStart) / 60) * pxPerMinute, 80)

        return (x, width)
    }

    private func tvOSVisiblePrograms(for channel: Channel) -> [Program] {
        // Use programs(for:) instead of visiblePrograms(for:) to avoid the
        // ViewModel's time-based filter which uses live Date() and can desync
        // from our frozen guideStartTime, causing cells to disappear.
        let programs = viewModel.programs(for: channel)
        return programs.filter { program in
            program.endDate > visibleStart && program.startDate < visibleEnd
        }
    }

    // MARK: - tvOS Filter Bar

    /// Filter row rendered as the first row in the grid (focusedRow == -1)
    private func tvOSFilterRow(isFocused: Bool, focusedItem: TVGuideHeaderItem) -> some View {
        HStack(spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Guide")
                    .midnightKicker(Theme.scaledFont(13))
                    .foregroundStyle(MidnightPalette.accent)
                Text(tvOSGuideTitle)
                    .midnightDisplay(Theme.scaledFont(30))
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.trailing, Theme.spacingSM)

            // Date
            tvOSHeaderField(
                imageName: "chevron.left",
                isFocused: isFocused && focusedItem == .previousDay,
                isEnabled: viewModel.canGoToPreviousDay
            )

            Text(viewModel.selectedDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.archivo(Theme.scaledFont(19), .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.ink)

            tvOSHeaderField(
                imageName: "chevron.right",
                isFocused: isFocused && focusedItem == .nextDay,
                isEnabled: true
            )

            Rectangle().fill(MidnightPalette.line).frame(width: 1, height: 30)

            // Search / active filter
            tvOSSearchField(isFocused: isFocused && focusedItem == .search)

            if hasPopulatedGroups {
                tvOSFilterField(
                    icon: "folder.fill",
                    title: "Group",
                    value: selectedGroupLabel,
                    isFocused: isFocused && focusedItem == .group
                )
            }
            #if DISPATCHERPVR
            tvOSFilterField(
                icon: "person.fill",
                title: "Profile",
                value: selectedProfileLabel,
                isFocused: isFocused && focusedItem == .profile
            )
            #endif

            // Reload channels + EPG from the server (#118)
            tvOSHeaderField(
                imageName: "arrow.clockwise",
                isFocused: isFocused && focusedItem == .refresh,
                isEnabled: !epgCache.isRefreshing
            )
            .accessibilityLabel("Refresh guide")
            .accessibilityIdentifier("guide-refresh-button")

            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }

    /// The selected group or profile, or "All Channels".
    private var tvOSGuideTitle: String {
        if let groupId = viewModel.selectedGroupId,
           let group = epgCache.channelGroups.first(where: { $0.id == groupId }) {
            return group.name
        }
        #if DISPATCHERPVR
        if let profileId = viewModel.selectedProfileId,
           let profile = epgCache.channelProfiles.first(where: { $0.id == profileId }) {
            return profile.name
        }
        #endif
        return "All Channels"
    }

    private var selectedGroupLabel: String {
        if let groupId = viewModel.selectedGroupId,
           let group = epgCache.channelGroups.first(where: { $0.id == groupId }) {
            return group.name
        }
        return "All Groups"
    }

    #if DISPATCHERPVR
    private var selectedProfileLabel: String {
        if let profileId = viewModel.selectedProfileId,
           let profile = epgCache.channelProfiles.first(where: { $0.id == profileId }) {
            return profile.name
        }
        return "All Profiles"
    }
    #endif

    private func tvOSSearchField(isFocused: Bool) -> some View {
        let isActive = isFocused || isTVSearchFieldFocused
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isActive ? MidnightPalette.selectedInk : MidnightPalette.inkFaint)
            TVImmediateSearchField(
                text: $viewModel.channelSearchText,
                placeholder: "Search channels...",
                requestFocus: $requestTVSearchKeyboard,
                useFocusedStyle: isActive,
                onFocusChange: { focused in
                    isTVSearchFieldFocused = focused
                    if !focused {
                        requestTVSearchKeyboard = false
                        DispatchQueue.main.async {
                            gridHasFocus = true
                        }
                        clampFocusedRowToChannels()
                    }
                }
            )
            .frame(height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? MidnightPalette.selectedBg : MidnightPalette.inputBg)
        .overlay {
            Rectangle().strokeBorder(isActive ? Color.clear : MidnightPalette.line, lineWidth: 1)
        }
        .scaleEffect(isActive ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.14), value: isActive)
    }

    private func beginTVSearchEditing() {
        gridHasFocus = false
        requestTVSearchKeyboard = true
    }

    private func endTVSearchEditing() {
        requestTVSearchKeyboard = false
        isTVSearchFieldFocused = false
        DispatchQueue.main.async {
            gridHasFocus = true
        }
    }

    private func tvOSFilterField(
        icon: String,
        title: String,
        value: String,
        isFocused: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("\(title): \(value)")
                .lineLimit(1)
        }
        .font(.archivo(Theme.scaledFont(17), .extraBold))
        .foregroundStyle(
            isFocused
            ? MidnightPalette.selectedInk
            : (value.hasPrefix("All ") ? MidnightPalette.inkSoft : MidnightPalette.accentSoft)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isFocused ? MidnightPalette.selectedBg : Color.clear)
        .overlay {
            Rectangle().strokeBorder(isFocused ? Color.clear : MidnightPalette.line, lineWidth: 1)
        }
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.14), value: isFocused)
    }

    private var tvOSHeaderDrawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerDrawerKind == .group ? "Select group" : "Select profile")
                .midnightKicker(Theme.scaledFont(13))
                .foregroundStyle(MidnightPalette.accent)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(currentDrawerItems.enumerated()), id: \.element.id) { index, item in
                        let isSelected = index == drawerSelectionIndex
                        HStack(spacing: 10) {
                            Text(item.label)
                                .lineLimit(1)
                            Spacer()
                        }
                        .font(.archivo(Theme.scaledFont(18), .extraBold))
                        .foregroundStyle(isSelected ? MidnightPalette.selectedInk : MidnightPalette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isSelected ? MidnightPalette.selectedBg : MidnightPalette.cellRest)
                        .overlay(alignment: .leading) {
                            if isSelected {
                                Rectangle().fill(MidnightPalette.accent).frame(width: 5)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, 12)
        .background(MidnightPalette.railHead)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }

    private func tvOSHeaderField(
        imageName: String,
        isFocused: Bool,
        isEnabled: Bool
    ) -> some View {
        Image(systemName: imageName)
            .font(.tvScaled(size: 16, weight: .semibold))
            .foregroundStyle(
                isEnabled
                ? (isFocused ? MidnightPalette.selectedInk : MidnightPalette.ink)
                : MidnightPalette.inkFaint.opacity(0.4)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFocused ? MidnightPalette.selectedBg : Color.clear)
            .overlay {
                Rectangle().strokeBorder(isFocused ? Color.clear : MidnightPalette.line, lineWidth: 1)
            }
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
    }

    private func clampFocusedRowToChannels() {
        focusedRow = 0
        scrollTopRow = 0
        focusedColumn = 0
    }

    private func openHeaderDrawer(_ kind: TVGuideDrawerKind) {
        headerDrawerKind = kind
        let selectedValue: Int? = (kind == .group) ? viewModel.selectedGroupId : viewModel.selectedProfileId
        if let idx = currentDrawerItems.firstIndex(where: { $0.value == selectedValue }) {
            drawerSelectionIndex = idx
        } else {
            drawerSelectionIndex = 0
        }
    }

    private func closeHeaderDrawer() {
        headerDrawerKind = nil
    }

    private func applyDrawerSelection() {
        guard let kind = headerDrawerKind, currentDrawerItems.indices.contains(drawerSelectionIndex) else { return }
        let selected = currentDrawerItems[drawerSelectionIndex]
        switch kind {
        case .group:
            viewModel.selectedGroupId = selected.value
        case .profile:
            viewModel.selectedProfileId = selected.value
        }
        clampFocusedRowToChannels()
        closeHeaderDrawer()
    }

    private func handleHeaderDrawerNavigation(_ direction: MoveCommandDirection) {
        guard !currentDrawerItems.isEmpty else { return }
        switch direction {
        case .up:
            drawerSelectionIndex = max(0, drawerSelectionIndex - 1)
        case .down:
            drawerSelectionIndex = min(currentDrawerItems.count - 1, drawerSelectionIndex + 1)
        case .left, .right:
            closeHeaderDrawer()
        @unknown default:
            break
        }
    }

    private func handleTVNavigation(_ direction: MoveCommandDirection) {
        if isHeaderDrawerOpen {
            handleHeaderDrawerNavigation(direction)
            return
        }

        if isTVSearchFieldFocused {
            endTVSearchEditing()
            if direction == .down {
                clampFocusedRowToChannels()
                return
            }
        }

        let channels = viewModel.channels

        switch direction {
        case .up:
            if focusedRow == filterRowIndex {
                onRequestNavBarFocus?()
            } else if focusedRow == 0 {
                // Move up to filter row
                focusedRow = filterRowIndex
                focusedHeaderItem = focusedColumn == 0 ? .nextDay : .search
            } else {
                focusedRow -= 1
                clampColumn()
            }
        case .down:
            if focusedRow == filterRowIndex {
                // Move from filter row to first channel
                focusedRow = 0
            } else if focusedRow < channels.count - 1 {
                focusedRow += 1
                clampColumn()
            }
        case .left:
            if focusedRow == filterRowIndex {
                moveHeaderFocusLeft()
                return
            }
            guard focusedRow >= 0, !channels.isEmpty else { return }
            if focusedColumn > 0 {
                focusedColumn -= 1
            } else if timeOffset > minimumTimeOffset {
                // Scroll back in time — focus the program immediately before the
                // one that was focused, mirroring the forward-scroll behavior.
                // Jumping to the last cell of the new window would throw focus
                // back to the right edge on every left press (#152).
                let programs = tvOSVisiblePrograms(for: channels[focusedRow])
                let previousProgram = programs.isEmpty
                    ? nil
                    : programs[min(focusedColumn, programs.count - 1)]
                timeOffset -= 1
                let newPrograms = tvOSVisiblePrograms(for: channels[focusedRow])
                if newPrograms.isEmpty {
                    focusedColumn = 0
                } else if let previousProgram,
                          let priorIndex = newPrograms.lastIndex(where: { $0.startDate < previousProgram.startDate }) {
                    focusedColumn = priorIndex
                } else if let previousProgram,
                          let sameIndex = newPrograms.firstIndex(where: { $0.startDate == previousProgram.startDate }) {
                    // Nothing earlier on this channel — stay on the same program.
                    focusedColumn = sameIndex
                } else {
                    focusedColumn = 0
                }
            } else {
                // Already on leftmost program of the row — open the nav bar
                onRequestNavBarFocus?()
            }
        case .right:
            if focusedRow == filterRowIndex {
                moveHeaderFocusRight()
                return
            }
            guard focusedRow >= 0, !channels.isEmpty else { return }
            let programs = tvOSVisiblePrograms(for: channels[focusedRow])
            guard !programs.isEmpty else {
                // No programs visible — just scroll forward in time
                if timeOffset < 36 { timeOffset += 1 }
                focusedColumn = 0
                return
            }
            if focusedColumn < programs.count - 1 {
                focusedColumn += 1
            } else if timeOffset < 36 {  // Max 18 hours ahead (36 x 30min)
                // Scroll forward in time — focus on first program after the current one
                let safeColumn = min(focusedColumn, programs.count - 1)
                let lastProgram = programs[safeColumn]
                timeOffset += 1
                let newPrograms = tvOSVisiblePrograms(for: channels[focusedRow])
                if let nextIndex = newPrograms.firstIndex(where: { $0.startDate > lastProgram.startDate }) {
                    focusedColumn = nextIndex
                } else {
                    focusedColumn = max(0, newPrograms.count - 1)
                }
            }
        @unknown default:
            break
        }
    }

    private func moveHeaderFocusLeft() {
        let items = tvHeaderItems
        guard let currentIndex = items.firstIndex(of: focusedHeaderItem) else {
            focusedHeaderItem = items[0]
            return
        }
        focusedHeaderItem = items[max(0, currentIndex - 1)]
    }

    private func moveHeaderFocusRight() {
        let items = tvHeaderItems
        guard let currentIndex = items.firstIndex(of: focusedHeaderItem) else {
            focusedHeaderItem = items[0]
            return
        }
        focusedHeaderItem = items[min(items.count - 1, currentIndex + 1)]
    }

    private func handleTVSelect() {
        if isHeaderDrawerOpen {
            applyDrawerSelection()
            return
        }
        if isTVSearchFieldFocused {
            endTVSearchEditing()
            clampFocusedRowToChannels()
            return
        }
        if focusedRow == filterRowIndex {
            selectFocusedHeaderItem()
            return
        }
        selectFocusedProgram()
    }

    private func selectFocusedHeaderItem() {
        switch focusedHeaderItem {
        case .previousDay:
            guard viewModel.canGoToPreviousDay else { return }
            viewModel.previousDay()
            Task { await viewModel.navigateToDate(using: client) }
        case .nextDay:
            endTVSearchEditing()
            viewModel.nextDay()
            Task { await viewModel.navigateToDate(using: client) }
        case .search:
            beginTVSearchEditing()
        case .group:
            guard hasPopulatedGroups else { return }
            endTVSearchEditing()
            openHeaderDrawer(.group)
        #if DISPATCHERPVR
        case .profile:
            endTVSearchEditing()
            openHeaderDrawer(.profile)
        #endif
        case .refresh:
            guard !epgCache.isRefreshing else { return }
            endTVSearchEditing()
            Task { await refreshGuide() }
        }
    }

    private func clampColumn() {
        guard focusedRow < viewModel.channels.count else { return }
        let programs = tvOSVisiblePrograms(for: viewModel.channels[focusedRow])
        focusedColumn = min(focusedColumn, max(0, programs.count - 1))
    }

    private func selectFocusedProgram() {
        guard focusedRow < viewModel.channels.count else { return }
        let channel = viewModel.channels[focusedRow]
        let programs = tvOSVisiblePrograms(for: channel)

        // No EPG data — play channel live
        guard focusedColumn < programs.count else {
            playLiveChannel(channel)
            return
        }

        let program = programs[focusedColumn]
        selectedProgramDetail = (program: program, channel: channel)
    }

    #endif


    @ViewBuilder
    private func channelCell(_ channel: Channel) -> some View {
        #if os(tvOS)
        // tvOS: non-interactive channel icon - logo fills the cell
        CachedAsyncImage(url: try? client.channelIconURL(channelId: channel.id)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            ProgressView()
                .scaleEffect(0.5)
        }
        .padding(Theme.spacingSM)
        .frame(width: channelWidth, height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius(10))
                .fill(Theme.surfaceElevated.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius(10))
                .stroke(Theme.surfaceHighlight.opacity(0.55), lineWidth: 1)
        )
        #elseif os(macOS)
        MacGuideChannelCell(
            channel: channel,
            iconURL: try? client.channelIconURL(channelId: channel.id)
        ) {
            playLiveChannel(channel)
        }
        #else
        // iOS: tappable to play live
        Button {
            playLiveChannel(channel)
        } label: {
            CachedAsyncImage(url: try? client.channelIconURL(channelId: channel.id)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView()
                    .scaleEffect(0.5)
            }
            .frame(width: Theme.iconSize, height: Theme.iconSize)
            .frame(width: channelWidth, height: rowHeight)
            .background(Theme.channelColumnBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("guide-channel-\(channel.id)")
        #endif
    }

    private func programsRow(_ channel: Channel) -> some View {
        let timelineStart = viewModel.timelineStart
        let dayPrograms = viewModel.visiblePrograms(for: channel)
        #if os(tvOS)
        let programs = dayPrograms
        #else
        // Only build the cells the viewer can actually see (#141).
        let programs = renderedPrograms(from: dayPrograms)
        #endif
        // Scroll target: :00 or :30 based on current minute
        let scrollTarget = viewModel.scrollTargetTime

        return ZStack(alignment: .leading) {
            // Background for the full timeline
            Color.clear
                .frame(width: hourWidth * CGFloat(viewModel.hoursToShow.count))

            // Keyed off the whole day, not the rendered window, so scrolling
            // into an empty stretch of a populated row doesn't swap in the
            // channel-name placeholder.
            if dayPrograms.isEmpty {
                // Show channel name as placeholder so user can still tap to play
                Button {
                    playLiveChannel(channel)
                } label: {
                    Text(channel.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, Theme.spacingMD)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            // Program cells
            ForEach(programs) { program in
                let isScheduled = viewModel.isScheduledRecording(program)
                let status = viewModel.recordingStatus(program)
                let isRecording = isScheduled && program.isCurrentlyAiring && status == .recording
                let matchesKeywords = viewModel.keywordMatchedProgramIds.contains(program.id)
                #if DISPATCHERPVR
                let catchupAvailable = viewModel.isCatchupAvailable(program, on: channel)
                #else
                let catchupAvailable = false
                #endif
                // Calculate leading padding for live programs - push text to visible left edge (scroll target)
                let leadingPad = GuideScrollHelper.calculateLeadingPadding(
                    programStart: max(program.startDate, timelineStart),
                    scrollTarget: scrollTarget,
                    hourWidth: hourWidth,
                    isCurrentlyAiring: program.isCurrentlyAiring
                )

                #if os(macOS)
                MacProgramCell(
                    program: program,
                    width: viewModel.programWidth(for: program, hourWidth: hourWidth, startTime: timelineStart),
                    height: rowHeight - 1,
                    isScheduledRecording: isScheduled,
                    isCurrentlyRecording: isRecording,
                    isCatchupAvailable: catchupAvailable,
                    matchedTopic: viewModel.keywordMatchByProgramId[program.id],
                    isSelected: macSelection?.program.id == program.id && macSelection?.channel.id == channel.id,
                    leadingPadding: leadingPad
                )
                .onTapGesture(count: 2) {
                    selectedProgramDetail = (program: program, channel: channel)
                }
                .onTapGesture {
                    macSelection = ProgramDetail(program: program, channel: channel)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    macSelection = ProgramDetail(program: program, channel: channel)
                }
                .contextMenu {
                    programContextMenu(program: program, channel: channel, isScheduled: isScheduled)
                }
                .accessibilityIdentifier("guide-program-\(program.id)")
                .offset(x: viewModel.programOffset(for: program, hourWidth: hourWidth, startTime: timelineStart))
                #else
                Button {
                    selectedProgramDetail = (program: program, channel: channel)
                } label: {
                    ProgramCell(
                        program: program,
                        width: viewModel.programWidth(for: program, hourWidth: hourWidth, startTime: timelineStart),
                        isScheduledRecording: isScheduled,
                        isCurrentlyRecording: isRecording,
                        isCatchupAvailable: catchupAvailable,
                        matchesKeyword: matchesKeywords,
                        leadingPadding: leadingPad
                    )
                }
                #if os(tvOS)
                .buttonStyle(TVGuideButtonStyle())
                .focusEffectDisabled()
                #else
                .buttonStyle(.plain)
                .contextMenu {
                    programContextMenu(program: program, channel: channel, isScheduled: isScheduled)
                }
                #endif
                .accessibilityIdentifier("guide-program-\(program.id)")
                .offset(x: viewModel.programOffset(for: program, hourWidth: hourWidth, startTime: timelineStart))
                #endif
            }

            // Now indicator
            nowIndicator(timelineStart: timelineStart)
        }
        .frame(width: hourWidth * CGFloat(viewModel.hoursToShow.count), height: rowHeight)
    }

    #if !os(tvOS)
    /// Right-click actions on a guide program (iOS long-press, macOS context menu).
    @ViewBuilder
    private func programContextMenu(program: Program, channel: Channel, isScheduled: Bool) -> some View {
                    if program.isCurrentlyAiring, let recId = viewModel.activeRecordingId(for: program, channelId: channel.id) {
                        let canPlay = UserPreferences.load().currentGPUAPI == .pixelbuffer
                        Button {
                            Task {
                                do {
                                    let url = try await appState.preparingStream {

                                        try await client.recordingStreamURL(recordingId: recId)

                                    }
                                    appState.playStream(url: url, title: program.name, recordingId: recId)
                                } catch {
                                    streamError = error.localizedDescription
                                }
                            }
                        } label: {
                            Label(canPlay ? "Watch from Beginning" : "Watch from Beginning (requires PixelBuffer)", systemImage: "play.fill")
                        }
                        .disabled(!canPlay)

                        Button {
                            playLiveChannel(channel)
                        } label: {
                            Label("Watch Live", systemImage: "dot.radiowaves.left.and.right")
                        }

                        if !appState.hideRecordings {
                            Button {
                                Task {
                                    try? await client.cancelRecording(recordingId: recId)
                                    await viewModel.reloadRecordings(client: client)
                                }
                            } label: {
                                Label("Cancel Recording", systemImage: "xmark.circle")
                            }
                        }
                    } else if !program.hasEnded && !appState.hideRecordings {
                        if isScheduled, let recId = viewModel.recordingId(for: program) {
                            Button {
                                Task {
                                    try? await client.cancelRecording(recordingId: recId)
                                    await viewModel.reloadRecordings(client: client)
                                }
                            } label: {
                                Label("Cancel Recording", systemImage: "xmark.circle")
                            }
                        } else {
                            Button {
                                Task {
                                    try? await client.scheduleRecording(program: program, channel: channel)
                                    await viewModel.reloadRecordings(client: client)
                                }
                            } label: {
                                Label("Record", systemImage: "record.circle")
                            }
                        }
                    }

                    Button {
                        selectedProgramDetail = (program: program, channel: channel)
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    }

    /// Schedules `program`, or cancels its recording when one is already set.
    private func toggleRecording(program: Program, channel: Channel) {
        Task {
            if viewModel.isScheduledRecording(program), let recId = viewModel.recordingId(for: program) {
                try? await client.cancelRecording(recordingId: recId)
            } else {
                try? await client.scheduleRecording(program: program, channel: channel)
            }
            await viewModel.reloadRecordings(client: client)
        }
    }
    #endif

    @ViewBuilder
    private func nowIndicator(timelineStart: Date) -> some View {
        let now = Date()
        if now >= timelineStart && now < timelineStart.addingTimeInterval(Double(viewModel.hoursToShow.count) * 3600) {
            let offset = CGFloat(now.timeIntervalSince(timelineStart) / 3600) * hourWidth
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 2)
                .offset(x: offset)
        }
    }

    @discardableResult
    private func updateScrollTarget(preferredTime: Date? = nil) -> String? {
        let calendar = Calendar.current
        let now = Date()
        let isToday = calendar.isDate(viewModel.selectedDate, inSameDayAs: now)
        let preferredTime = preferredTime.flatMap {
            calendar.isDate($0, inSameDayAs: viewModel.selectedDate) ? $0 : nil
        }

        // Store scroll target for text padding calculation
        let scrollTargetDate = GuideScrollHelper.calculateScrollTarget(
            currentTime: preferredTime ?? (isToday ? now : viewModel.timelineStart)
        )
        currentTimelineHour = scrollTargetDate

        // The regular guide starts today's timeline at the current hour, so it
        // needs no initial scroll. Catch-up keeps the whole day and opens at
        // the current half-hour, leaving the earlier schedule to its left.
        if preferredTime == nil && isToday && !viewModel.allowsPastDates {
            scrollTargetTime = nil
            scrollTargetId = nil
            return nil
        }

        let targetTime = preferredTime != nil
            ? scrollTargetDate
            : (isToday ? scrollTargetDate : viewModel.timelineStart)
        let targetHourComponent = calendar.component(.hour, from: targetTime)
        if let targetHour = viewModel.hoursToShow.first(where: { calendar.component(.hour, from: $0) == targetHourComponent }) {
            let targetId = GuideScrollHelper.calculateScrollId(currentTime: targetTime, targetHour: targetHour)
            // Set before the id: the id's onChange reads it.
            scrollTargetTime = targetTime
            scrollTargetId = targetId
            return targetId
        }
        scrollTargetTime = nil
        scrollTargetId = nil
        return nil
    }

    /// Pull-to-refresh (iOS/macOS) and the tvOS refresh button both land here:
    /// re-fetch channels/EPG/recordings so server-side changes show up without
    /// restarting the app (#118).
    private func refreshGuide() async {
        await viewModel.refresh(using: client)
        viewModel.updateKeywordMatches(keywords: keywords)
    }

    private func refreshRecordings() async {
        do {
            let (completed, recording, scheduled) = try await client.getAllRecordings()
            viewModel.recordings = completed + recording + scheduled
        } catch {
            // Silently fail - the grid just won't update the indicators
        }
    }

}

#if os(tvOS)
private struct TVImmediateSearchField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var requestFocus: Bool
    var useFocusedStyle: Bool
    var onFocusChange: (Bool) -> Void

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TVImmediateSearchField

        init(parent: TVImmediateSearchField) {
            self.parent = parent
        }

        @objc func textDidChange(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.text = text
        field.textColor = UIColor(MidnightPalette.ink)
        field.tintColor = UIColor(MidnightPalette.accent)
        // Header-sized, not the tvOS text field default.
        field.font = UIFont.systemFont(ofSize: Theme.scaledFont(22), weight: .semibold)
        field.borderStyle = .none
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .search
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 12
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.textColor = UIColor(useFocusedStyle ? MidnightPalette.selectedInk : MidnightPalette.ink)
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor(useFocusedStyle ? MidnightPalette.selectedSub : MidnightPalette.inkFaint)
            ]
        )

        if requestFocus {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}
#endif


#if os(macOS)
import AppKit

/// Installs an NSEvent local monitor while the guide is visible that locks
/// scroll-wheel gestures to whichever axis dominates the first event of a
/// gesture. Off-axis events are dropped (returned as nil) — AppKit doesn't
/// allow mutating an NSEvent's deltas, so cross-axis frames are simply
/// swallowed. The lock resets at every gesture begin / end.
private struct MacScrollDirectionalLockModifier: ViewModifier {
    @State private var monitor: Any?
    @State private var lockedAxis: Axis? = nil

    private enum Axis { case horizontal, vertical }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    switch event.phase {
                    case .began, .mayBegin:
                        lockedAxis = nil
                    case .ended, .cancelled:
                        lockedAxis = nil
                        return event
                    default:
                        break
                    }

                    let dx = abs(event.scrollingDeltaX)
                    let dy = abs(event.scrollingDeltaY)

                    if lockedAxis == nil {
                        // Need a meaningful delta before committing to an axis
                        if max(dx, dy) < 0.5 { return event }
                        lockedAxis = dx > dy ? .horizontal : .vertical
                        return event
                    }

                    switch lockedAxis! {
                    case .horizontal:
                        // Drop events whose dominant axis is vertical
                        return dy > dx ? nil : event
                    case .vertical:
                        return dx > dy ? nil : event
                    }
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
                lockedAxis = nil
            }
    }
}
#endif

#if os(iOS)
import UIKit

/// Walks up the SwiftUI view hierarchy to find the enclosing UIScrollView and
/// enables `isDirectionalLockEnabled`, so panning locks to whichever axis the
/// gesture started on (no diagonal scrolling).
private struct ScrollViewDirectionalLock: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            var parent: UIView? = view.superview
            while let current = parent {
                if let scrollView = current as? UIScrollView {
                    scrollView.isDirectionalLockEnabled = true
                    return
                }
                parent = current.superview
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif


#Preview {
    GuideView()
        .environmentObject(PVRClient())
        .environmentObject(AppState())
        .environmentObject(EPGCache())
        #if os(iOS) || os(macOS)
        .environmentObject(GuideViewModel())
        #endif
        .preferredColorScheme(.dark)
}
