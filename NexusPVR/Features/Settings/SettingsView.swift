//
//  SettingsView.swift
//  nextpvr-apple-client
//
//  Settings main view
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    #if os(tvOS)
    @Environment(\.requestSidebarFocus) private var requestSidebarFocus
    #endif
    @EnvironmentObject private var epgCache: EPGCache
    @State private var showingUnlinkConfirm = false
    @State private var seekBackwardSeconds: Int = UserPreferences.load().seekBackwardSeconds
    @State private var seekForwardSeconds: Int = UserPreferences.load().seekForwardSeconds
    @State private var audioChannels: String = UserPreferences.load().audioChannels
    @State private var tvosGPUAPI: GPUAPI = UserPreferences.load().tvosGPUAPI
    @State private var iosGPUAPI: GPUAPI = UserPreferences.load().iosGPUAPI
    @State private var macosGPUAPI: GPUAPI = UserPreferences.load().macosGPUAPI
    @State private var subtitleMode: SubtitleMode = UserPreferences.load().subtitleMode
    @State private var subtitleSize: SubtitleSize = UserPreferences.load().subtitleSize
    @State private var subtitleBackground: Bool = UserPreferences.load().subtitleBackground
    @State private var deinterlaceMode: DeinterlaceMode = UserPreferences.load().deinterlaceMode
    #if !DISPATCHERPVR
    @State private var streamQuality: StreamQuality = UserPreferences.load().streamQuality
    #endif
    @State private var landingTab: LandingTabOption = UserPreferences.load().landingTab
    @State private var hideRecordings: Bool = UserPreferences.load().hideRecordings
    @State private var theme: AppTheme = UserPreferences.load().theme
    #if os(tvOS)
    @State private var uiFontSize: UIFontSize = UserPreferences.load().uiFontSize
    #endif
    #if DISPATCHERPVR
    @State private var guideShowGroupsInSidebar: Bool = UserPreferences.load().guideShowGroupsInSidebar
    @State private var guideGroupIds: [Int] = UserPreferences.load().guideGroupIds
    @State private var guideShowProfilesInSidebar: Bool = UserPreferences.load().guideShowProfilesInSidebar
    @State private var guideProfileIds: [Int] = UserPreferences.load().guideProfileIds
    #endif
    @ObservedObject private var eventLog: NetworkEventLog

    init(eventLog: NetworkEventLog = Dependencies.networkEventLog) {
        self._eventLog = ObservedObject(wrappedValue: eventLog)
    }
    #if os(tvOS)
    @State private var activeTVPopup: TVSettingsPopup?
    @FocusState private var popupFocusedItemID: String?
    @State private var showingTVEventLog = false
    #endif
    #if DEBUG
    @State private var debugStreamEnabled: Bool = UserDefaults.standard.bool(forKey: "debugStreamEnabled")
    @State private var debugStreamURL: String = UserDefaults.standard.string(forKey: "debugStreamURL") ?? "http://localhost:9000/video"
    @State private var debugStreamAsRecording: Bool = UserDefaults.standard.bool(forKey: "debugStreamAsRecording")
    #endif

    #if os(tvOS)
    private enum TVSettingsPopup: Hashable {
        case server
        case seekBackward
        case seekForward
        case audioOutput
        case subtitleMode
        case subtitleSize
        case subtitleBackground
        case deinterlace
        #if !DISPATCHERPVR
        case streamQuality
        #endif
        case renderer
        case landingTab
        case hideRecordings
        case theme
        case uiFontSize
    }
    #endif

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            tvOSContent
            #else
            List {
                serverSection
                generalSection
                playbackSection
                #if DISPATCHERPVR
                guideSection
                #endif
                #if DEBUG
                debugStreamSection
                #endif
                eventLogLinkSection
            }
            .safeAreaInset(edge: .bottom) {
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacingSM)
            }
            .navigationTitle("Settings")
            #if os(macOS)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            #elseif os(iOS)
            .listStyle(.insetGrouped)
            .sidebarMenuToolbar()
            #endif
            #endif
        }
        .accessibilityIdentifier("settings-view")
        #if os(tvOS)
        .background(.ultraThinMaterial)
        #else
        .background(Theme.background)
        #endif
    }

    #if os(tvOS)
    private var tvOSContent: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingXL) {
                    HStack(alignment: .center, spacing: Theme.spacingMD) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.guideNowPlaying.opacity(0.95))
                                .frame(width: 56, height: 56)
                            Image(systemName: "gearshape.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Settings")
                                .font(.tvScaled(size: 38, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Playback, server and diagnostics")
                                .font(.tvScaled(size: 22, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Theme.spacingSM)
                    .padding(.vertical, Theme.spacingSM)

                    TVSettingsSection(
                        title: "\(Brand.serverName) Server",
                        icon: "server.rack"
                    ) {
                        tvSettingsRow(
                            title: "Server",
                            value: serverSummaryValue,
                            icon: "network",
                            detail: serverRowDetail
                        ) {
                            activeTVPopup = .server
                        }
                    }
                    .focusSection()

                    TVSettingsSection(
                        title: "General",
                        icon: "gearshape"
                    ) {
                        VStack(spacing: Theme.spacingMD) {
                            tvSettingsRow(
                                title: "Landing Page",
                                value: displayedLandingTab.label,
                                icon: "house.fill"
                            ) {
                                activeTVPopup = .landingTab
                            }
                            tvSettingsRow(
                                title: "Theme",
                                value: theme.label,
                                icon: theme.icon
                            ) {
                                activeTVPopup = .theme
                            }
                            tvSettingsRow(
                                title: "Text Size",
                                value: uiFontSize.displayName,
                                icon: "textformat.size",
                                detail: "Scales text and rows across the app"
                            ) {
                                activeTVPopup = .uiFontSize
                            }
                            tvSettingsRow(
                                title: "Hide Recording Features",
                                value: hideRecordings ? "On" : "Off",
                                icon: "record.circle"
                            ) {
                                activeTVPopup = .hideRecordings
                            }
                        }
                    }
                    .focusSection()

                    TVSettingsSection(
                        title: "Playback",
                        icon: "play.circle"
                    ) {
                        VStack(spacing: Theme.spacingMD) {
                            tvSettingsRow(
                                title: "Seek Backward",
                                value: "\(seekBackwardSeconds)s",
                                icon: "gobackward"
                            ) {
                                activeTVPopup = .seekBackward
                            }
                            tvSettingsRow(
                                title: "Seek Forward",
                                value: "\(seekForwardSeconds)s",
                                icon: "goforward"
                            ) {
                                activeTVPopup = .seekForward
                            }
                            tvSettingsRow(
                                title: "Audio Output",
                                value: audioChannels == "stereo" ? "Stereo" : "Auto",
                                icon: "speaker.wave.2"
                            ) {
                                activeTVPopup = .audioOutput
                            }
                            #if !DISPATCHERPVR
                            tvSettingsRow(
                                title: "Live TV Quality",
                                value: streamQuality.label,
                                icon: streamQuality.icon,
                                detail: streamQualityDescription
                            ) {
                                activeTVPopup = .streamQuality
                            }
                            #endif
                            tvSettingsRow(
                                title: "Deinterlacing",
                                value: deinterlaceMode.label,
                                icon: deinterlaceMode.icon,
                                detail: deinterlaceDescription
                            ) {
                                activeTVPopup = .deinterlace
                            }
                            tvSettingsRow(
                                title: "Subtitles",
                                value: subtitleMode == .auto ? "Auto" : "Manual",
                                icon: "captions.bubble",
                                detail: subtitleModeDescription
                            ) {
                                activeTVPopup = .subtitleMode
                            }
                            tvSettingsRow(
                                title: "Subtitle Size",
                                value: subtitleSize.displayName,
                                icon: "textformat.size"
                            ) {
                                activeTVPopup = .subtitleSize
                            }
                            tvSettingsRow(
                                title: "Subtitle Background",
                                value: subtitleBackground ? "On" : "Off",
                                icon: "rectangle.fill"
                            ) {
                                activeTVPopup = .subtitleBackground
                            }
                            tvSettingsRow(
                                title: "Renderer",
                                value: rendererName(for: tvosGPUAPI),
                                icon: "display.2",
                                detail: rendererDescription(for: tvosGPUAPI)
                            ) {
                                activeTVPopup = .renderer
                            }
                        }
                    }
                    .focusSection()

                #if DISPATCHERPVR
                    tvOSGuideSettingsSection
                        .focusSection()

                #endif

                #if DEBUG
                    TVSettingsSection(
                        title: "Debug",
                        icon: "ladybug"
                    ) {
                        VStack(spacing: Theme.spacingMD) {
                            Toggle("Test Stream", isOn: $debugStreamEnabled)
                                .onChange(of: debugStreamEnabled) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "debugStreamEnabled")
                                }

                            if debugStreamEnabled {
                                HStack(spacing: 8) {
                                    TextField("Stream URL", text: $debugStreamURL)
                                        .autocorrectionDisabled()
                                        .onChange(of: debugStreamURL) { newValue in
                                            UserDefaults.standard.set(newValue, forKey: "debugStreamURL")
                                        }
                                }

                                Toggle("Play as Recording", isOn: $debugStreamAsRecording)
                                    .onChange(of: debugStreamAsRecording) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "debugStreamAsRecording")
                                    }

                                Button {
                                    if let url = URL(string: debugStreamURL) {
                                        appState.playStream(
                                            url: url,
                                            title: debugStreamAsRecording ? "Test Recording" : "Test Stream",
                                            recordingId: debugStreamAsRecording ? -1 : nil
                                        )
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "play.circle")
                                            .foregroundStyle(Theme.accent)
                                        Text(debugStreamAsRecording ? "Play Test Recording" : "Play Test Stream")
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(Theme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                    .focusSection()
                #endif

                    tvSettingsActionRow(
                        title: "Event Log",
                        value: "\(eventLog.events.count)",
                        icon: "list.bullet.rectangle",
                        action: {
                            showingTVEventLog = true
                        }
                    )
                    .focusSection()

                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        .font(.tvScaled(size: 18, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.spacingMD)

                }
                .padding(.vertical, Theme.spacingXL)
                .padding(.horizontal, 36)
                .background {
                    NavigationLink(isActive: $showingTVEventLog) {
                        EventLogView()
                    } label: {
                        EmptyView()
                    }
                    .hidden()
                }
            }
            .allowsHitTesting(activeTVPopup == nil)
            .opacity(activeTVPopup == nil ? 1 : 0.6)

            if let activeTVPopup {
                tvSettingsPopup(for: activeTVPopup)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: activeTVPopup)
        .onAppear {
            appState.tvosBlocksSidebarExitCommand = activeTVPopup != nil || showingTVEventLog
            appState.tvosSettingsHasPopup = activeTVPopup != nil
            appState.tvosSettingsShowingEventLog = showingTVEventLog
        }
        .onChange(of: activeTVPopup) { _ in
            appState.tvosBlocksSidebarExitCommand = activeTVPopup != nil || showingTVEventLog
            appState.tvosSettingsHasPopup = activeTVPopup != nil
        }
        .onChange(of: showingTVEventLog) { _ in
            appState.tvosBlocksSidebarExitCommand = activeTVPopup != nil || showingTVEventLog
            appState.tvosSettingsShowingEventLog = showingTVEventLog
        }
        .onChange(of: appState.tvosSettingsDismissPopupRequest) { _ in
            activeTVPopup = nil
        }
        .onChange(of: appState.tvosSettingsDismissEventLogRequest) { _ in
            showingTVEventLog = false
        }
        .onExitCommand {
            if activeTVPopup != nil {
                activeTVPopup = nil
            } else if showingTVEventLog {
                showingTVEventLog = false
            } else {
                requestSidebarFocus()
            }
        }
        .onMoveCommand { direction in
            guard direction == .left,
                  activeTVPopup == nil,
                  !showingTVEventLog else { return }
            requestSidebarFocus()
        }
    }

    private func tvSettingsRow(
        title: String,
        value: String,
        icon: String,
        detail: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMD) {
                Image(systemName: icon)
                    .font(.tvScaled(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.tvScaled(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(value)
                        .font(.tvScaled(size: 20, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.tvScaled(size: 16, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.tvScaled(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingMD)
            .background(Theme.guideNowPlaying.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        }
        .buttonStyle(TVSettingsRowButtonStyle())
    }

    private func tvSettingsActionRow(
        title: String,
        value: String,
        icon: String,
        detail: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMD) {
                Image(systemName: icon)
                    .font(.tvScaled(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.tvScaled(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(value)
                        .font(.tvScaled(size: 20, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.tvScaled(size: 16, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.tvScaled(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingMD)
            .background(Theme.guideNowPlaying.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        }
        .buttonStyle(TVSettingsRowButtonStyle())
    }

    /// tvOS sub-line under the Server row showing the server's public IP
    /// and geo location (#112). The full address line already shows the
    /// host + status; the detail line below it carries the environment
    /// info so the Network panel is no longer needed.
    #endif

    #if os(tvOS) && DISPATCHERPVR
    private var tvOSGuideSettingsSection: some View {
        TVSettingsSection(
            title: "Guide",
            icon: "rectangle.grid.1x2"
        ) {
            VStack(spacing: Theme.spacingMD) {
                Toggle("Show Groups in Sidebar", isOn: $guideShowGroupsInSidebar)
                    .font(.tvScaled(size: 24, weight: .semibold))
                    .modifier(TVGuideSidebarToggleForegroundStyle())
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingSM)
                    .background(Theme.guideNowPlaying.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
                    .onChange(of: guideShowGroupsInSidebar) { newValue in
                        var prefs = UserPreferences.load()
                        prefs.guideShowGroupsInSidebar = newValue
                        prefs.save()
                        if !newValue {
                            appState.guideGroupFilter = nil
                            appState.guideChannelFilter = ""
                        }
                        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
                    }

                if guideShowGroupsInSidebar {
                    if epgCache.channelGroups.isEmpty {
                        tvOSGuideStatusRow("No channel groups available")
                    } else {
                        let populatedGroups = epgCache.channelGroups.filter { group in
                            epgCache.guideSidebarChannels.contains { $0.groupId == group.id }
                        }
                        if populatedGroups.isEmpty {
                            tvOSGuideStatusRow("No channels in any group")
                        } else {
                            Text("Included Groups")
                                .font(.tvScaled(size: 18, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.spacingMD)

                            ForEach(populatedGroups) { group in
                                tvOSGuideGroupToggleRow(group: group)
                            }
                        }
                    }
                }

                Toggle("Show Profiles in Sidebar", isOn: $guideShowProfilesInSidebar)
                    .font(.tvScaled(size: 24, weight: .semibold))
                    .modifier(TVGuideSidebarToggleForegroundStyle())
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingSM)
                    .background(Theme.guideNowPlaying.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
                    .onChange(of: guideShowProfilesInSidebar) { newValue in
                        var prefs = UserPreferences.load()
                        prefs.guideShowProfilesInSidebar = newValue
                        prefs.save()
                        if !newValue {
                            appState.guideProfileFilter = nil
                            appState.guideChannelFilter = ""
                        }
                        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
                    }

                if guideShowProfilesInSidebar {
                    if epgCache.channelProfiles.isEmpty {
                        tvOSGuideStatusRow("No channel profiles available")
                    } else {
                        let populatedProfiles = epgCache.channelProfiles.filter { profile in
                            epgCache.guideSidebarChannels.contains { profile.channels.contains($0.id) }
                        }
                        if populatedProfiles.isEmpty {
                            tvOSGuideStatusRow("No channels in any profile")
                        } else {
                            Text("Included Profiles")
                                .font(.tvScaled(size: 18, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.spacingMD)

                            ForEach(populatedProfiles) { profile in
                                tvOSGuideProfileToggleRow(profile: profile)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tvOSGuideStatusRow(_ text: String) -> some View {
        Text(text)
            .font(.tvScaled(size: 20, weight: .regular))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingMD)
            .background(Theme.guideNowPlaying.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
    }

    private func tvOSGuideGroupToggleRow(group: ChannelGroup) -> some View {
        let isSelected = guideGroupIds.contains(group.id)

        return Button {
            if isSelected {
                guideGroupIds.removeAll { $0 == group.id }
            } else {
                guideGroupIds.append(group.id)
            }

            var prefs = UserPreferences.load()
            prefs.guideGroupIds = guideGroupIds
            prefs.save()
            if !guideGroupIds.isEmpty, appState.guideGroupFilter == group.id, !guideGroupIds.contains(group.id) {
                appState.guideGroupFilter = nil
                appState.guideChannelFilter = ""
            }
            NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
        } label: {
            TVGuideToggleRowContent(title: group.name, isSelected: isSelected)
        }
        .buttonStyle(TVSettingsRowButtonStyle())
    }

    private func tvOSGuideProfileToggleRow(profile: ChannelProfile) -> some View {
        let isSelected = guideProfileIds.contains(profile.id)

        return Button {
            if isSelected {
                guideProfileIds.removeAll { $0 == profile.id }
            } else {
                guideProfileIds.append(profile.id)
            }

            var prefs = UserPreferences.load()
            prefs.guideProfileIds = guideProfileIds
            prefs.save()
            if !guideProfileIds.isEmpty, appState.guideProfileFilter == profile.id, !guideProfileIds.contains(profile.id) {
                appState.guideProfileFilter = nil
                appState.guideChannelFilter = ""
            }
            NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
        } label: {
            TVGuideToggleRowContent(title: profile.name, isSelected: isSelected)
        }
        .buttonStyle(TVSettingsRowButtonStyle())
    }
    #endif

    private var serverSummaryValue: String {
        let host = client.config.displayAddress.isEmpty ? "Not configured" : client.config.displayAddress
        let status = client.isAuthenticated ? "Connected" : "Not Connected"
        return "\(host) \(status)"
    }

    /// Sub-line under the tvOS Server row. Only Dispatcharr exposes the
    /// environment endpoint that backs it (#112) — the NextPVR variant has
    /// nothing to show there, and `environmentSubtitle` doesn't exist in
    /// that build at all, so the branch has to happen here rather than at
    /// the call site.
    private var serverRowDetail: String? {
        #if DISPATCHERPVR
        return environmentSubtitle
        #else
        return nil
        #endif
    }

    #if DISPATCHERPVR
    /// One-line summary of the server's public IP and geo location
    /// (#112), shared by the tvOS Server row's detail line and the
    /// iOS / macOS Public IP row inside the Server section.
    ///
    /// Returns `nil` when the data isn't ready yet, so the tvOS row can
    /// hide the sub-line until something meaningful exists while iOS /
    /// macOS substitute an explicit fallback via `environmentServerValue`.
    private var environmentSubtitle: String? {
        guard appState.environmentAvailable,
              let env = appState.environmentSettings else {
            return nil
        }
        if !env.ipLookupEnabled { return "IP lookup disabled on server" }
        if env.ipLookupPending { return "Looking up…" }
        if env.publicIP == nil && (env.countryName ?? env.countryCode) == nil {
            return "No IP info reported by server"
        }
        let publicIP = env.publicIP ?? "—"
        guard let location = environmentLocationString(for: env) else {
            return publicIP
        }
        return "\(publicIP) (\(location))"
    }

    /// iOS / macOS variant of `environmentSubtitle`. Substitutes a
    /// non-empty fallback so the row always reads something rather than
    /// appearing blank while the first poll is still in flight.
    private var environmentServerValue: String {
        if let subtitle = environmentSubtitle { return subtitle }
        if appState.environmentSettings == nil {
            return "Loading…"
        }
        return "Not available on this server version"
    }

    private func environmentLocationString(for env: EnvironmentSettings) -> String? {
        let country = env.countryName ?? env.countryCode
        let city = env.city
        switch (country, city) {
        case let (.some(country), .some(city)) where country.contains(city):
            return country
        case let (.some(country), .some(city)):
            return "\(city), \(country)"
        case let (.some(country), .none):
            return country
        case let (.none, .some(city)):
            return city
        case (.none, .none):
            return nil
        }
    }
    #endif

    private func rendererName(for api: GPUAPI) -> String {
        switch api {
        case .metal:
            return "Metal"
        case .pixelbuffer:
            return "PixelBuffer (Recommended)"
        case .opengl:
            return "OpenGL"
        }
    }

    #if os(tvOS)
    @ViewBuilder
    private func tvSettingsPopup(for popup: TVSettingsPopup) -> some View {
        let options = popupOptions(for: popup)
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture {
                    activeTVPopup = nil
                }

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                Text(popupTitle(for: popup))
                    .font(.tvScaled(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                VStack(spacing: Theme.spacingSM) {
                    ForEach(options, id: \.id) { option in
                        Button(option.title) {
                            option.action()
                            activeTVPopup = nil
                        }
                        .buttonStyle(TVSettingsPopupButtonStyle(variant: option.isDestructive ? .destructive : .regular))
                        .focused($popupFocusedItemID, equals: option.id)
                    }

                    Button("Cancel") {
                        activeTVPopup = nil
                    }
                    .buttonStyle(TVSettingsPopupButtonStyle(variant: .cancel))
                    .focused($popupFocusedItemID, equals: "settings-popup-cancel")
                }
            }
            .padding(Theme.spacingLG)
            .frame(maxWidth: 920)
            .background(Theme.surface.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLG))
            .onAppear {
                let currentOptionID = options.first(where: { $0.isCurrent })?.id ?? "settings-popup-cancel"
                DispatchQueue.main.async {
                    popupFocusedItemID = currentOptionID
                }
            }
            .onExitCommand {
                activeTVPopup = nil
            }
        }
    }

    private func popupTitle(for popup: TVSettingsPopup) -> String {
        switch popup {
        case .server:
            return "Server"
        case .seekBackward:
            return "Seek Backward"
        case .seekForward:
            return "Seek Forward"
        case .audioOutput:
            return "Audio Output"
        case .deinterlace:
            return "Deinterlacing"
        #if !DISPATCHERPVR
        case .streamQuality:
            return "Live TV Quality"
        #endif
        case .subtitleMode:
            return "Subtitles"
        case .subtitleSize:
            return "Subtitle Size"
        case .subtitleBackground:
            return "Subtitle Background"
        case .renderer:
            return "Renderer"
        case .landingTab:
            return "Landing Page"
        case .hideRecordings:
            return "Hide Recording Features"
        case .theme:
            return "Theme"
        case .uiFontSize:
            return "Text Size"
        }
    }

    private struct TVPopupOption {
        let id: String
        let title: String
        let isCurrent: Bool
        let isDestructive: Bool
        let action: () -> Void
    }

    private func popupOptions(for popup: TVSettingsPopup) -> [TVPopupOption] {
        switch popup {
        case .server:
            return [
                TVPopupOption(id: "settings-popup-server-unlink", title: "Unlink Server", isCurrent: true, isDestructive: true) {
                    unlinkServer()
                }
            ]
        case .seekBackward:
            return [5, 10, 15, 30].map { seconds in
                TVPopupOption(
                    id: "settings-popup-seek-backward-\(seconds)",
                    title: "\(seconds)s",
                    isCurrent: seekBackwardSeconds == seconds,
                    isDestructive: false
                ) {
                    seekBackwardSeconds = seconds
                    var prefs = UserPreferences.load()
                    prefs.seekBackwardSeconds = seconds
                    prefs.save()
                }
            }
        case .seekForward:
            return [15, 30, 45, 60].map { seconds in
                TVPopupOption(
                    id: "settings-popup-seek-forward-\(seconds)",
                    title: "\(seconds)s",
                    isCurrent: seekForwardSeconds == seconds,
                    isDestructive: false
                ) {
                    seekForwardSeconds = seconds
                    var prefs = UserPreferences.load()
                    prefs.seekForwardSeconds = seconds
                    prefs.save()
                }
            }
        case .audioOutput:
            return [
                TVPopupOption(id: "settings-popup-audio-auto", title: "Auto", isCurrent: audioChannels == "auto", isDestructive: false) {
                    audioChannels = "auto"
                    var prefs = UserPreferences.load()
                    prefs.audioChannels = "auto"
                    prefs.save()
                },
                TVPopupOption(id: "settings-popup-audio-stereo", title: "Stereo", isCurrent: audioChannels == "stereo", isDestructive: false) {
                    audioChannels = "stereo"
                    var prefs = UserPreferences.load()
                    prefs.audioChannels = "stereo"
                    prefs.save()
                }
            ]
        case .deinterlace:
            return DeinterlaceMode.allCases.map { mode in
                TVPopupOption(
                    id: "settings-popup-deinterlace-\(mode.rawValue)",
                    title: mode.label,
                    isCurrent: deinterlaceMode == mode,
                    isDestructive: false
                ) {
                    deinterlaceMode = mode
                    var prefs = UserPreferences.load()
                    prefs.deinterlaceMode = mode
                    prefs.save()
                }
            }
        #if !DISPATCHERPVR
        case .streamQuality:
            return StreamQuality.allCases.map { quality in
                TVPopupOption(
                    id: "settings-popup-stream-quality-\(quality.rawValue)",
                    title: quality.label,
                    isCurrent: streamQuality == quality,
                    isDestructive: false
                ) {
                    streamQuality = quality
                    var prefs = UserPreferences.load()
                    prefs.streamQuality = quality
                    prefs.save()
                }
            }
        #endif
        case .subtitleMode:
            return [
                TVPopupOption(id: "settings-popup-subtitle-manual", title: "Manual", isCurrent: subtitleMode == .manual, isDestructive: false) {
                    subtitleMode = .manual
                    var prefs = UserPreferences.load()
                    prefs.subtitleMode = .manual
                    prefs.save()
                },
                TVPopupOption(id: "settings-popup-subtitle-auto", title: "Auto", isCurrent: subtitleMode == .auto, isDestructive: false) {
                    subtitleMode = .auto
                    var prefs = UserPreferences.load()
                    prefs.subtitleMode = .auto
                    prefs.save()
                }
            ]
        case .subtitleSize:
            return SubtitleSize.allCases.map { size in
                TVPopupOption(
                    id: "settings-popup-subtitle-size-\(size.rawValue)",
                    title: size.displayName,
                    isCurrent: subtitleSize == size,
                    isDestructive: false
                ) {
                    subtitleSize = size
                    var prefs = UserPreferences.load()
                    prefs.subtitleSize = size
                    prefs.save()
                }
            }
        case .uiFontSize:
            // Applies live: `appState.uiFontSize` writes the global the
            // scaled fonts read and invalidates every view that holds
            // appState, so the popup itself redraws at the new size while
            // the user is still choosing. (#107)
            return UIFontSize.allCases.map { size in
                TVPopupOption(
                    id: "settings-popup-ui-font-size-\(size.rawValue)",
                    title: size.displayName,
                    isCurrent: uiFontSize == size,
                    isDestructive: false
                ) {
                    uiFontSize = size
                    appState.uiFontSize = size
                    var prefs = UserPreferences.load()
                    prefs.uiFontSize = size
                    prefs.save()
                }
            }
        case .subtitleBackground:
            return [
                TVPopupOption(id: "settings-popup-subtitle-bg-on", title: "On", isCurrent: subtitleBackground, isDestructive: false) {
                    subtitleBackground = true
                    var prefs = UserPreferences.load()
                    prefs.subtitleBackground = true
                    prefs.save()
                },
                TVPopupOption(id: "settings-popup-subtitle-bg-off", title: "Off", isCurrent: !subtitleBackground, isDestructive: false) {
                    subtitleBackground = false
                    var prefs = UserPreferences.load()
                    prefs.subtitleBackground = false
                    prefs.save()
                }
            ]
        case .renderer:
            return GPUAPI.allCases.map { api in
                TVPopupOption(
                    id: "settings-popup-renderer-\(rendererName(for: api))",
                    title: rendererName(for: api),
                    isCurrent: tvosGPUAPI == api,
                    isDestructive: false
                ) {
                    tvosGPUAPI = api
                    var prefs = UserPreferences.load()
                    prefs.tvosGPUAPI = api
                    prefs.save()
                }
            }
        case .landingTab:
            return availableLandingOptions
                .map { option in
                    TVPopupOption(
                        id: "settings-popup-landing-\(option.rawValue)",
                        title: option.label,
                        isCurrent: displayedLandingTab == option,
                        isDestructive: false
                    ) {
                        saveLandingTab(option)
                    }
                }
        case .hideRecordings:
            return [
                TVPopupOption(id: "settings-popup-hide-recordings-on", title: "On", isCurrent: hideRecordings, isDestructive: false) {
                    saveHideRecordings(true)
                },
                TVPopupOption(id: "settings-popup-hide-recordings-off", title: "Off", isCurrent: !hideRecordings, isDestructive: false) {
                    saveHideRecordings(false)
                }
            ]
        case .theme:
            return AppTheme.allCases.map { option in
                TVPopupOption(
                    id: "settings-popup-theme-\(option.rawValue)",
                    title: option.label,
                    isCurrent: theme == option,
                    isDestructive: false
                ) {
                    saveTheme(option)
                }
            }
        }
    }
    #endif

    private var generalSection: some View {
        Section {
            // Filter the picker to only show landing options the current
            // user can actually open. Hiding unavailable options keeps the
            // UI honest and avoids surprising the user with a redirected
            // landing on next launch.
            Picker("Landing Page", selection: landingTabSelection) {
                ForEach(availableLandingOptions) { option in
                    Text(option.label).tag(option)
                }
            }
            .accessibilityIdentifier("settings-landing-page-picker")

            Picker("Theme", selection: themeSelection) {
                ForEach(AppTheme.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .accessibilityIdentifier("settings-theme-picker")

            Toggle("Hide Recording Features", isOn: hideRecordingsSelection)
                .accessibilityIdentifier("settings-hide-recordings-toggle")
        } header: {
            Text("General")
        } footer: {
            Text("Choose which page opens when the app launches. Theme overrides the device appearance — System follows your device setting. Hiding recording features removes all recording menus and buttons from the app.")
        }
    }

    private var landingTabSelection: Binding<LandingTabOption> {
        Binding(
            get: { displayedLandingTab },
            set: { newValue in saveLandingTab(newValue) }
        )
    }

    private var themeSelection: Binding<AppTheme> {
        Binding(
            get: { theme },
            set: { newValue in saveTheme(newValue) }
        )
    }

    private var hideRecordingsSelection: Binding<Bool> {
        Binding(
            get: { hideRecordings },
            set: { newValue in saveHideRecordings(newValue) }
        )
    }

    private var availableLandingOptions: [LandingTabOption] {
        LandingTabOption.allCases.filter { option in
            AppState.isLandingOptionAvailable(option, forUserLevel: appState.userLevel, hideRecordings: hideRecordings)
        }
    }

    private var displayedLandingTab: LandingTabOption {
        availableLandingOptions.contains(landingTab) ? landingTab : .guide
    }

    private func saveLandingTab(_ option: LandingTabOption) {
        landingTab = option
        var prefs = UserPreferences.load()
        prefs.landingTab = option
        prefs.save()
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
    }

    private func saveTheme(_ option: AppTheme) {
        theme = option
        var prefs = UserPreferences.load()
        prefs.theme = option
        prefs.save()
        // Apply immediately so the appearance changes without a relaunch.
        appState.theme = option
    }

    private func saveHideRecordings(_ hidden: Bool) {
        hideRecordings = hidden
        var prefs = UserPreferences.load()
        prefs.hideRecordings = hidden
        prefs.save()
        // Apply immediately so tabs, menus and buttons update without relaunch.
        appState.hideRecordings = hidden
    }

    private var serverSection: some View {
        Section {
            HStack {
                Text("Host")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(verbatim: client.config.displayAddress)
                    .foregroundStyle(Theme.textPrimary)
            }

            #if DISPATCHERPVR
            environmentServerRow
            #endif

            HStack {
                Text("Status")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if client.isAuthenticated {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                        Text("Connected")
                            .foregroundStyle(Theme.success)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.warning)
                        Text("Not Connected")
                            .foregroundStyle(Theme.warning)
                    }
                }
            }

            Button(role: .destructive) {
                showingUnlinkConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Label("Unlink Server", systemImage: "server.rack")
                    Spacer()
                }
            }
            .accessibilityIdentifier("unlink-server-button")
            .confirmationDialog("Unlink Server", isPresented: $showingUnlinkConfirm, titleVisibility: .visible) {
                Button("Unlink", role: .destructive) {
                    unlinkServer()
                }
                .accessibilityIdentifier("confirm-unlink-button")
            } message: {
                Text("This will disconnect and forget the server. You'll need to set it up again.")
            }
        } header: {
            Text("\(Brand.serverName) Server")
        }
    }

    private func unlinkServer() {
        client.disconnect()
        ServerConfig.clear()
        client.updateConfig(.default)
        #if DISPATCHERPVR
        client.useOutputEndpoints = false
        #endif
        appState.guideChannelFilter = ""
        appState.guideGroupFilter = nil
        appState.guideProfileFilter = nil
        appState.searchQuery = ""
        #if DISPATCHERPVR
        appState.userLevel = 10
        #endif
    }

    private var playbackSection: some View {
        Section {
            Picker("Seek Backward", selection: $seekBackwardSeconds) {
                Text("5 seconds").tag(5)
                Text("10 seconds").tag(10)
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
            }

            Picker("Seek Forward", selection: $seekForwardSeconds) {
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("45 seconds").tag(45)
                Text("60 seconds").tag(60)
            }

            Picker("Audio Output", selection: $audioChannels) {
                Text("Auto").tag("auto")
                Text("Stereo").tag("stereo")
            }

            #if !DISPATCHERPVR
            Picker("Live TV Quality", selection: $streamQuality) {
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }
            Text(streamQualityDescription)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            #endif

            Picker("Deinterlacing", selection: $deinterlaceMode) {
                ForEach(DeinterlaceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(deinterlaceDescription)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            Picker("Subtitles", selection: $subtitleMode) {
                Text("Manual").tag(SubtitleMode.manual)
                Text("Auto").tag(SubtitleMode.auto)
            }
            Text(subtitleModeDescription)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            Picker("Subtitle Size", selection: $subtitleSize) {
                ForEach(SubtitleSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }

            Toggle("Subtitle Background", isOn: $subtitleBackground)

            #if os(iOS)
            Picker("Renderer", selection: $iosGPUAPI) {
                Text("OpenGL").tag(GPUAPI.opengl)
                Text("Metal").tag(GPUAPI.metal)
                Text("PixelBuffer (Recommended)").tag(GPUAPI.pixelbuffer)
            }
            Text(rendererDescription(for: iosGPUAPI))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            #elseif os(macOS)
            Picker("Renderer", selection: $macosGPUAPI) {
                Text("OpenGL").tag(GPUAPI.opengl)
                Text("Metal").tag(GPUAPI.metal)
                Text("PixelBuffer (Recommended)").tag(GPUAPI.pixelbuffer)
            }
            Text(rendererDescription(for: macosGPUAPI))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            #endif
        } header: {
            Text("Playback")
        }
        .onChange(of: seekBackwardSeconds) { _ in
            var prefs = UserPreferences.load()
            prefs.seekBackwardSeconds = seekBackwardSeconds
            prefs.save()
        }
        .onChange(of: seekForwardSeconds) { _ in
            var prefs = UserPreferences.load()
            prefs.seekForwardSeconds = seekForwardSeconds
            prefs.save()
        }
        .onChange(of: audioChannels) { _ in
            var prefs = UserPreferences.load()
            prefs.audioChannels = audioChannels
            prefs.save()
        }
        .onChange(of: deinterlaceMode) { _ in
            var prefs = UserPreferences.load()
            prefs.deinterlaceMode = deinterlaceMode
            prefs.save()
        }
        #if !DISPATCHERPVR
        .onChange(of: streamQuality) { _ in
            var prefs = UserPreferences.load()
            prefs.streamQuality = streamQuality
            prefs.save()
        }
        #endif
        .onChange(of: subtitleMode) { _ in
            var prefs = UserPreferences.load()
            prefs.subtitleMode = subtitleMode
            prefs.save()
        }
        .onChange(of: subtitleSize) { _ in
            var prefs = UserPreferences.load()
            prefs.subtitleSize = subtitleSize
            prefs.save()
        }
        .onChange(of: subtitleBackground) { _ in
            var prefs = UserPreferences.load()
            prefs.subtitleBackground = subtitleBackground
            prefs.save()
        }
        #if os(iOS)
        .onChange(of: iosGPUAPI) { _ in
            var prefs = UserPreferences.load()
            prefs.iosGPUAPI = iosGPUAPI
            prefs.save()
        }
        #elseif os(macOS)
        .onChange(of: macosGPUAPI) { _ in
            var prefs = UserPreferences.load()
            prefs.macosGPUAPI = macosGPUAPI
            prefs.save()
        }
        #endif
    }

    private var subtitleModeDescription: String {
        switch subtitleMode {
        case .manual:
            return "Select subtitles manually each time from the player settings panel."
        case .auto:
            return "Automatically select the last used subtitle language when available."
        }
    }

    #if !DISPATCHERPVR
    /// Explains the selected live TV quality. Like the other player settings
    /// this takes effect on the next stream, since the profile is chosen when
    /// the stream is opened.
    private var streamQualityDescription: String {
        streamQuality.summary + " Applies to the next channel you play."
    }
    #endif

    /// Explains the selected deinterlacing mode (#142). Changing the mode
    /// takes effect the next time playback starts, since mpv is configured
    /// when the player is created.
    private var deinterlaceDescription: String {
        deinterlaceMode.summary + " Applies to the next stream you play."
    }

    private func rendererDescription(for api: GPUAPI) -> String {
        switch api {
        case .pixelbuffer:
            return "Renders directly to a Metal surface + Supports native Picture-in-Picture"
        case .metal:
            return "Renders directly to a Metal surface. May offer lower latency but lacks Picture-in-Picture support."
        case .opengl:
            return "Legacy OpenGL-based rendering. Broad compatibility but no Picture-in-Picture support."
        }
    }

    #if DISPATCHERPVR
    private var guideSection: some View {
        Section {
            Toggle("Show Groups in Sidebar", isOn: $guideShowGroupsInSidebar)
                .onChange(of: guideShowGroupsInSidebar) { newValue in
                    var prefs = UserPreferences.load()
                    prefs.guideShowGroupsInSidebar = newValue
                    prefs.save()
                    if !newValue {
                        appState.guideGroupFilter = nil
                        appState.guideChannelFilter = ""
                    }
                    NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
                }
            if guideShowGroupsInSidebar {
                if epgCache.channelGroups.isEmpty {
                    Text("No channel groups available")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    let populatedGroups = epgCache.channelGroups.filter { group in
                        epgCache.guideSidebarChannels.contains { $0.groupId == group.id }
                    }
                    if populatedGroups.isEmpty {
                        Text("No channels in any group")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(populatedGroups) { group in
                            let isSelected = guideGroupIds.contains(group.id)
                            Button {
                                if isSelected {
                                    guideGroupIds.removeAll { $0 == group.id }
                                } else {
                                    guideGroupIds.append(group.id)
                                }
                                var prefs = UserPreferences.load()
                                prefs.guideGroupIds = guideGroupIds
                                prefs.save()
                                if !guideGroupIds.isEmpty, appState.guideGroupFilter == group.id, !guideGroupIds.contains(group.id) {
                                    appState.guideGroupFilter = nil
                                    appState.guideChannelFilter = ""
                                }
                                NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                                    Text(group.name)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Toggle("Show Profiles in Sidebar", isOn: $guideShowProfilesInSidebar)
                .onChange(of: guideShowProfilesInSidebar) { newValue in
                    var prefs = UserPreferences.load()
                    prefs.guideShowProfilesInSidebar = newValue
                    prefs.save()
                    if !newValue {
                        appState.guideProfileFilter = nil
                        appState.guideChannelFilter = ""
                    }
                    NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
                }
            if guideShowProfilesInSidebar {
                if epgCache.channelProfiles.isEmpty {
                    Text("No channel profiles available")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    let populatedProfiles = epgCache.channelProfiles.filter { profile in
                        epgCache.guideSidebarChannels.contains { profile.channels.contains($0.id) }
                    }
                    if populatedProfiles.isEmpty {
                        Text("No channels in any profile")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(populatedProfiles) { profile in
                            let isSelected = guideProfileIds.contains(profile.id)
                            Button {
                                if isSelected {
                                    guideProfileIds.removeAll { $0 == profile.id }
                                } else {
                                    guideProfileIds.append(profile.id)
                                }
                                var prefs = UserPreferences.load()
                                prefs.guideProfileIds = guideProfileIds
                                prefs.save()
                                if !guideProfileIds.isEmpty, appState.guideProfileFilter == profile.id, !guideProfileIds.contains(profile.id) {
                                    appState.guideProfileFilter = nil
                                    appState.guideChannelFilter = ""
                                }
                                NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                                    Text(profile.name)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("Guide")
        }
    }
    #endif

    #if DISPATCHERPVR
    /// iOS / macOS row showing the server's public IP and geo location
    /// (#112). Lives inside the Server section beneath the Host row so the
    /// identity of the server (host + public IP + location) stays grouped
    /// together instead of being split into a separate Network section.
    private var environmentServerRow: some View {
        HStack {
            Text("Server Public IP")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(verbatim: environmentServerValue)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("env-public-ip-and-location")
        }
    }
    #endif

    #if DEBUG
    private var debugStreamSection: some View {
        Section {
            Toggle("Test Stream Override", isOn: $debugStreamEnabled)
                .onChange(of: debugStreamEnabled) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "debugStreamEnabled")
                }

            if debugStreamEnabled {
                TextField("Stream URL", text: $debugStreamURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: debugStreamURL) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "debugStreamURL")
                    }

                Toggle("Play as Recording", isOn: $debugStreamAsRecording)
                    .onChange(of: debugStreamAsRecording) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "debugStreamAsRecording")
                    }

                Button(debugStreamAsRecording ? "Play Test Recording" : "Play Test Stream") {
                    if let url = URL(string: debugStreamURL) {
                        appState.playStream(
                            url: url,
                            title: debugStreamAsRecording ? "Test Recording" : "Test Stream",
                            recordingId: debugStreamAsRecording ? -1 : nil
                        )
                    }
                }
            }
        } header: {
            Text("Debug")
        }
    }
    #endif

    private var eventLogLinkSection: some View {
        Section {
            NavigationLink(destination: EventLogView()) {
                HStack {
                    Label("Event Log", systemImage: "list.bullet.rectangle")
                    Spacer()
                    if !eventLog.events.isEmpty {
                        Text("\(eventLog.events.count)")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }


}

#if os(tvOS)
#if DISPATCHERPVR
private struct TVGuideSidebarToggleForegroundStyle: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isFocused ? Color(white: 0.06) : Theme.textPrimary)
    }
}

private struct TVGuideToggleRowContent: View {
    let title: String
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: Theme.spacingMD) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.tvScaled(size: 24, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)

            Text(title)
                .font(.tvScaled(size: 24, weight: .semibold))
                .foregroundStyle(isFocused ? Color.white : Theme.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingMD)
        .background(Theme.guideNowPlaying.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
    }
}
#endif

private struct TVSettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                    .stroke(isFocused ? Theme.accent : Color.clear, lineWidth: isFocused ? 3 : 0)
            }
            .shadow(color: isFocused ? Theme.accent.opacity(0.24) : .clear, radius: 12)
            .scaleEffect(configuration.isPressed ? 0.985 : isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
    }
}

private struct TVSettingsPopupButtonStyle: ButtonStyle {
    enum Variant {
        case regular
        case destructive
        case cancel
    }

    let variant: Variant
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tvScaled(size: 24, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.vertical, Theme.spacingMD)
            .frame(maxWidth: .infinity)
            .background(backgroundColor(configuration: configuration))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMD)
                    .stroke(isFocused ? Theme.accent : Color.clear, lineWidth: isFocused ? 3 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
    }

    private var foregroundColor: Color {
        switch variant {
        case .destructive:
            return .white
        case .regular, .cancel:
            return Theme.textPrimary
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        let base: Color
        switch variant {
        case .regular:
            base = Theme.guideNowPlaying.opacity(0.9)
        case .cancel:
            base = Theme.surfaceElevated.opacity(0.9)
        case .destructive:
            base = Theme.error.opacity(0.9)
        }
        return configuration.isPressed ? base.opacity(0.72) : base
    }
}
#endif

#Preview {
    SettingsView()
        .environmentObject(PVRClient())
        .preferredColorScheme(.dark)
}
