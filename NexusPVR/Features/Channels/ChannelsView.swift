//
//  ChannelsView.swift
//  nextpvr-apple-client
//
//  Responsive grid of channels with logo, channel name, and the current
//  EPG program. Reuses `EPGCache` (no extra network calls, no 50-channel
//  cap) and the project's `CachedAsyncImage` + Theme constants.
//

import SwiftUI
#if os(tvOS)
import UIKit
#endif

struct ChannelsView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var epgCache: EPGCache
    #if os(tvOS)
    @Environment(\.requestSidebarFocus) private var requestSidebarFocus
    #endif

    @State private var streamError: String?
    @State private var now = Date()
    @State private var showFilters = false
    #if os(tvOS)
    @FocusState private var focusedChannelId: Int?
    @State private var requestTVSearchKeyboard = false
    #if DISPATCHERPVR
    @State private var headerDrawerKind: ChannelsDrawerKind?
    @FocusState private var focusedDrawerItemId: String?
    #endif
    #endif

    #if os(tvOS) && DISPATCHERPVR
    /// Which header filter is currently expanded as a drawer, matching the
    /// guide view's group/profile drawer UX.
    private enum ChannelsDrawerKind { case group, profile }
    #endif

    /// Minimum 2 visible columns on iPhone, scales up for iPad / macOS / tvOS.
    private var columns: [GridItem] {
        #if os(tvOS)
        return [
            GridItem(.adaptive(minimum: 320, maximum: 420), spacing: Theme.spacingMD)
        ]
        #else
        return [
            GridItem(.adaptive(minimum: 160, maximum: 240), spacing: Theme.spacingMD)
        ]
        #endif
    }

    /// Use the full all-channels list rather than `epgCache.visibleChannels`.
    /// `visibleChannels` is narrowed by guide profile reloads (Dispatcharr
    /// summary endpoint can return a server-side profile-filtered subset),
    /// which would make the Channels page mysteriously lose channels when
    /// the user changes their guide profile. `channels` is the stable,
    /// unfiltered source.
    private var visibleChannels: [Channel] {
        var result = epgCache.channels
        #if DISPATCHERPVR
        if let profileId = appState.guideProfileFilter,
           let profile = epgCache.channelProfiles.first(where: { $0.id == profileId }) {
            let channelIds = Set(profile.channels)
            result = result.filter { channelIds.contains($0.id) }
        } else if let groupId = appState.guideGroupFilter {
            result = result.filter { $0.groupId == groupId }
        }
        #endif
        guard !appState.guideChannelFilter.isEmpty else { return result }
        let query = appState.guideChannelFilter.lowercased()
        return result.filter { channel in
            channel.name.lowercased().contains(query) ||
            String(channel.number).contains(query)
        }
    }

    #if DISPATCHERPVR
    private var hasFilterData: Bool {
        !epgCache.channelProfiles.isEmpty || !populatedGroups.isEmpty
    }

    private var hasActiveFilters: Bool {
        appState.guideProfileFilter != nil ||
        appState.guideGroupFilter != nil ||
        !appState.guideChannelFilter.isEmpty
    }

    private var populatedGroups: [ChannelGroup] {
        epgCache.channelGroups.filter { group in
            epgCache.channels.contains { $0.groupId == group.id }
        }
    }

    private var selectedGroupLabel: String {
        if let groupId = appState.guideGroupFilter,
           let group = epgCache.channelGroups.first(where: { $0.id == groupId }) {
            return group.name
        }
        return "All Groups"
    }

    private var selectedProfileLabel: String {
        if let profileId = appState.guideProfileFilter,
           let profile = epgCache.channelProfiles.first(where: { $0.id == profileId }) {
            return profile.name
        }
        return "All Profiles"
    }
    #endif

    private var firstVisibleChannelId: Int? {
        visibleChannels.first?.id
    }

    var body: some View {
        #if os(tvOS)
        content
            .accessibilityIdentifier("channels-view")
            .alert("Error", isPresented: .constant(streamError != nil)) {
                Button("OK") { streamError = nil }
            } message: {
                if let error = streamError { Text(error) }
            }
            .background(.ultraThinMaterial)
            .onMoveCommand { direction in
                #if DISPATCHERPVR
                if headerDrawerKind != nil {
                    // Up/down navigates the drawer list (handled by the focus
                    // engine); left/right collapses it, like the guide view.
                    if direction == .left || direction == .right {
                        closeDrawer()
                    }
                    return
                }
                #endif
                if direction == .left { requestSidebarFocus() }
            }
            .onExitCommand {
                #if DISPATCHERPVR
                if headerDrawerKind != nil {
                    closeDrawer()
                    return
                }
                #endif
                requestSidebarFocus()
            }
            .task {
                focusedChannelId = firstVisibleChannelId
                await tickCurrentTime()
            }
            .onChange(of: firstVisibleChannelId) { _, id in
                guard let focusedChannelId else {
                    self.focusedChannelId = id
                    return
                }
                if !visibleChannels.contains(where: { $0.id == focusedChannelId }) {
                    self.focusedChannelId = id
                }
            }
        #else
        NavigationStack {
            content
            .navigationTitle("Channels")
            .accessibilityIdentifier("channels-view")
            #if DISPATCHERPVR && !os(tvOS)
            .toolbar {
                if hasFilterData {
                    ToolbarItem(placement: .automatic) {
                        filterToggleButton
                    }
                }
            }
            #endif
            #if os(iOS)
            .searchable(text: $appState.guideChannelFilter, prompt: "Search channels")
            .sidebarMenuToolbar()
            #elseif os(macOS)
            .searchable(text: $appState.guideChannelFilter, prompt: "Search channels")
            #endif
            .alert("Error", isPresented: .constant(streamError != nil)) {
                Button("OK") { streamError = nil }
            } message: {
                if let error = streamError { Text(error) }
            }
        }
        .background(Theme.background)
        .task {
            await tickCurrentTime()
        }
        #endif
    }

    private var content: some View {
        Group {
            if !epgCache.hasLoaded {
                loadingView
            } else if let error = epgCache.error, epgCache.channels.isEmpty {
                errorView(error)
            } else if visibleChannels.isEmpty {
                emptyContent
            } else {
                channelGrid
            }
        }
    }

    private func tickCurrentTime() async {
        // Re-evaluate "current" once a minute so progress bars animate
        // and programs flip over as the day progresses.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            now = Date()
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: Theme.spacingMD) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.accent)
            Text("Loading channels...")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.warning)
            Text("Unable to load channels")
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

    /// True when the empty state contains its own focusable control (the
    /// "Clear Filters" button). In that case we must NOT apply
    /// `tvOSFocusableEmptyState()`, because it wraps the whole empty view in an
    /// outer focusable `Button` that swallows the inner button's focus — making
    /// the filter impossible to reset on tvOS.
    private var emptyStateHasFocusableButton: Bool {
        #if DISPATCHERPVR
        return hasActiveFilters
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var emptyView: some View {
        if emptyStateHasFocusableButton {
            emptyStateBody
        } else {
            emptyStateBody
                .tvOSFocusableEmptyState()
        }
    }

    private var emptyStateBody: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "tv")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if epgCache.channels.isEmpty {
                Text(Brand.configureServerMessage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            #if DISPATCHERPVR
            if hasActiveFilters {
                Button("Clear Filters") {
                    appState.guideChannelFilter = ""
                    appState.guideGroupFilter = nil
                    appState.guideProfileFilter = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(tvOS)
        // Group the empty state as a focus section so the centered "Clear
        // Filters" button is reachable from the top-left search field — plain
        // directional focus can't bridge that off-axis jump on tvOS.
        .focusSection()
        #endif
    }

    private var emptyTitle: String {
        #if DISPATCHERPVR
        return hasActiveFilters ? "No channels match filters" : "No channels available"
        #else
        return appState.guideChannelFilter.isEmpty ? "No channels available" : "No matches"
        #endif
    }

    private var emptyContent: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            tvOSFilterBar
            #else
            #if DISPATCHERPVR
            if showFilters && hasFilterData {
                filterPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            #endif
            #endif
            emptyView
        }
    }

    // MARK: - Grid

    private var channelGrid: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            tvOSFilterBar
            #else
            #if DISPATCHERPVR
            if showFilters && hasFilterData {
                filterPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            #endif
            #endif

            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.spacingMD) {
                    ForEach(visibleChannels) { channel in
                        Button {
                            play(channel: channel)
                        } label: {
                            ChannelGridCard(
                                channel: channel,
                                currentProgram: epgCache.currentProgram(for: channel, at: now)
                            )
                        }
                        .accessibilityIdentifier("channel-card-\(channel.id)")
                        #if os(tvOS)
                        .buttonStyle(ChannelGridCardButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedChannelId, equals: channel.id)
                        .zIndex(focusedChannelId == channel.id ? 1 : 0)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(Theme.spacingMD)
            }
        }
    }

    private func play(channel: Channel) {
        Task {
            do {
                let programName = epgCache.currentProgram(for: channel, at: now)?.name ?? "Live"
                // Always go through `client.liveStreamURL(channelId:)` —
                // the raw `channel.streamURL` from the channel summary
                // response isn't guaranteed to be absolute or to carry a
                // valid session, so preferring it can produce unplayable
                // URLs. The PVR client knows the correct base URL, query
                // parameters, and session for live playback.
                let url = try await client.liveStreamURL(channelId: channel.id)
                appState.playStream(
                    url: url,
                    title: "\(channel.name) - \(programName)",
                    channelId: channel.id,
                    channelName: channel.name
                )
            } catch {
                streamError = error.localizedDescription
            }
        }
    }

    #if os(tvOS)
    private var tvOSFilterBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.spacingLG) {
                tvOSSearchField
                #if DISPATCHERPVR
                if hasFilterData {
                    Rectangle()
                        .fill(Theme.surfaceHighlight)
                        .frame(width: 1, height: 30)
                    tvOSDispatcharrField(
                        icon: "folder.fill",
                        title: "Group",
                        value: selectedGroupLabel,
                        kind: .group
                    )
                    tvOSDispatcharrField(
                        icon: "person.fill",
                        title: "Profile",
                        value: selectedProfileLabel,
                        kind: .profile
                    )
                }
                #endif

                Spacer()
            }
            .padding(.horizontal, Theme.spacingLG)
            .frame(minHeight: 62)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.surfaceHighlight.opacity(0.5), lineWidth: 1)
            )

            #if DISPATCHERPVR
            if headerDrawerKind != nil {
                tvOSHeaderDrawer
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            #endif
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .focusSection()
    }

    /// The visible search "field" is a focusable `Button` so it picks up the
    /// guide-style highlight (via `TVPillFieldButtonStyle`) instead of the raw
    /// system focus halo. Actual text entry is handled by a zero-size,
    /// non-focusable `UITextField` that becomes first responder (and presents
    /// the system keyboard) when the button is selected.
    private var tvOSSearchField: some View {
        Button {
            requestTVSearchKeyboard = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(appState.guideChannelFilter.isEmpty ? "Search channels..." : appState.guideChannelFilter)
                    .lineLimit(1)
                    .opacity(appState.guideChannelFilter.isEmpty ? 0.6 : 1)
                Spacer(minLength: 0)
            }
            .frame(width: 356, height: 36)
        }
        .buttonStyle(TVPillFieldButtonStyle(unfocusedForeground: Theme.textTertiary))
        .focusEffectDisabled()
        .accessibilityIdentifier("channels-view-field")
        .background(
            ChannelsTVImmediateSearchField(
                text: $appState.guideChannelFilter,
                placeholder: "Search channels...",
                requestFocus: $requestTVSearchKeyboard,
                onFocusChange: { focused in
                    if !focused {
                        requestTVSearchKeyboard = false
                    }
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    #if DISPATCHERPVR
    private func tvOSDispatcharrField(icon: String, title: String, value: String, kind: ChannelsDrawerKind) -> some View {
        Button {
            if headerDrawerKind == kind {
                closeDrawer()
            } else {
                openDrawer(kind)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text("\(title): \(value)")
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .buttonStyle(TVPillFieldButtonStyle(
            unfocusedForeground: value.hasPrefix("All ") ? Theme.textTertiary : Theme.accent
        ))
        .focusEffectDisabled()
        .accessibilityLabel("Show \(title.lowercased()) filters")
    }

    // MARK: - tvOS Group/Profile Drawer (matches guide view UX)

    /// Vertical drawer listing the options for the open filter. Mirrors the
    /// guide's `tvOSHeaderDrawer`: a titled list with a checkmark on the
    /// highlighted row. Each row is a focusable button so it works with the
    /// channels grid's native focus model.
    private var tvOSHeaderDrawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerDrawerKind == .group ? "Select Group" : "Select Profile")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(currentDrawerItems, id: \.id) { item in
                        Button {
                            applyDrawerSelection(item.value)
                        } label: {
                            Text(item.label)
                        }
                        .buttonStyle(ChannelsDrawerItemButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedDrawerItemId, equals: item.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 360)
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .focusSection()
    }

    private var currentDrawerItems: [(id: String, label: String, value: Int?)] {
        switch headerDrawerKind {
        case .group:
            return [(id: "group-all", label: "All Groups", value: nil)] +
                   populatedGroups.map { (id: "group-\($0.id)", label: $0.name, value: $0.id) }
        case .profile:
            return [(id: "profile-all", label: "All Profiles", value: nil)] +
                   epgCache.channelProfiles.map { (id: "profile-\($0.id)", label: $0.name, value: $0.id) }
        case .none:
            return []
        }
    }

    private var currentDrawerSelectedItemId: String? {
        let value: Int? = (headerDrawerKind == .group)
            ? appState.guideGroupFilter
            : appState.guideProfileFilter
        return currentDrawerItems.first(where: { $0.value == value })?.id
    }

    private func openDrawer(_ kind: ChannelsDrawerKind) {
        withAnimation(.easeInOut(duration: Theme.animationDuration)) {
            headerDrawerKind = kind
        }
        // Defer until the drawer has rendered so the focus lands on the
        // currently-selected option (like the guide's initial cursor).
        DispatchQueue.main.async {
            focusedDrawerItemId = currentDrawerSelectedItemId
        }
    }

    private func closeDrawer() {
        withAnimation(.easeInOut(duration: Theme.animationDuration)) {
            headerDrawerKind = nil
        }
    }

    private func applyDrawerSelection(_ value: Int?) {
        switch headerDrawerKind {
        case .group:
            appState.guideGroupFilter = value
            if value != nil {
                appState.guideProfileFilter = nil
                appState.guideChannelFilter = ""
            }
        case .profile:
            appState.guideProfileFilter = value
            if value != nil {
                appState.guideGroupFilter = nil
                appState.guideChannelFilter = ""
            }
        case .none:
            break
        }
        closeDrawer()
    }
    #endif
    #endif

    #if DISPATCHERPVR
    private var filterToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: Theme.animationDuration)) {
                showFilters.toggle()
            }
        } label: {
            Image(systemName: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(hasActiveFilters ? Theme.accent : Theme.textPrimary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showFilters ? "Hide filters" : "Show filters")
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !epgCache.channelProfiles.isEmpty {
                filterRow(
                    label: "Profile",
                    items: epgCache.channelProfiles.map { (id: $0.id, name: $0.name) },
                    selectedId: appState.guideProfileFilter
                ) { id in
                    appState.guideProfileFilter = id
                    if id != nil {
                        appState.guideGroupFilter = nil
                        appState.guideChannelFilter = ""
                    }
                }
            }

            if !populatedGroups.isEmpty {
                filterRow(
                    label: "Group",
                    items: populatedGroups.map { (id: $0.id, name: $0.name) },
                    selectedId: appState.guideGroupFilter
                ) { id in
                    appState.guideGroupFilter = id
                    if id != nil {
                        appState.guideProfileFilter = nil
                        appState.guideChannelFilter = ""
                    }
                }
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private func filterRow(
        label: String,
        items: [(id: Int, name: String)],
        selectedId: Int?,
        onSelect: @escaping (Int?) -> Void
    ) -> some View {
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
    #endif
}

// MARK: - Channel Grid Card

/// Card view used inside the Channels grid. Mirrors the styling of
/// `LiveTVView.ChannelCard` but pulls program data from `EPGCache`
/// (so it never duplicates the per-channel `getListings` request and
/// is not limited to 50 channels).
struct ChannelGridCard: View {
    @EnvironmentObject private var client: PVRClient
    let channel: Channel
    let currentProgram: Program?
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // Logo header
            HStack(alignment: .top) {
                CachedAsyncImage(url: try? client.channelIconURL(channelId: channel.id)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "tv")
                        .font(.title)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(width: Theme.iconSize, height: Theme.iconSize)

                Spacer(minLength: Theme.spacingSM)

                if let program = currentProgram, let sport = SportDetector.detect(from: program) {
                    SportIconView(sport: sport, size: Theme.iconSize * 0.5)
                }
            }

            Text(channel.name)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if let program = currentProgram {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(program.cleanName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        if program.isNew { NewBadge() }
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Theme.surfaceHighlight)
                            Rectangle()
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * program.progress())
                        }
                    }
                    .frame(height: 3)
                    .clipShape(Capsule())
                }
            } else {
                Text("No program info")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMD)
                .fill(channelInteriorGradient)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
    }

    private var channelInteriorGradient: LinearGradient {
        LinearGradient(
            colors: [
                Theme.surfaceElevated,
                Theme.accent.opacity(0.14),
                Theme.surface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    ChannelsView()
        .environmentObject(PVRClient())
        .environmentObject(AppState())
        .environmentObject(EPGCache())
        .preferredColorScheme(.dark)
}

#if os(tvOS)
/// tvOS `ButtonStyle` for the channel grid cards. Draws the same focus
/// treatment as the guide's program cells (accent border + accent glow +
/// subtle scale) and — because it is a custom style — fully replaces the
/// default tvOS button "platter"/glossy focus effect that `.plain` keeps.
struct ChannelGridCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChannelGridCardFocusWrapper { configuration.label }
    }
}

