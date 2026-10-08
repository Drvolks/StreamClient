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
    #if !os(tvOS)
    @State private var cellularStreamQuality: StreamQuality? = UserPreferences.load().cellularStreamQuality
    #endif
    #endif
    @State private var landingTab: LandingTabOption = UserPreferences.load().landingTab
    @State private var hideRecordings: Bool = UserPreferences.load().hideRecordings
    @State private var theme: AppTheme = UserPreferences.load().theme
    #if os(tvOS)
    @State private var uiFontSize: UIFontSize = UserPreferences.load().uiFontSize
    #endif
    @State private var guideShowGroupsInSidebar: Bool = UserPreferences.load().guideShowGroupsInSidebar
    @State private var guideGroupIds: [Int] = UserPreferences.load().guideGroupIds
    #if DISPATCHERPVR
    @State private var guideShowProfilesInSidebar: Bool = UserPreferences.load().guideShowProfilesInSidebar
    @State private var guideProfileIds: [Int] = UserPreferences.load().guideProfileIds
    /// Selected Dispatcharr Output Profile id (#161); nil is Original.
    @State private var outputProfileId: Int? = UserPreferences.load().outputProfileId
    #endif
    @ObservedObject private var eventLog: NetworkEventLog

    init(eventLog: NetworkEventLog = Dependencies.networkEventLog) {
        self._eventLog = ObservedObject(wrappedValue: eventLog)
    }
    #if os(macOS)
    @SceneStorage("settings.category") private var macCategory: SettingsCategory = .server
    @State private var showingMacEventLog = false
    #endif
    #if os(macOS) || os(tvOS)
    /// The topics being edited (Settings > Topics).
    @State private var topicList: [String] = UserPreferences.load().keywords
    @State private var newTopic = ""
    #endif
    #if os(tvOS)
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeTVPopup: TVSettingsPopup?
    @FocusState private var popupFocusedItemID: String?
    @State private var showingTVEventLog = false
    @FocusState private var isAddTopicFieldFocused: Bool
    @State private var requestTopicKeyboard = false
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
        case deinterlace
        #if !DISPATCHERPVR
        case streamQuality
        #else
        case outputProfile
        #endif
        case renderer
        case landingTab
        case theme
        case uiFontSize
        /// Move or remove one topic (Settings > Topics).
        case topic(String)
    }
    #endif

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            tvOSContent
            #elseif os(macOS)
            macOSContent
            #else
            List {
                serverSection
                generalSection
                playbackSection
                guideSection
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
            .listStyle(.insetGrouped)
            .sidebarMenuToolbar()
            #endif
        }
        .accessibilityIdentifier("settings-view")
        #if DISPATCHERPVR
        .task {
            await client.ensureOutputProfilesLoaded()
        }
        #endif
        #if os(tvOS)
        .background(MidnightGradients.ground(colorScheme))
        #else
        .background(Theme.background)
        #endif
    }

    #if os(tvOS)
    private var tvOSContent: some View {
        ZStack {
            VStack(spacing: 0) {
                TVPageHeader(kicker: nil, title: "Settings", readout: tvOSVersionText)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacingXL) {
                        tvSection(.server) {
                            Button {
                                activeTVPopup = .server
                            } label: {
                                TVSettingsRowLabel(
                                    title: client.config.displayAddress.isEmpty ? "Not configured" : client.config.displayAddress,
                                    subtitle: serverRowDetail
                                ) {
                                    if client.isAuthenticated {
                                        MidnightFieldChip(text: "Connected", size: Theme.scaledFont(14))
                                    } else {
                                        Text("Not connected")
                                            .midnightBadge(Theme.scaledFont(14))
                                            .foregroundStyle(MidnightPalette.danger)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .overlay { Rectangle().strokeBorder(MidnightPalette.danger, lineWidth: 1) }
                                    }
                                }
                            }
                            .buttonStyle(TVMidnightButtonStyle())
                            .accessibilityIdentifier("settings-server-row")
                        }

                        tvSection(.general) {
                            tvRow("Landing Page", value: displayedLandingTab.label) { activeTVPopup = .landingTab }
                            tvRow("Theme", value: theme.label) { activeTVPopup = .theme }
                            tvRow("Text Size", value: uiFontSize.displayName, subtitle: "Scales text and rows across the app") {
                                activeTVPopup = .uiFontSize
                            }
                        }

                        tvSection(.playback, hint: tvOSPlaybackHint) {
                            #if !DISPATCHERPVR
                            tvRow("Live TV Quality", value: streamQuality.label) { activeTVPopup = .streamQuality }
                            #else
                            tvRow("Live TV Output Profile", value: outputProfileLabel) { activeTVPopup = .outputProfile }
                            #endif
                            tvRow("Seek Backward", value: "\(seekBackwardSeconds)s") { activeTVPopup = .seekBackward }
                            tvRow("Seek Forward", value: "\(seekForwardSeconds)s") { activeTVPopup = .seekForward }
                            tvRow("Audio Output", value: audioChannels == "stereo" ? "Stereo" : "Auto") { activeTVPopup = .audioOutput }
                        }

                        tvSection(.subtitles) {
                            tvRow("Subtitles", value: subtitleMode == .auto ? "Auto" : "Manual") { activeTVPopup = .subtitleMode }
                            tvRow("Subtitle Size", value: subtitleSize.displayName) { activeTVPopup = .subtitleSize }
                            tvSwitchRow("Subtitle Background", isOn: subtitleBackground) {
                                subtitleBackground.toggle()
                                var prefs = UserPreferences.load()
                                prefs.subtitleBackground = subtitleBackground
                                prefs.save()
                            }
                        }

                        tvSection(.guide) {
                            tvOSGuideRows
                        }

                        tvSection(.topics) {
                            tvOSTopicsRows
                        }

                        tvSection(.recordings) {
                            tvSwitchRow("Hide Recording Features", isOn: hideRecordings) {
                                saveHideRecordings(!hideRecordings)
                            }
                        }

                        tvSection(.advanced) {
                            tvRow("Renderer", value: rendererName(for: tvosGPUAPI)) { activeTVPopup = .renderer }
                            tvRow("Deinterlacing", value: deinterlaceMode.label) { activeTVPopup = .deinterlace }
                            tvRow("Event Log", value: "\(eventLog.events.count)") { showingTVEventLog = true }
                        }

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
                    }
                    .padding(.vertical, Theme.spacingLG)
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
            .background {
                NavigationLink(isActive: $showingTVEventLog) {
                    EventLogView()
                } label: {
                    EmptyView()
                }
                .hidden()
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
        .onAppear {
            topicList = UserPreferences.load().keywords
            applyRequestedTVCategory()
        }
        .onChange(of: appState.requestedSettingsCategory) { _ in applyRequestedTVCategory() }
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

    /// A Settings category: its header, its rows, then its one hint.
    private func tvSection<Content: View>(
        _ category: SettingsCategory,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MidnightSectionHeader(title: category.title, meta: "")
                .padding(.bottom, 6)
            content()
            Text(hint ?? category.hint)
                .font(.archivo(Theme.scaledFont(16)))
                .foregroundStyle(MidnightPalette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 4)
        }
        .focusSection()
    }

    /// A row showing its current value; selecting it opens the chooser.
    private func tvRow(
        _ title: String,
        value: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TVSettingsRowLabel(title: title, subtitle: subtitle, value: value)
        }
        .buttonStyle(TVMidnightButtonStyle())
    }

    /// An on / off row; selecting it flips the setting.
    private func tvSwitchRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TVSettingsRowLabel(title: title) { TVSettingsSwitch(isOn: isOn) }
        }
        .buttonStyle(TVMidnightButtonStyle())
    }

    /// Add a topic, then each topic in order; selecting one offers to move
    /// or remove it. (Topics used to be managed from the sidebar.)
    @ViewBuilder
    private var tvOSTopicsRows: some View {
        Button {
            requestTopicKeyboard = true
        } label: {
            TVSettingsRowLabel(
                title: "Add a topic",
                subtitle: "Matched against program titles, subtitles and descriptions."
            ) {
                Image(systemName: "plus")
                    .font(.system(size: Theme.scaledFont(22), weight: .heavy))
                    .foregroundStyle(MidnightPalette.accent)
            }
        }
        .buttonStyle(TVMidnightButtonStyle())
        .focused($isAddTopicFieldFocused)
        .accessibilityIdentifier("keyword-text-field")
        .background(
            TVKeyboardField(
                text: $newTopic,
                placeholder: "e.g. Cycling",
                requestFocus: $requestTopicKeyboard,
                returnKeyType: .done,
                onFocusChange: { editing in
                    // Done (or leaving the keyboard) adds what was typed.
                    guard !editing else { return }
                    requestTopicKeyboard = false
                    addTopic()
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
        )

        if topicList.isEmpty {
            tvOSGuideStatusRow("No topics yet.")
        } else {
            ForEach(Array(topicList.enumerated()), id: \.element) { index, keyword in
                Button {
                    activeTVPopup = .topic(keyword)
                } label: {
                    TVSettingsRowLabel(
                        title: keyword,
                        subtitle: index == 0 ? "Opens by default" : nil,
                        value: appState.topicKeywordMatchCounts[keyword].map { "\($0) program\($0 == 1 ? "" : "s")" } ?? ""
                    )
                }
                .buttonStyle(TVMidnightButtonStyle())
                .accessibilityIdentifier("settings-topic-\(keyword)")
            }
        }
    }

    private var tvOSPlaybackHint: String {
        #if DISPATCHERPVR
        outputProfileDescription
        #else
        streamQualityDescription
        #endif
    }

    private var tvOSVersionText: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// Settings > Topics was requested (the sidebar's Topics with no topics
    /// yet): put focus on the add field.
    private func applyRequestedTVCategory() {
        guard let requested = appState.requestedSettingsCategory else { return }
        appState.requestedSettingsCategory = nil
        if requested == .topics {
            DispatchQueue.main.async { isAddTopicFieldFocused = true }
        }
    }

    /// tvOS sub-line under the Server row showing the server's public IP
    /// and geo location (#112). The full address line already shows the
    /// host + status; the detail line below it carries the environment
    /// info so the Network panel is no longer needed.
    #endif

    #if os(tvOS)
    private var tvOSGuideRows: some View {
        Group {
            tvSwitchRow("Show groups in sidebar", isOn: guideShowGroupsInSidebar) {
                setGuideShowGroupsInSidebar(!guideShowGroupsInSidebar)
            }
            if guideShowGroupsInSidebar {
                let populatedGroups = epgCache.populatedChannelGroups
                if epgCache.channelGroups.isEmpty {
                    tvOSGuideStatusRow("No channel groups available")
                } else if populatedGroups.isEmpty {
                    tvOSGuideStatusRow("No channels in any group")
                } else {
                    ForEach(populatedGroups) { group in
                        tvOSGuideGroupToggleRow(group: group)
                    }
                }
            }

            // Channel profiles are a Dispatcharr concept; NextPVR only has groups.
            #if DISPATCHERPVR
            tvSwitchRow("Show profiles in sidebar", isOn: guideShowProfilesInSidebar) {
                setGuideShowProfilesInSidebar(!guideShowProfilesInSidebar)
            }
            if guideShowProfilesInSidebar {
                let populatedProfiles = epgCache.channelProfiles.filter { profile in
                    epgCache.guideSidebarChannels.contains { profile.channels.contains($0.id) }
                }
                if epgCache.channelProfiles.isEmpty {
                    tvOSGuideStatusRow("No channel profiles available")
                } else if populatedProfiles.isEmpty {
                    tvOSGuideStatusRow("No channels in any profile")
                } else {
                    ForEach(populatedProfiles) { profile in
                        tvOSGuideProfileToggleRow(profile: profile)
                    }
                }
            }
            #endif
        }
    }

    private func setGuideShowGroupsInSidebar(_ newValue: Bool) {
        guideShowGroupsInSidebar = newValue
        var prefs = UserPreferences.load()
        prefs.guideShowGroupsInSidebar = newValue
        prefs.save()
        if !newValue {
            appState.guideGroupFilter = nil
            appState.guideChannelFilter = ""
        }
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
    }

    #if DISPATCHERPVR
    private func setGuideShowProfilesInSidebar(_ newValue: Bool) {
        guideShowProfilesInSidebar = newValue
        var prefs = UserPreferences.load()
        prefs.guideShowProfilesInSidebar = newValue
        prefs.save()
        if !newValue {
            appState.guideProfileFilter = nil
            appState.guideChannelFilter = ""
        }
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
    }
    #endif

    private func tvOSGuideStatusRow(_ text: String) -> some View {
        Text(text)
            .font(.archivo(Theme.scaledFont(18)))
            .foregroundStyle(MidnightPalette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(MidnightPalette.cellRest.opacity(0.6))
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
            TVSettingsRowLabel(title: group.name) { TVSettingsCheck(isOn: isSelected) }
        }
        .buttonStyle(TVMidnightButtonStyle())
    }

    #if DISPATCHERPVR
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
            TVSettingsRowLabel(title: profile.name) { TVSettingsCheck(isOn: isSelected) }
        }
        .buttonStyle(TVMidnightButtonStyle())
    }
    #endif
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
                    .midnightDisplay(Theme.scaledFont(28))
                    .foregroundStyle(MidnightPalette.ink)

                VStack(spacing: 6) {
                    ForEach(options, id: \.id) { option in
                        Button(option.title) {
                            option.action()
                            activeTVPopup = nil
                        }
                        .buttonStyle(TVSettingsPopupButtonStyle(
                            variant: option.isDestructive ? .destructive : .regular,
                            isCurrent: option.isCurrent && !option.isDestructive
                        ))
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
            .background(MidnightPalette.railHead)
            .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
            .overlay(alignment: .top) {
                Rectangle().fill(MidnightPalette.accent).frame(height: 4)
            }
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
        #else
        case .outputProfile:
            return "Live TV Output Profile"
        #endif
        case .subtitleMode:
            return "Subtitles"
        case .subtitleSize:
            return "Subtitle Size"
        case .renderer:
            return "Renderer"
        case .landingTab:
            return "Landing Page"
        case .theme:
            return "Theme"
        case .uiFontSize:
            return "Text Size"
        case .topic(let keyword):
            return keyword
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
        #else
        case .outputProfile:
            return outputProfileChoices.map { choice in
                TVPopupOption(
                    id: "settings-popup-output-profile-\(choice.id.map(String.init) ?? "original")",
                    title: choice.label,
                    isCurrent: outputProfileId == choice.id,
                    isDestructive: false
                ) {
                    saveOutputProfile(choice.id)
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
        case .topic(let keyword):
            guard let index = topicList.firstIndex(of: keyword) else { return [] }
            var options: [TVPopupOption] = []
            if index > 0 {
                options.append(TVPopupOption(id: "settings-popup-topic-up", title: "Move Up", isCurrent: false, isDestructive: false) {
                    moveTopic(at: index, by: -1)
                })
            }
            if index < topicList.count - 1 {
                options.append(TVPopupOption(id: "settings-popup-topic-down", title: "Move Down", isCurrent: false, isDestructive: false) {
                    moveTopic(at: index, by: 1)
                })
            }
            options.append(TVPopupOption(id: "settings-popup-topic-remove", title: "Remove Topic", isCurrent: true, isDestructive: true) {
                removeTopic(keyword)
            })
            return options
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

            #if !os(tvOS)
            CustomHostSettingsRows()
            #endif

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
        persistingPlaybackPreferences(Section {
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

            #if !os(tvOS)
            Picker("On Cellular", selection: $cellularStreamQuality) {
                Text("Same as usual").tag(StreamQuality?.none)
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.label).tag(StreamQuality?.some(quality))
                }
            }
            Text(cellularStreamQualityDescription)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            #endif
            #else
            Picker("Live TV Output Profile", selection: $outputProfileId) {
                ForEach(outputProfileChoices) { choice in
                    Text(choice.label).tag(choice.id)
                }
            }
            Text(outputProfileDescription)
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
        })
    }

    /// Saves each playback and subtitle setting when it changes. Shared by the
    /// iOS Playback section and the macOS Settings panes.
    private func persistingPlaybackPreferences<Content: View>(_ content: Content) -> some View {
        content
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
        #if !os(tvOS)
        .onChange(of: cellularStreamQuality) { _ in
            var prefs = UserPreferences.load()
            prefs.cellularStreamQuality = cellularStreamQuality
            prefs.save()
        }
        #endif
        #else
        .onChange(of: outputProfileId) { _ in
            saveOutputProfile(outputProfileId)
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
    #if !os(tvOS)
    /// Explains the metered-network override. "Metered" rather than "cellular"
    /// because the rule also covers a personal hotspot and Low Data Mode.
    private var cellularStreamQualityDescription: String {
        guard let cellularStreamQuality else {
            return "Live TV uses the quality above on every network."
        }
        return "Live TV switches to \(cellularStreamQuality.label) on cellular, a personal "
            + "hotspot, or in Low Data Mode. Chosen when playback starts — changing network "
            + "mid-program doesn't interrupt the stream."
    }
    #endif

    /// Explains the selected live TV quality. Like the other player settings
    /// this takes effect on the next stream, since the profile is chosen when
    /// the stream is opened.
    private var streamQualityDescription: String {
        streamQuality.summary + " Applies to the next channel you play."
    }
    #endif

    #if DISPATCHERPVR
    /// One row of the Output Profile picker (#161). `id` nil is Original.
    private struct OutputProfileChoice: Identifiable {
        let id: Int?
        let label: String
    }

    /// Original plus every active profile the server reports. When the saved
    /// id isn't among them (deleted server-side, or the list couldn't be read)
    /// it's kept as an explicit "unavailable" row so the picker never shows a
    /// blank selection and the user can see what will fall back.
    private var outputProfileChoices: [OutputProfileChoice] {
        var choices = [OutputProfileChoice(id: nil, label: "Original")]
        let profiles = client.outputProfiles ?? []
        choices += profiles.map { OutputProfileChoice(id: $0.id, label: $0.name) }
        if let outputProfileId, !profiles.contains(where: { $0.id == outputProfileId }) {
            choices.append(OutputProfileChoice(id: outputProfileId, label: "Profile #\(outputProfileId) (unavailable)"))
        }
        return choices
    }

    private var outputProfileLabel: String {
        outputProfileChoices.first(where: { $0.id == outputProfileId })?.label ?? "Original"
    }

    /// Explains the selected output profile. Like the other player settings
    /// this takes effect on the next stream, since the URL is built when the
    /// stream is opened.
    private var outputProfileDescription: String {
        guard let outputProfileId else {
            return "Streams live TV exactly as Dispatcharr delivers it, with no extra "
                + "server-side processing. Applies to the next channel you play."
        }
        if client.outputProfiles?.contains(where: { $0.id == outputProfileId }) == true {
            return "Dispatcharr runs this profile's FFmpeg step on live TV before sending it "
                + "to this device, trading server CPU for a client-friendly stream. "
                + "Applies to the next channel you play."
        }
        if client.outputProfiles == nil {
            return "This server didn't return its output profiles — it may be an older "
                + "Dispatcharr, or this account may lack API access. Live TV plays the "
                + "original stream until a profile can be verified."
        }
        return "This profile is no longer active on the server. Live TV plays the "
            + "original stream until you pick another."
    }

    private func saveOutputProfile(_ id: Int?) {
        outputProfileId = id
        var prefs = UserPreferences.load()
        prefs.outputProfileId = id
        prefs.save()
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

    private var guideSection: some View {
        Section {
            Toggle("Show Groups in Sidebar", isOn: $guideShowGroupsInSidebar)
                .onChange(of: guideShowGroupsInSidebar) { newValue in
                    saveGuideShowGroups(newValue)
                }
            if guideShowGroupsInSidebar {
                if epgCache.channelGroups.isEmpty {
                    Text("No channel groups available")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    let populatedGroups = epgCache.populatedChannelGroups
                    if populatedGroups.isEmpty {
                        Text("No channels in any group")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(populatedGroups) { group in
                            let isSelected = guideGroupIds.contains(group.id)
                            Button {
                                toggleGuideGroup(group.id)
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

            // Channel profiles are a Dispatcharr concept; NextPVR only has groups.
            #if DISPATCHERPVR
            Toggle("Show Profiles in Sidebar", isOn: $guideShowProfilesInSidebar)
                .onChange(of: guideShowProfilesInSidebar) { newValue in
                    saveGuideShowProfiles(newValue)
                }
            if guideShowProfilesInSidebar {
                if epgCache.channelProfiles.isEmpty {
                    Text("No channel profiles available")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    if populatedProfiles.isEmpty {
                        Text("No channels in any profile")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(populatedProfiles) { profile in
                            let isSelected = guideProfileIds.contains(profile.id)
                            Button {
                                toggleGuideProfile(profile.id)
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
            #endif
        } header: {
            Text("Guide")
        }
    }

    private func saveGuideShowGroups(_ show: Bool) {
        var prefs = UserPreferences.load()
        prefs.guideShowGroupsInSidebar = show
        prefs.save()
        if !show {
            appState.guideGroupFilter = nil
            appState.guideChannelFilter = ""
        }
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
    }

    private func toggleGuideGroup(_ id: Int) {
        if guideGroupIds.contains(id) {
            guideGroupIds.removeAll { $0 == id }
        } else {
            guideGroupIds.append(id)
        }
        var prefs = UserPreferences.load()
        prefs.guideGroupIds = guideGroupIds
        prefs.save()
        if !guideGroupIds.isEmpty, appState.guideGroupFilter == id, !guideGroupIds.contains(id) {
            appState.guideGroupFilter = nil
            appState.guideChannelFilter = ""
        }
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
    }

    #if DISPATCHERPVR
    /// Profiles that hold at least one channel; empty ones aren't offered.
    private var populatedProfiles: [ChannelProfile] {
        epgCache.channelProfiles.filter { profile in
            epgCache.guideSidebarChannels.contains { profile.channels.contains($0.id) }
        }
    }

    private func saveGuideShowProfiles(_ show: Bool) {
        var prefs = UserPreferences.load()
        prefs.guideShowProfilesInSidebar = show
        prefs.save()
        if !show {
            appState.guideProfileFilter = nil
            appState.guideChannelFilter = ""
        }
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
    }

    private func toggleGuideProfile(_ id: Int) {
        if guideProfileIds.contains(id) {
            guideProfileIds.removeAll { $0 == id }
        } else {
            guideProfileIds.append(id)
        }
        var prefs = UserPreferences.load()
        prefs.guideProfileIds = guideProfileIds
        prefs.save()
        if !guideProfileIds.isEmpty, appState.guideProfileFilter == id, !guideProfileIds.contains(id) {
            appState.guideProfileFilter = nil
            appState.guideChannelFilter = ""
        }
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
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
                    playDebugStream()
                }
            }
        } header: {
            Text("Debug")
        }
    }

    private func playDebugStream() {
        guard let url = URL(string: debugStreamURL) else { return }
        appState.playStream(
            url: url,
            title: debugStreamAsRecording ? "Test Recording" : "Test Stream",
            recordingId: debugStreamAsRecording ? -1 : nil
        )
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

#if os(macOS)
// MARK: - macOS (Midnight)

/// macOS Settings: a numbered category index beside one pane of rows. Only the
/// layout differs from iOS — every row reads and saves the same state.
extension SettingsView {
    var macOSContent: some View {
        persistingPlaybackPreferences(
            HStack(spacing: 0) {
                MacSettingsIndexView(selection: $macCategory, summary: macSummary(for:))
                MacSettingsPaneView(category: macCategory, hint: macHint(for: macCategory)) {
                    macRows(for: macCategory)
                }
                .id(macCategory)
            }
        )
        .toggleStyle(MidnightToggleStyle())
        .navigationDestination(isPresented: $showingMacEventLog) {
            EventLogView()
        }
        .onAppear(perform: applyRequestedCategory)
        .onChange(of: appState.requestedSettingsCategory) { _ in applyRequestedCategory() }
        .confirmationDialog("Unlink Server", isPresented: $showingUnlinkConfirm, titleVisibility: .visible) {
            Button("Unlink", role: .destructive) {
                unlinkServer()
            }
            .accessibilityIdentifier("confirm-unlink-button")
        } message: {
            Text("This will disconnect and forget the server. You'll need to set it up again.")
        }
    }

    @ViewBuilder
    private func macRows(for category: SettingsCategory) -> some View {
        switch category {
        case .server: macServerRows
        case .general: macGeneralRows
        case .playback: macPlaybackRows
        case .subtitles: macSubtitleRows
        case .guide: macGuideRows
        case .topics: macTopicsRows
        case .recordings: macRecordingRows
        case .advanced: macAdvancedRows
        }
    }

    // MARK: Summaries

    private func macSummary(for category: SettingsCategory) -> String {
        switch category {
        case .server:
            return client.config.displayAddress.isEmpty ? "Not configured" : client.config.displayAddress
        case .general:
            return "\(displayedLandingTab.label) · \(theme.label)"
        case .playback:
            #if DISPATCHERPVR
            let stream = outputProfileLabel
            #else
            let stream = streamQuality.label
            #endif
            return "\(stream) · \(seekBackwardSeconds)s / \(seekForwardSeconds)s"
        case .subtitles:
            let mode = subtitleMode == .manual ? "Manual" : "Auto"
            let background = subtitleBackground ? "background" : "no background"
            return "\(mode) · \(subtitleSize.displayName) · \(background)"
        case .guide:
            // Count only ticks that still match a listed group or profile: the
            // saved ids can outlive one deleted on the server.
            let groupCount = epgCache.populatedChannelGroups.filter { guideGroupIds.contains($0.id) }.count
            var parts = [guideShowGroupsInSidebar ? Self.count(groupCount, "group") : "Groups off"]
            #if DISPATCHERPVR
            let profileCount = populatedProfiles.filter { guideProfileIds.contains($0.id) }.count
            parts.append(guideShowProfilesInSidebar ? Self.count(profileCount, "profile") : "Profiles off")
            #endif
            return parts.joined(separator: " · ")
        case .topics:
            return topicList.isEmpty ? "None" : topicList.joined(separator: " · ")
        case .recordings:
            return hideRecordings ? "Hidden" : "Shown"
        case .advanced:
            return "\(macRendererShortName) · \(deinterlaceMode.label)"
        }
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    private func macHint(for category: SettingsCategory) -> String {
        guard category == .playback else { return category.hint }
        #if DISPATCHERPVR
        return outputProfileDescription
        #else
        return streamQualityDescription
        #endif
    }

    private var macRendererShortName: String {
        switch macosGPUAPI {
        case .pixelbuffer: "PixelBuffer"
        case .metal: "Metal"
        case .opengl: "OpenGL"
        }
    }

    // MARK: Panes

    @ViewBuilder
    private var macServerRows: some View {
        MacSettingsRow(title: "Host") {
            Text(verbatim: client.config.displayAddress)
                .midnightMeta(14, weight: .heavy)
                .foregroundStyle(MidnightPalette.ink)
                .textSelection(.enabled)
        }
        #if DISPATCHERPVR
        MacSettingsRow(title: "Server Public IP") {
            Text(verbatim: environmentServerValue)
                .midnightMeta(13, weight: .semibold)
                .foregroundStyle(MidnightPalette.ink)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("env-public-ip-and-location")
        }
        #endif
        MacSettingsRow(title: "Status") {
            if client.isAuthenticated {
                MidnightFieldChip(text: "Connected")
            } else {
                Text("Not connected")
                    .font(.archivo(12, .extraBold))
                    .textCase(.uppercase)
                    .foregroundStyle(MidnightPalette.danger)
            }
        }
        CustomHostSettingsRows()
        MacSettingsRow(title: "Unlink this device", subtitle: "Forget this server on this Mac.") {
            Button("Unlink") { showingUnlinkConfirm = true }
                .buttonStyle(MidnightOutlineButtonStyle(isDestructive: true))
                .accessibilityIdentifier("unlink-server-button")
        }
    }

    @ViewBuilder
    private var macGeneralRows: some View {
        MacSettingsRow(title: "Landing Page") {
            MidnightPicker(
                title: "Landing Page",
                selection: landingTabSelection,
                options: availableLandingOptions.map { ($0.label, $0) }
            )
            .accessibilityIdentifier("settings-landing-page-picker")
        }
        MacSettingsRow(title: "Theme") {
            MidnightPicker(
                title: "Theme",
                selection: themeSelection,
                options: AppTheme.allCases.map { ($0.label, $0) }
            )
            .accessibilityIdentifier("settings-theme-picker")
        }
    }

    @ViewBuilder
    private var macPlaybackRows: some View {
        MacSettingsRow(title: "Seek Backward") {
            MidnightPicker(
                title: "Seek Backward",
                selection: $seekBackwardSeconds,
                options: [5, 10, 15, 30].map { ("\($0) seconds", $0) }
            )
        }
        MacSettingsRow(title: "Seek Forward") {
            MidnightPicker(
                title: "Seek Forward",
                selection: $seekForwardSeconds,
                options: [15, 30, 45, 60].map { ("\($0) seconds", $0) }
            )
        }
        MacSettingsRow(title: "Audio Output") {
            MidnightPicker(
                title: "Audio Output",
                selection: $audioChannels,
                options: [("Auto", "auto"), ("Stereo", "stereo")]
            )
        }
        #if DISPATCHERPVR
        MacSettingsRow(title: "Live TV Output Profile") {
            MidnightPicker(
                title: "Live TV Output Profile",
                selection: $outputProfileId,
                options: outputProfileChoices.map { ($0.label, $0.id) }
            )
        }
        #else
        MacSettingsRow(title: "Live TV Quality") {
            MidnightPicker(
                title: "Live TV Quality",
                selection: $streamQuality,
                options: StreamQuality.allCases.map { ($0.label, $0) }
            )
        }
        MacSettingsRow(title: "On Cellular", subtitle: cellularStreamQualityDescription) {
            MidnightPicker(
                title: "On Cellular",
                selection: $cellularStreamQuality,
                options: [("Same as usual", StreamQuality?.none)]
                    + StreamQuality.allCases.map { ($0.label, StreamQuality?.some($0)) }
            )
        }
        #endif
    }

    @ViewBuilder
    private var macSubtitleRows: some View {
        MacSettingsRow(title: "Subtitles") {
            MidnightPicker(
                title: "Subtitles",
                selection: $subtitleMode,
                options: [("Manual", SubtitleMode.manual), ("Auto", SubtitleMode.auto)]
            )
        }
        MacSettingsRow(title: "Subtitle Size") {
            MidnightPicker(
                title: "Subtitle Size",
                selection: $subtitleSize,
                options: SubtitleSize.allCases.map { ($0.displayName, $0) }
            )
        }
        MacSettingsRow(title: "Subtitle Background") {
            Toggle("Subtitle Background", isOn: $subtitleBackground)
        }
    }

    @ViewBuilder
    private var macGuideRows: some View {
        MacSettingsRow(title: "Show Groups in Sidebar") {
            Toggle("Show Groups in Sidebar", isOn: $guideShowGroupsInSidebar)
                .onChange(of: guideShowGroupsInSidebar) { newValue in
                    saveGuideShowGroups(newValue)
                }
        }
        macGuideChoices(
            emptyMessage: epgCache.channelGroups.isEmpty ? "No channel groups available" : "No channels in any group",
            items: epgCache.populatedChannelGroups.map { ($0.id, $0.name) },
            selectedIds: guideGroupIds,
            isEnabled: guideShowGroupsInSidebar,
            toggle: toggleGuideGroup
        )
        #if DISPATCHERPVR
        MacSettingsRow(title: "Show Profiles in Sidebar") {
            Toggle("Show Profiles in Sidebar", isOn: $guideShowProfilesInSidebar)
                .onChange(of: guideShowProfilesInSidebar) { newValue in
                    saveGuideShowProfiles(newValue)
                }
        }
        macGuideChoices(
            emptyMessage: epgCache.channelProfiles.isEmpty ? "No channel profiles available" : "No channels in any profile",
            items: populatedProfiles.map { ($0.id, $0.name) },
            selectedIds: guideProfileIds,
            isEnabled: guideShowProfilesInSidebar,
            toggle: toggleGuideProfile
        )
        #endif
    }

    /// Checkbox rows under a Guide sidebar toggle, dimmed while it is off.
    private func macGuideChoices(
        emptyMessage: String,
        items: [(id: Int, name: String)],
        selectedIds: [Int],
        isEnabled: Bool,
        toggle: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.archivo(12.5))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .padding(.leading, 22)
                    .padding(.vertical, 8)
            } else {
                ForEach(items, id: \.id) { item in
                    MacSettingsCheckboxRow(title: item.name, isChecked: selectedIds.contains(item.id)) {
                        toggle(item.id)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }

    private func applyRequestedCategory() {
        guard let requested = appState.requestedSettingsCategory else { return }
        macCategory = requested
        appState.requestedSettingsCategory = nil
    }

    // MARK: Topics

    @ViewBuilder
    private var macTopicsRows: some View {
        MacSettingsRow(title: "Add a topic", subtitle: "Matched against program titles, subtitles and descriptions.") {
            HStack(spacing: 8) {
                TextField("e.g. Cycling", text: $newTopic)
                    .textFieldStyle(.plain)
                    .font(.archivo(13))
                    .frame(width: 200)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background { Rectangle().fill(MidnightPalette.inputBg) }
                    .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
                    .onSubmit(addTopic)
                    .accessibilityIdentifier("keyword-text-field")
                Button("Add", action: addTopic)
                    .buttonStyle(MidnightFieldButtonStyle())
                    .fixedSize()
                    .disabled(newTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("add-keyword-confirm")
            }
        }
        if topicList.isEmpty {
            Text("No topics yet.")
                .font(.archivo(12.5))
                .foregroundStyle(MidnightPalette.inkSoft)
                .padding(.vertical, 12)
        } else {
            ForEach(Array(topicList.enumerated()), id: \.element) { index, keyword in
                MacSettingsRow(title: keyword, subtitle: index == 0 ? "Opens by default" : nil) {
                    HStack(spacing: 6) {
                        Button {
                            moveTopic(at: index, by: -1)
                        } label: {
                            Image(systemName: "arrow.up").frame(width: 14, height: 14)
                        }
                        .buttonStyle(MidnightOutlineButtonStyle())
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(keyword) up")
                        Button {
                            moveTopic(at: index, by: 1)
                        } label: {
                            Image(systemName: "arrow.down").frame(width: 14, height: 14)
                        }
                        .buttonStyle(MidnightOutlineButtonStyle())
                        .disabled(index == topicList.count - 1)
                        .accessibilityLabel("Move \(keyword) down")
                        Button("Remove") { removeTopic(keyword) }
                            .buttonStyle(MidnightOutlineButtonStyle(isDestructive: true))
                    }
                }
            }
        }
    }


    @ViewBuilder
    private var macRecordingRows: some View {
        MacSettingsRow(title: "Hide Recording Features") {
            Toggle("Hide Recording Features", isOn: hideRecordingsSelection)
                .accessibilityIdentifier("settings-hide-recordings-toggle")
        }
    }

    @ViewBuilder
    private var macAdvancedRows: some View {
        MacSettingsRow(title: "Deinterlacing", subtitle: deinterlaceMode.summary) {
            MidnightPicker(
                title: "Deinterlacing",
                selection: $deinterlaceMode,
                options: DeinterlaceMode.allCases.map { ($0.label, $0) }
            )
        }
        MacSettingsRow(title: "Renderer", subtitle: rendererDescription(for: macosGPUAPI)) {
            MidnightPicker(
                title: "Renderer",
                selection: $macosGPUAPI,
                options: [GPUAPI.opengl, .metal, .pixelbuffer].map { (rendererName(for: $0), $0) }
            )
        }
        MacSettingsRow(
            title: "Event Log",
            subtitle: eventLog.events.isEmpty ? "No events recorded" : Self.count(eventLog.events.count, "event")
        ) {
            Button("View") { showingMacEventLog = true }
                .buttonStyle(MidnightOutlineButtonStyle())
        }
        #if DEBUG
        MacSettingsRow(title: "Test Stream Override") {
            Toggle("Test Stream Override", isOn: $debugStreamEnabled)
                .onChange(of: debugStreamEnabled) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "debugStreamEnabled")
                }
        }
        if debugStreamEnabled {
            MacSettingsRow(title: "Stream URL") {
                TextField("Stream URL", text: $debugStreamURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: 320)
                    .padding(6)
                    .background(MidnightPalette.inputBg)
                    .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
                    .onChange(of: debugStreamURL) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "debugStreamURL")
                    }
            }
            MacSettingsRow(title: "Play as Recording") {
                Toggle("Play as Recording", isOn: $debugStreamAsRecording)
                    .onChange(of: debugStreamAsRecording) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "debugStreamAsRecording")
                    }
            }
            MacSettingsRow(title: "Test Playback") {
                Button(debugStreamAsRecording ? "Play Recording" : "Play Stream") {
                    playDebugStream()
                }
                .buttonStyle(MidnightOutlineButtonStyle())
            }
        }
        #endif
    }
}
#endif

#if os(macOS) || os(tvOS)
// MARK: - Topics (macOS and tvOS Settings)

extension SettingsView {
    private func addTopic() {
        let trimmed = newTopic.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        newTopic = ""
        guard !topicList.contains(trimmed) else { return }
        topicList.append(trimmed)
        saveTopics()
    }

    private func removeTopic(_ keyword: String) {
        topicList.removeAll { $0 == keyword }
        saveTopics()
    }

    private func moveTopic(at index: Int, by offset: Int) {
        let destination = index + offset
        guard topicList.indices.contains(destination) else { return }
        topicList.swapAt(index, destination)
        saveTopics()
    }

    /// Same save path as `KeywordsEditorView`: persist, then publish the list so
    /// the sidebar's topic rows and counts follow.
    private func saveTopics() {
        var prefs = UserPreferences.load()
        prefs.keywords = topicList
        prefs.save()
        appState.topicKeywords = topicList
        if !topicList.contains(appState.selectedTopicKeyword) {
            appState.selectedTopicKeyword = topicList.first ?? ""
        }
    }
}
#endif

#if os(tvOS)
private struct TVSettingsPopupButtonStyle: ButtonStyle {
    enum Variant {
        case regular
        case destructive
        case cancel
    }

    let variant: Variant
    var isCurrent = false

    func makeBody(configuration: Configuration) -> some View {
        TVSettingsPopupButtonBody(variant: variant, isCurrent: isCurrent, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

/// Midnight popup option: a plate that inverts when focused; the current
/// value carries a check, a destructive option the danger colour.
private struct TVSettingsPopupButtonBody<Content: View>: View {
    let variant: TVSettingsPopupButtonStyle.Variant
    let isCurrent: Bool
    let isPressed: Bool
    @ViewBuilder let content: Content

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 12) {
            content
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: Theme.scaledFont(18), weight: .heavy))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.accent)
            }
        }
        .font(.archivo(Theme.scaledFont(21), .extraBold))
        .foregroundStyle(ink)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle().fill(variant == .destructive ? MidnightPalette.dangerInk : MidnightPalette.accent).frame(width: 6)
            }
        }
        .scaleEffect(isPressed ? 0.99 : (isFocused ? 1.01 : 1.0))
        .animation(.easeInOut(duration: 0.14), value: isFocused)
    }

    private var ink: Color {
        switch variant {
        case .destructive: return isFocused ? .white : MidnightPalette.danger
        case .regular, .cancel: return isFocused ? MidnightPalette.selectedInk : (variant == .cancel ? MidnightPalette.inkSoft : MidnightPalette.ink)
        }
    }

    private var background: Color {
        if isFocused { return variant == .destructive ? MidnightPalette.danger : MidnightPalette.selectedBg }
        return MidnightPalette.cellRest
    }
}
#endif

#Preview {
    SettingsView()
        .environmentObject(PVRClient())
        .preferredColorScheme(.dark)
}
