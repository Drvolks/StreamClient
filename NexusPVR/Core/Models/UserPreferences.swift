//
//  UserPreferences.swift
//  nextpvr-apple-client
//
//  User preferences and settings - synced via iCloud
//

import Foundation

nonisolated struct UserPreferences: Codable {
    var keywords: [String] = []
    var seekBackwardSeconds: Int = 10
    var seekForwardSeconds: Int = 30
    var audioChannels: String = "auto"
    var tvosGPUAPI: GPUAPI = .pixelbuffer
    var iosGPUAPI: GPUAPI = .pixelbuffer
    var macosGPUAPI: GPUAPI = .pixelbuffer
    var subtitleMode: SubtitleMode = .manual
    var subtitleSize: SubtitleSize = .medium
    var subtitleBackground: Bool = true
    /// Deinterlacing mode applied by the player (#142). Defaults to `.auto`
    /// so interlaced broadcasts (DVB 1080i50 / 576i50, ATSC 1080i60) play
    /// without combing while progressive channels are left untouched.
    var deinterlaceMode: DeinterlaceMode = .auto
    /// Server-side transcoding profile requested for live TV. Defaults to
    /// `.original`, which keeps the existing direct-stream behaviour: NextPVR
    /// only transcodes when a client asks it to, so an upgrading user sees no
    /// change in bandwidth, quality or CPU load on their server.
    var streamQuality: StreamQuality = .original
    /// Quality used instead of `streamQuality` while on a metered network
    /// (cellular, personal hotspot, or Low Data Mode). Nil means "same as
    /// usual" — the default, so an upgrade changes nothing until asked.
    var cellularStreamQuality: StreamQuality? = nil
    /// Dispatcharr Output Profile requested on live TV URLs (#161). Nil is
    /// Original / pass-through — the default, which leaves every live URL
    /// exactly as before. Unused by the NextPVR variant, which has its own
    /// server-side transcoding via `streamQuality`. Stored as the server's
    /// profile id, so the choice is validated against the connected server's
    /// active profiles at play time rather than trusted blindly.
    var outputProfileId: Int? = nil
    /// User-selectable tvOS UI font size (#107). Default `.medium`
    /// preserves the pre-feature visual output exactly — existing
    /// users see zero change on first launch after upgrade.
    var uiFontSize: UIFontSize = .medium
    var preferredSubtitleLanguage: String? = nil
    var guideShowGroupsInSidebar: Bool = false
    var guideGroupIds: [Int] = []
    var guideShowProfilesInSidebar: Bool = false
    var guideProfileIds: [Int] = []
    /// Persisted raw value of the tab the app should open to at launch.
    /// Stored as a `String` so this model stays free of UI dependencies;
    /// resolve via the `landingTab` computed property.
    var landingTabRawValue: String = LandingTabOption.defaultRawValue
    /// When true, all recording features (tabs, menus, buttons) are hidden (#110).
    var hideRecordings: Bool = false
    /// Persisted raw value of the appearance override (#108). Stored as a
    /// `String` for the same reason as `landingTabRawValue`: this model stays
    /// free of UI (SwiftUI) dependencies. Resolve via the `theme` property.
    var themeRawValue: String = AppTheme.defaultRawValue
    var updatedAt: Date = .distantPast

    /// The GPU API for the current platform.
    var currentGPUAPI: GPUAPI {
        #if os(tvOS)
        tvosGPUAPI
        #elseif os(macOS)
        macosGPUAPI
        #else
        iosGPUAPI
        #endif
    }

    /// The tab the app should open to at launch. The raw value is stored on
    /// disk so this struct doesn't need to import the navigation module.
    var landingTab: LandingTabOption {
        get { LandingTabOption(rawValue: landingTabRawValue) ?? .guide }
        set { landingTabRawValue = newValue.rawValue }
    }

    /// The appearance the app should use. The raw value is stored on disk so
    /// this struct doesn't need to import SwiftUI.
    var theme: AppTheme {
        get { AppTheme(rawValue: themeRawValue) ?? .system }
        set { themeRawValue = newValue.rawValue }
    }

    /// Live TV stream quality. `.original` streams the tuner's transport
    /// stream untouched (what the app has always done); every other case asks
    /// NextPVR to transcode via `channel.transcode.initiate`, trading server
    /// CPU for bandwidth.
    ///
    /// The raw values are the resolutions Kodi's `pvr.nextpvr` addon offers,
    /// in the same order, because those are the profile names NextPVR servers
    /// ship with — see `instance-settings.xml` in that addon.
    ///
    /// Nested here for the same reason as `DeinterlaceMode` — the tvOS Top
    /// Shelf extension shares `UserPreferences.swift` but not its sibling
    /// Core/Models files.
    nonisolated enum StreamQuality: String, CaseIterable, Identifiable, Codable {
        case original = "Original"
        case p1080 = "1080"
        case p720 = "720"
        case p576 = "576"
        case p504 = "504"
        case p480 = "480"
        case p360 = "360"
        case p240 = "240"
        case p144 = "144"

        var id: String { rawValue }
    }

    /// User-selectable deinterlacing mode (#142). Nested here for the same
    /// reason as `AppTheme` — the tvOS Top Shelf extension shares
    /// `UserPreferences.swift` but not its sibling Core/Models files.
    nonisolated enum DeinterlaceMode: String, CaseIterable, Identifiable, Codable {
        case off = "Off"
        case auto = "Auto"
        case on = "On"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: return "Off"
            case .auto: return "Automatic"
            case .on: return "Always On"
            }
        }
    }

    /// User-selectable appearance override (#108). Nested here for the same
    /// reason as `LandingTabOption` — the tvOS Top Shelf extension shares
    /// `UserPreferences.swift` but not its sibling Core/Models files.
    nonisolated enum AppTheme: String, CaseIterable, Identifiable, Codable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        /// The raw value used when no preference has been persisted.
        static var defaultRawValue: String { AppTheme.system.rawValue }
    }

    /// User-selectable landing page option. Nested inside `UserPreferences`
    /// (rather than defined as a separate top-level type) so the persistence
    /// model is self-contained: the tvOS Top Shelf extension shares
    /// `UserPreferences.swift` but does not include sibling Core/Models
    /// files. Keeping the enum here means a single source file is enough for
    /// the Top Shelf to keep compiling.
    nonisolated enum LandingTabOption: String, CaseIterable, Identifiable, Codable {
        case guide = "Guide"
        case channels = "Channels"
        case completedRecordings = "CompletedRecordings"
        #if DISPATCHERPVR
        case stats = "Stats"
        #endif

        var id: String { rawValue }

        var label: String {
            switch self {
            case .guide: return "Guide"
            case .channels: return "Channels"
            case .completedRecordings: return "Completed Recordings"
            #if DISPATCHERPVR
            case .stats: return "Status"
            #endif
            }
        }

        /// The raw value used when no preference has been persisted.
        static var defaultRawValue: String { LandingTabOption.guide.rawValue }
    }

    // Migration: keep old property for decoding existing data
    private enum CodingKeys: String, CodingKey {
        case keywords
        case seekBackwardSeconds
        case seekForwardSeconds
        case seekTimeSeconds // legacy
        case audioChannels
        case tvosGPUAPI
        case iosGPUAPI
        case macosGPUAPI
        case subtitleMode
        case subtitleSize
        case subtitleBackground
        case deinterlaceMode
        case streamQuality
        case cellularStreamQuality
        case outputProfileId
        case uiFontSize
        case preferredSubtitleLanguage
        case guideShowGroupsInSidebar
        case guideGroupIds
        case guideShowProfilesInSidebar
        case guideProfileIds
        case landingTabRawValue
        case hideRecordings
        case themeRawValue
        case updatedAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        seekBackwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekBackwardSeconds) ?? 10
        // Migrate from old seekTimeSeconds if seekForwardSeconds not present
        if let forward = try container.decodeIfPresent(Int.self, forKey: .seekForwardSeconds) {
            seekForwardSeconds = forward
        } else if let legacy = try container.decodeIfPresent(Int.self, forKey: .seekTimeSeconds) {
            seekForwardSeconds = legacy
        } else {
            seekForwardSeconds = 30
        }
        audioChannels = try container.decodeIfPresent(String.self, forKey: .audioChannels) ?? "auto"
        tvosGPUAPI = try container.decodeIfPresent(GPUAPI.self, forKey: .tvosGPUAPI) ?? .pixelbuffer
        iosGPUAPI = try container.decodeIfPresent(GPUAPI.self, forKey: .iosGPUAPI) ?? .pixelbuffer
        macosGPUAPI = try container.decodeIfPresent(GPUAPI.self, forKey: .macosGPUAPI) ?? .pixelbuffer
        subtitleMode = try container.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode) ?? .manual
        subtitleSize = try container.decodeIfPresent(SubtitleSize.self, forKey: .subtitleSize) ?? .medium
        subtitleBackground = try container.decodeIfPresent(Bool.self, forKey: .subtitleBackground) ?? true
        // Prefs written before #142 have no `deinterlaceMode`; they decode to
        // .auto, which is the recommended default for broadcast streams.
        deinterlaceMode = try container.decodeIfPresent(DeinterlaceMode.self, forKey: .deinterlaceMode) ?? .auto
        // Prefs written before this setting existed decode to .original, so an
        // upgrade never silently starts transcoding on someone's server.
        streamQuality = try container.decodeIfPresent(StreamQuality.self, forKey: .streamQuality) ?? .original
        cellularStreamQuality = try container.decodeIfPresent(StreamQuality.self, forKey: .cellularStreamQuality)
        // Prefs written before #161 have no `outputProfileId`: Original.
        outputProfileId = try container.decodeIfPresent(Int.self, forKey: .outputProfileId)
        // Forward- and backward-compat: a blob without `uiFontSize`
        // (any prefs written before #107) decodes to .medium so
        // existing users see no visual change.
        uiFontSize = try container.decodeIfPresent(UIFontSize.self, forKey: .uiFontSize) ?? .medium
        preferredSubtitleLanguage = try container.decodeIfPresent(String.self, forKey: .preferredSubtitleLanguage)
        guideShowGroupsInSidebar = try container.decodeIfPresent(Bool.self, forKey: .guideShowGroupsInSidebar) ?? false
        guideGroupIds = try container.decodeIfPresent([Int].self, forKey: .guideGroupIds) ?? []
        guideShowProfilesInSidebar = try container.decodeIfPresent(Bool.self, forKey: .guideShowProfilesInSidebar) ?? false
        guideProfileIds = try container.decodeIfPresent([Int].self, forKey: .guideProfileIds) ?? []
        landingTabRawValue = try container.decodeIfPresent(String.self, forKey: .landingTabRawValue) ?? LandingTabOption.defaultRawValue
        hideRecordings = try container.decodeIfPresent(Bool.self, forKey: .hideRecordings) ?? false
        themeRawValue = try container.decodeIfPresent(String.self, forKey: .themeRawValue) ?? AppTheme.defaultRawValue
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(seekBackwardSeconds, forKey: .seekBackwardSeconds)
        try container.encode(seekForwardSeconds, forKey: .seekForwardSeconds)
        try container.encode(audioChannels, forKey: .audioChannels)
        try container.encode(tvosGPUAPI, forKey: .tvosGPUAPI)
        try container.encode(iosGPUAPI, forKey: .iosGPUAPI)
        try container.encode(macosGPUAPI, forKey: .macosGPUAPI)
        try container.encode(subtitleMode, forKey: .subtitleMode)
        try container.encode(subtitleSize, forKey: .subtitleSize)
        try container.encode(subtitleBackground, forKey: .subtitleBackground)
        try container.encode(deinterlaceMode, forKey: .deinterlaceMode)
        try container.encode(streamQuality, forKey: .streamQuality)
        try container.encodeIfPresent(cellularStreamQuality, forKey: .cellularStreamQuality)
        try container.encodeIfPresent(outputProfileId, forKey: .outputProfileId)
        try container.encode(uiFontSize, forKey: .uiFontSize)
        try container.encodeIfPresent(preferredSubtitleLanguage, forKey: .preferredSubtitleLanguage)
        try container.encode(guideShowGroupsInSidebar, forKey: .guideShowGroupsInSidebar)
        try container.encode(guideGroupIds, forKey: .guideGroupIds)
        try container.encode(guideShowProfilesInSidebar, forKey: .guideShowProfilesInSidebar)
        try container.encode(guideProfileIds, forKey: .guideProfileIds)
        try container.encode(landingTabRawValue, forKey: .landingTabRawValue)
        try container.encode(hideRecordings, forKey: .hideRecordings)
        try container.encode(themeRawValue, forKey: .themeRawValue)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static let storageKey = "UserPreferences"
    private static var ubiquitousStore: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }

    /// In-memory store for demo mode — when set, load/save bypass persistence
    nonisolated(unsafe) static var demoStore: UserPreferences?

    static func load() -> UserPreferences {
        if let demo = demoStore { return demo }

        let cloudPrefs = ubiquitousStore.data(forKey: storageKey).flatMap(decode)
        let localPrefs = UserDefaults.standard.data(forKey: storageKey).flatMap(decode)

        if let prefs = resolvePersistence(local: localPrefs, cloud: cloudPrefs) {
            persist(prefs)
            return prefs
        }

        return UserPreferences()
    }

    func save() {
        if Self.demoStore != nil {
            Self.demoStore = self
            return
        }
        var prefs = self
        prefs.updatedAt = Date()
        Self.persist(prefs)
        NotificationCenter.default.post(name: Notification.Name("preferencesDidSync"), object: nil)
    }

    static func loadFromAppGroup() -> UserPreferences {
        guard let data = UserDefaults(suiteName: ServerConfig.appGroupSuite)?.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return UserPreferences()
        }
        return prefs
    }

    /// Call this to start observing iCloud sync changes
    static func startObservingSync(onChange: @escaping @Sendable () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { _ in
            onChange()
        }
    }

    private static func decode(_ data: Data) -> UserPreferences? {
        try? JSONDecoder().decode(UserPreferences.self, from: data)
    }

    static func resolvePersistence(local: UserPreferences?, cloud: UserPreferences?) -> UserPreferences? {
        switch (local, cloud) {
        case let (local?, cloud?):
            if local.updatedAt == .distantPast && cloud.updatedAt == .distantPast {
                return local
            }
            return local.updatedAt >= cloud.updatedAt ? local : cloud
        case let (local?, nil):
            return local
        case let (nil, cloud?):
            return cloud
        case (nil, nil):
            return nil
        }
    }

    private static func persist(_ prefs: UserPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }

        // Save to iCloud for sync
        ubiquitousStore.set(data, forKey: storageKey)
        ubiquitousStore.synchronize()

        // Also save locally as backup
        UserDefaults.standard.set(data, forKey: storageKey)

        // Save to App Group for Top Shelf extension
        UserDefaults(suiteName: ServerConfig.appGroupSuite)?.set(data, forKey: storageKey)
    }
}