private struct ChannelGridCardFocusWrapper<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMD)
                    .strokeBorder(isFocused ? Theme.accent.opacity(0.95) : Color.clear, lineWidth: 3)
            }
            .shadow(color: isFocused ? Theme.accent.opacity(0.22) : .clear, radius: 10, x: 0, y: 1)
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
    }
}

/// tvOS `ButtonStyle` for the pill-shaped fields in the filter bar (search and
/// the Dispatcharr group/profile chips). Mirrors the guide's `tvOSSearchField`
/// / `tvOSDispatcharrField` look: white fill + dark text + scale when focused.
struct TVPillFieldButtonStyle: ButtonStyle {
    var unfocusedForeground: Color

    func makeBody(configuration: Configuration) -> some View {
        TVPillFieldFocusWrapper(unfocusedForeground: unfocusedForeground) {
            configuration.label
        }
    }
}

private struct TVPillFieldFocusWrapper<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let unfocusedForeground: Color
    let content: () -> Content

    init(unfocusedForeground: Color, @ViewBuilder content: @escaping () -> Content) {
        self.unfocusedForeground = unfocusedForeground
        self.content = content
    }

    var body: some View {
        content()
            .foregroundStyle(isFocused ? Color(white: 0.1) : unfocusedForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? Color.white : Theme.surfaceElevated.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? Color.clear : Theme.surfaceHighlight, lineWidth: 1)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
    }
}

#if DISPATCHERPVR
/// tvOS `ButtonStyle` for rows in the group/profile drawer. Highlighted
/// (focused) row shows a filled checkmark + accent border, matching the guide
/// view's `tvOSHeaderDrawer` rows.
struct ChannelsDrawerItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChannelsDrawerItemFocusWrapper { configuration.label }
    }
}

private struct ChannelsDrawerItemFocusWrapper<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isFocused ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isFocused ? Theme.accent : Theme.textTertiary)
            content()
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(isFocused ? Theme.textPrimary : Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isFocused ? Theme.surfaceElevated : Theme.surface.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Theme.accent : Theme.surfaceHighlight.opacity(0.5), lineWidth: isFocused ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}
#endif

/// Zero-size `UITextField` that only ever drives the on-screen keyboard for the
/// search field. `canBecomeFocused` is `false` so the focus engine never lands
/// on it — the visible focusable element is the SwiftUI `Button` in front of it.
private final class NonFocusableTextField: UITextField {
    override var canBecomeFocused: Bool { false }
}

private struct ChannelsTVImmediateSearchField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var requestFocus: Bool
    var onFocusChange: (Bool) -> Void

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ChannelsTVImmediateSearchField

        init(parent: ChannelsTVImmediateSearchField) {
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
        let field = NonFocusableTextField(frame: .zero)
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.text = text
        field.textColor = UIColor.white
        field.tintColor = UIColor.white
        field.borderStyle = .none
        field.returnKeyType = .search
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder

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
