//
//  EPGCache.swift
//  PVR Client
//
//  Central cache/index for channels and EPG data.
//  Loads all data upfront, provides windowed access for the guide,
//  and instant search/topic matching without additional network calls.
//

import SwiftUI
import Combine

@MainActor
final class EPGCache: ObservableObject {
    /// All channels (full list, sorted by number)
    @Published var channels: [Channel] = []
    /// Channels to display in the guide — first 20 initially, all after EPG loads
    @Published var visibleChannels: [Channel] = []
    /// Unfiltered channel snapshot used for guide sidebar/filter metadata.
    /// Dispatcharr profile reloads narrow `channels`/`visibleChannels` server-side;
    /// this preserves the all-channel list so profile shortcuts don't hide group shortcuts.
    @Published private(set) var guideSidebarChannels: [Channel] = []
    @Published var channelProfiles: [ChannelProfile] = []
    @Published var channelGroups: [ChannelGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isFullyLoaded = false
    /// True while a user-initiated refresh is in flight (see `refresh(using:profileId:)`).
    /// Unlike `isLoading`, the existing data stays on screen while this is true.
    @Published private(set) var isRefreshing = false
    /// When channels + the fast EPG window were last fetched successfully, by
    /// either `loadData` or `refresh`. Scene activation uses it to skip
    /// refreshing data that is still fresh (see `EPGActivationRefreshPolicy`).
    private(set) var lastRefreshDate: Date?
    @Published private(set) var error: String?
    /// Start time of the oldest program currently present in the cache. Date
    /// navigation uses its day as a hard lower bound.
    @Published private(set) var earliestEPGDate: Date?

    private(set) var channelMap: [Int: Channel] = [:]
    private(set) var epg: [Int: [Program]] = [:] {
        didSet { epgGeneration &+= 1 }
    }
    /// Bumped whenever `epg` is replaced or merged into. Views that memoize
    /// derived slices of the EPG (see `GuideViewModel.programs(for:)`) key
    /// their caches on this so a background merge or refresh invalidates them
    /// without any explicit notification (#141).
    private(set) var epgGeneration: Int = 0
    /// Days whose listings are completely in the cache ("yyyy-MM-dd" keys).
    private var loadedDays: Set<String> = []
    /// Set once a full-EPG download has put every day the server has in the
    /// cache, for backends that can't serve a single day.
    private var hasCompleteEPG = false
    /// Day requests in flight, so date navigation joins the background
    /// preload's request for a day instead of repeating it.
    private var dayLoads: [String: Task<EPGDayLoadOutcome, Never>] = [:]
    /// Bumped whenever `epg` is replaced rather than merged into. A day
    /// request captures it and drops its listings once it no longer matches,
    /// so they can't land in a cache loaded for another profile or server.
    private var epgEpoch = 0
    /// Channel profile the cached channels were loaded for; day requests pass
    /// it so the server only sends that profile's programmes.
    private var loadedProfileId: Int?
    private var backgroundLoadTask: Task<Void, Never>?
    private var isLoadInProgress = false
    /// Bumped by `invalidate()` and by every `loadData`. A load or refresh
    /// captures it before its first `await` and drops its results once it no
    /// longer matches: an invalidated load that kept going would otherwise
    /// start its background phase, leave `isLoadInProgress` set and make the
    /// replacement `loadData` return early, so the pages waited on
    /// `hasLoaded` forever (#179).
    private var loadGeneration = 0

    /// How far the background preload reaches around today. Days outside it
    /// load on demand (`ensureDay`), so this only bounds what search and
    /// topics can see without navigating there first.
    nonisolated static let preloadDaysBack = 1
    nonisolated static let preloadDaysForward = 14
    nonisolated private static let preloadConcurrency = 4
    /// Dispatcharr's own cap on how far back the grid looks.
    nonisolated private static let maximumHistoryDays = 30

    nonisolated private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = Calendar.current.timeZone
        return f
    }()

    // MARK: - Loading

    func loadData(using client: PVRClient, profileId: Int? = nil) async {
        // Prevent concurrent loads
        guard !isLoadInProgress else { return }
        guard client.isConfigured else {
            error = "Server not configured"
            return
        }

        backgroundLoadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoadInProgress = true
        isLoading = true
        hasLoaded = false
        isFullyLoaded = false
        error = nil
        replaceEPG(with: [:])
        loadedProfileId = profileId
        let totalStart = CFAbsoluteTimeGetCurrent()

        do {
            if !client.isAuthenticated {
                let authStart = CFAbsoluteTimeGetCurrent()
                try await client.authenticate()
                print("[EPGCache] Auth: \(ms(since: authStart))ms")
            }

            // Fetch all channels
            let channelsStart = CFAbsoluteTimeGetCurrent()
            #if DISPATCHERPVR
            let loaded = try await client.getChannelSummary(profileId: profileId)
            #else
            let loaded = try await client.getChannels()
            #endif
            guard generation == loadGeneration else { return }
            let sorted = loaded.sorted { $0.number < $1.number }
            channels = sorted
            if profileId == nil || guideSidebarChannels.isEmpty {
                guideSidebarChannels = sorted
            }
            channelMap = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            print("[EPGCache] Channels: \(sorted.count) in \(ms(since: channelsStart))ms")

            // Show the grid immediately with all channels
            // LazyVStack only renders visible rows (~15), so 1000 channels is fine
            visibleChannels = sorted

            // Fetch channel profiles and groups (Dispatcharr only)
            #if DISPATCHERPVR
            channelProfiles = (try? await client.getChannelProfiles()) ?? []
            channelGroups = (try? await client.getChannelGroups()) ?? []
            #endif
            guard generation == loadGeneration else { return }

            hasLoaded = true
            isLoading = false
            lastRefreshDate = Date()
            print("[EPGCache] Grid ready (\(visibleChannels.count) channels): \(ms(since: totalStart))ms")

            #if DISPATCHERPVR
            enrichWithCatchupInfo(using: client)
            #else
            enrichWithChannelGroups(using: client)
            #endif

            // Two-phase EPG load:
            //   1. Foreground (awaited): fetch the small "fast window" so the
            //      guide is interactive ASAP (Dispatcharr /api/epg/grid/, or
            //      NextPVR per-channel with start/end window).
            //   2. Background (detached): fetch the surrounding days and merge
            //      them into the cache so date navigation, search and topics
            //      work without refetching.
            let channelsForEPG = sorted
            do {
                let fastStart = CFAbsoluteTimeGetCurrent()
                let fastListings = try await client.getFastListings(for: channelsForEPG, profileId: profileId)
                guard generation == loadGeneration else { return }
                // Merged, not swapped in: the cache was emptied above, and a
                // day request started since (catch-up history) must survive.
                merge(fastListings)
                let fastCount = fastListings.values.reduce(0) { $0 + $1.count }
                print("[EPGCache] Fast EPG: \(fastCount) programs across \(fastListings.count) channels in \(ms(since: fastStart))ms")
            } catch {
                print("[EPGCache] Fast EPG failed (\(error.localizedDescription)), falling back to full load")
            }
            guard generation == loadGeneration else { return }

            startBackgroundFullLoad(using: client, channels: channelsForEPG, totalStart: totalStart)

        } catch {
            guard generation == loadGeneration else { return }
            self.error = error.localizedDescription
            isLoading = false
            isLoadInProgress = false
            hasLoaded = true
            print("[EPGCache] Load failed after \(ms(since: totalStart))ms: \(error.localizedDescription)")
        }
    }

    /// Phase 2 of a load: fetch the days around today in the background and
    /// merge them into whatever the fast window already put in the cache.
    /// Backends that can't serve a single day get one full-EPG download.
    private func startBackgroundFullLoad(using client: PVRClient, channels channelsForEPG: [Channel], totalStart: CFAbsoluteTime) {
        isLoadInProgress = true
        backgroundLoadTask = Task { [weak self] in
            guard let self else { return }
            let epgStart = CFAbsoluteTimeGetCurrent()
            do {
                let loadedByDay = await self.preloadDays(using: client)
                guard !Task.isCancelled else { return }
                if !loadedByDay {
                    let epoch = self.epgEpoch
                    let listings = try await client.getAllListings(for: channelsForEPG)
                    guard !Task.isCancelled, epoch == self.epgEpoch else { return }
                    self.merge(listings)
                    // Compute loaded days off main actor
                    let snapshot = self.epg
                    let days = await Task.detached(priority: .utility) {
                        var daySet = Set<String>()
                        for programs in snapshot.values {
                            for program in programs {
                                daySet.insert(Self.dayFormatter.string(from: program.startDate))
                            }
                        }
                        return daySet
                    }.value
                    guard !Task.isCancelled, epoch == self.epgEpoch else { return }
                    self.loadedDays = days
                    self.hasCompleteEPG = true
                }
                self.isLoadInProgress = false
                self.isFullyLoaded = true
                let programCount = self.epg.values.reduce(0) { $0 + $1.count }
                print("[EPGCache] EPG (\(loadedByDay ? "by day" : "full")): \(programCount) programs across \(self.epg.count) channels in \(self.ms(since: epgStart))ms")
                print("[EPGCache] Total load: \(self.ms(since: totalStart))ms")
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoadInProgress = false
                print("[EPGCache] EPG load failed: \(error.localizedDescription)")
            }
        }
    }

    /// Loads the days around today one window at a time, nearest first.
    /// A day that fails is left unloaded — it is retried when the user
    /// navigates to it — and the rest still load.
    ///
    /// Returns false when the backend can't serve a single day, in which case
    /// nothing was loaded and the caller downloads the full EPG instead.
    private func preloadDays(using client: PVRClient) async -> Bool {
        var days = EPGDayWindows.preloadOrder(
            now: Date(),
            daysBack: Self.preloadDaysBack,
            daysForward: Self.preloadDaysForward
        ).makeIterator()

        // Today goes first on its own: it settles whether the backend serves
        // single days before the rest fan out.
        guard let today = days.next() else { return true }
        if await loadDay(today, using: client) == .unsupported { return false }

        return await withTaskGroup(of: EPGDayLoadOutcome.self) { group in
            func addNext() {
                guard !Task.isCancelled, let day = days.next() else { return }
                group.addTask { await self.loadDay(day, using: client) }
            }
            for _ in 0..<Self.preloadConcurrency { addNext() }

            var supported = true
            for await outcome in group {
                if outcome == .unsupported {
                    supported = false
                } else if supported {
                    addNext()
                }
            }
            return supported
        }
    }

    /// Fetches one day's listings and merges them into the cache, joining a
    /// request already in flight for that day.
    private func loadDay(_ day: DateInterval, using client: PVRClient) async -> EPGDayLoadOutcome {
        let key = Self.dayFormatter.string(from: day.start)
        if loadedDays.contains(key) { return .loaded }
        if let running = dayLoads[key] { return await running.value }

        let epoch = epgEpoch
        let channels = self.channels
        let profileId = loadedProfileId
        let task = Task { [weak self] () -> EPGDayLoadOutcome in
            let start = CFAbsoluteTimeGetCurrent()
            do {
                guard let listings = try await client.getListings(for: channels, in: day, profileId: profileId) else {
                    return .unsupported
                }
                guard let self, epoch == self.epgEpoch else { return .failed }
                self.merge(listings)
                self.loadedDays.insert(key)
                let count = listings.values.reduce(0) { $0 + $1.count }
                print("[EPGCache] Loaded day \(key): \(count) programs in \(self.ms(since: start))ms")
                return .loaded
            } catch {
                // Keep what we have: the day stays unloaded and can be retried.
                print("[EPGCache] Day \(key) failed: \(error.localizedDescription)")
                return .failed
            }
        }
        dayLoads[key] = task
        let outcome = await task.value
        if dayLoads[key] == task {
            dayLoads[key] = nil
        }
        return outcome
    }

    /// User-initiated refresh (pull-to-refresh on iOS/macOS, refresh button on
    /// tvOS): re-fetch channels, groups/profiles and EPG from the server so
    /// server-side changes (a new channel, an updated EPG) show up without
    /// restarting the app.
    ///
    /// Unlike `reloadData`, the currently cached data stays on screen for the
    /// whole refresh — `hasLoaded`/`isFullyLoaded` are never flipped back to
    /// false, so the guide doesn't collapse into its loading state and then
    /// rebuild. New data is swapped in only once it has arrived.
    func refresh(using client: PVRClient, profileId: Int? = nil) async {
        guard !isRefreshing else { return }
        guard client.isConfigured else {
            error = "Server not configured"
            return
        }

        // Drop any in-flight full-EPG load: it would merge stale listings on top
        // of the data we are about to fetch.
        backgroundLoadTask?.cancel()
        backgroundLoadTask = nil
        isLoadInProgress = false

        isRefreshing = true
        defer { isRefreshing = false }
        let generation = loadGeneration
        let totalStart = CFAbsoluteTimeGetCurrent()

        do {
            if !client.isAuthenticated {
                try await client.authenticate()
            }

            #if DISPATCHERPVR
            let loaded = try await client.getChannelSummary(profileId: profileId)
            #else
            let loaded = try await client.getChannels()
            #endif
            let sorted = loaded.sorted { $0.number < $1.number }

            #if DISPATCHERPVR
            let profiles = try? await client.getChannelProfiles()
            let groups = try? await client.getChannelGroups()
            #endif

            // Fetch the fast window before publishing anything, so the grid never
            // shows a channel row without its programs.
            let fastListings = try? await client.getFastListings(for: sorted, profileId: profileId)
            guard generation == loadGeneration else { return }

            channels = sorted
            if profileId == nil || guideSidebarChannels.isEmpty {
                guideSidebarChannels = sorted
            }
            channelMap = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            visibleChannels = sorted
            #if DISPATCHERPVR
            if let profiles { channelProfiles = profiles }
            if let groups { channelGroups = groups }
            #endif
            loadedProfileId = profileId
            if let fastListings {
                // Replace rather than merge: programs removed server-side must go.
                replaceEPG(with: fastListings)
            } else {
                // Nothing to swap in, but every day is still due a re-fetch.
                loadedDays = []
                hasCompleteEPG = false
            }
            error = nil
            hasLoaded = true
            lastRefreshDate = Date()
            print("[EPGCache] Refresh: \(sorted.count) channels in \(ms(since: totalStart))ms")

            #if DISPATCHERPVR
            enrichWithCatchupInfo(using: client)
            #else
            enrichWithChannelGroups(using: client)
            #endif

            startBackgroundFullLoad(using: client, channels: sorted, totalStart: totalStart)
        } catch {
            guard generation == loadGeneration else { return }
            self.error = error.localizedDescription
            print("[EPGCache] Refresh failed after \(ms(since: totalStart))ms: \(error.localizedDescription)")
        }
    }

    func reloadData(using client: PVRClient, profileId: Int? = nil) async {
        let sidebarChannels = guideSidebarChannels
        invalidate()
        if profileId != nil {
            guideSidebarChannels = sidebarChannels
        }
        await loadData(using: client, profileId: profileId)
    }

    /// Ensure EPG data for a specific day is loaded. Returns false when the
    /// day could not be fetched; whatever was cached stays as it was.
    ///
    /// Backends with a windowed endpoint fetch just that day. The others have
    /// only the full EPG to offer: wait for the background load if it is still
    /// running, and download it here if that failed or was cancelled.
    @discardableResult
    func ensureDay(_ date: Date, using client: PVRClient) async -> Bool {
        let key = Self.dayFormatter.string(from: date)
        if hasCompleteEPG || loadedDays.contains(key) { return true }

        switch await loadDay(EPGDayWindows.day(containing: date), using: client) {
        case .loaded: return true
        case .failed: return false
        case .unsupported: break
        }

        if let task = backgroundLoadTask {
            await task.value
            if hasCompleteEPG || loadedDays.contains(key) { return true }
        }

        let start = CFAbsoluteTimeGetCurrent()
        let epoch = epgEpoch
        do {
            let listings = try await client.getAllListings(for: channels)
            guard epoch == epgEpoch else { return false }
            merge(listings)
            markLoadedDays(from: listings)
            hasCompleteEPG = true
            print("[EPGCache] Loaded full EPG for day \(key) in \(ms(since: start))ms")
            return true
        } catch {
            // Silently fail — user can retry via date navigation
            return false
        }
    }

    /// Ensures every day from `start` through `end` is loaded, most recent
    /// first — a catch-up archive spans several. Stops at the first day that
    /// can't be fetched rather than failing the same way for each one.
    func ensureDays(from start: Date, through end: Date, using client: PVRClient) async {
        for day in EPGDayWindows.days(from: start, through: end).reversed() {
            guard !Task.isCancelled, await ensureDay(day.start, using: client) else { return }
        }
    }

    #if DISPATCHERPVR
    /// Backfills `isCatchup`/`catchupDays` (#119) onto channels loaded via
    /// `getChannelSummary(profileId:)`, whose `summary/` serializer omits
    /// both fields (confirmed against a live server — the full
    /// `/api/channels/channels/` endpoint has them, `/summary/` doesn't).
    /// Runs in the background after the initial paint so it never delays
    /// the guide showing up; the badge/button just appear a beat later.
    private func enrichWithCatchupInfo(using client: PVRClient) {
        Task { [weak self] in
            guard let self else { return }
            guard let info = try? await client.getChannelCatchupInfo(), !info.isEmpty else { return }
            self.applyCatchupInfo(info)
            await self.loadCatchupHistory(using: client)
        }
    }

    /// Loads the past days catch-up can still play, so the guide can browse
    /// back through them. The background preload only reaches yesterday: how
    /// far back the archive goes isn't known until the catch-up info arrives.
    private func loadCatchupHistory(using client: PVRClient) async {
        let archiveDays = channels.filter(\.isCatchup).map(\.catchupDays).max() ?? 0
        let daysBack = min(archiveDays, Self.maximumHistoryDays)
        let now = Date()
        guard daysBack > Self.preloadDaysBack,
              let oldest = Calendar.current.date(byAdding: .day, value: -daysBack, to: now) else { return }
        await ensureDays(from: oldest, through: now, using: client)
    }

    private func applyCatchupInfo(_ info: [Int: (isCatchup: Bool, catchupDays: Int)]) {
        func apply(_ list: [Channel]) -> [Channel] {
            list.map { ch in
                guard let entry = info[ch.id] else { return ch }
                return ch.withCatchup(isCatchup: entry.isCatchup, catchupDays: entry.catchupDays)
            }
        }
        channels = apply(channels)
        visibleChannels = apply(visibleChannels)
        guideSidebarChannels = apply(guideSidebarChannels)
        channelMap = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    #else
    /// Loads NextPVR's channel groups and stamps membership onto the cached
    /// channels (#158).
    ///
    /// Discovery costs one request for the group list plus one per group, so it
    /// runs in the background after the grid has painted rather than delaying
    /// first paint; the sidebar, settings picker and filters pick the groups up
    /// reactively. Runs on every load *and* refresh so server-side group edits
    /// appear without restarting the app.
    private func enrichWithChannelGroups(using client: PVRClient) {
        Task { [weak self] in
            guard let self else { return }
            let catalog = (try? await client.getChannelGroupCatalog()) ?? .empty
            self.applyChannelGroups(catalog)
        }
    }

    /// Replaces the cached group metadata. An empty catalogue clears it, which
    /// is what a server with no (or no longer any) custom groups should show —
    /// the all-channel lists themselves are untouched.
    func applyChannelGroups(_ catalog: ChannelGroupCatalog) {
        channelGroups = catalog.groups
        func apply(_ list: [Channel]) -> [Channel] {
            list.map { $0.withGroupIds(catalog.membership[$0.id] ?? []) }
        }
        channels = apply(channels)
        visibleChannels = apply(visibleChannels)
        guideSidebarChannels = apply(guideSidebarChannels)
        channelMap = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    #endif

    /// Prefetch yesterday + tomorrow EPG in background
    func prefetchAdjacentDays(around date: Date, using client: PVRClient) async {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date

        async let _ = ensureDay(yesterday, using: client)
        async let _ = ensureDay(tomorrow, using: client)
    }

    // MARK: - Channel Filtering

    func channels(inProfile profileId: Int?) -> [Channel] {
        // When Dispatcharr channels were loaded through the summary endpoint
        // with a profile id, this should already be narrowed server-side.
        // Keep this as a screen-level fallback for cached/all-channel data.
        guard let profileId,
              let profile = channelProfiles.first(where: { $0.id == profileId }) else {
            return visibleChannels
        }
        let channelIds = Set(profile.channels)
        return visibleChannels.filter { channelIds.contains($0.id) }
    }

    func channels(inGroup groupId: Int?) -> [Channel] {
        guard let groupId else { return visibleChannels }
        return visibleChannels.filter { $0.isMember(ofGroup: groupId) }
    }

    /// Channel groups that hold at least one channel. Every group-picking
    /// surface (sidebar sub-rows, guide/channels filter panels and tvOS
    /// drawers, the settings picker) hides empty groups, since selecting one
    /// would leave the screen blank.
    ///
    /// Read from `guideSidebarChannels` rather than `visibleChannels` so a
    /// Dispatcharr profile reload, which narrows the visible list server-side,
    /// can't make groups disappear from the pickers.
    var populatedChannelGroups: [ChannelGroup] {
        Self.channelGroups(channelGroups, populatedIn: guideSidebarChannels)
    }

    /// True when at least one group holds a channel — the cheap check the
    /// filter affordances use to decide whether to show themselves.
    var hasPopulatedChannelGroups: Bool {
        channelGroups.contains { group in
            guideSidebarChannels.contains { $0.isMember(ofGroup: group.id) }
        }
    }

    /// Pure form of `populatedChannelGroups`.
    nonisolated static func channelGroups(
        _ groups: [ChannelGroup],
        populatedIn channels: [Channel]
    ) -> [ChannelGroup] {
        groups.filter { group in
            channels.contains { $0.isMember(ofGroup: group.id) }
        }
    }

    /// Non-empty channel groups whose name matches `search`, for the sidebar
    /// search dropdown. Empty groups are excluded — selecting one would show a
    /// blank guide — and an empty query matches nothing rather than everything.
    ///
    /// Matched against `guideSidebarChannels` rather than `visibleChannels` so
    /// a Dispatcharr profile reload, which narrows the visible list
    /// server-side, can't make groups disappear from search.
    func channelGroups(matching search: String) -> [ChannelGroup] {
        Self.channelGroups(channelGroups, matching: search, in: guideSidebarChannels)
    }

    /// Pure form of `channelGroups(matching:)`.
    nonisolated static func channelGroups(
        _ groups: [ChannelGroup],
        matching search: String,
        in channels: [Channel]
    ) -> [ChannelGroup] {
        guard !search.isEmpty else { return [] }
        let query = search.lowercased()
        return channelGroups(groups, populatedIn: channels)
            .filter { $0.name.lowercased().contains(query) }
    }

    func filteredChannels(matching search: String) -> [Channel] {
        guard !search.isEmpty else { return visibleChannels }
        let query = search.lowercased()
        return visibleChannels.filter { channel in
            channel.name.lowercased().contains(query) ||
            String(channel.number).contains(query)
        }
    }

    // MARK: - Programs Access

    /// Complete cached EPG for one channel. Callers that need an archive-wide
    /// view (rather than a single guide day) can filter this snapshot without
    /// repeatedly scanning the same channel data for every date.
    func allPrograms(for channelId: Int) -> [Program] {
        epg[channelId] ?? []
    }

    func programs(for channelId: Int, on date: Date) -> [Program] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = dayStart.addingTimeInterval(24 * 3600)

        guard let all = epg[channelId] else { return [] }
        return all.filter { $0.endDate > dayStart && $0.startDate < dayEnd }
    }

    /// Returns the program currently airing on the given channel at `date`.
    /// Returns nil when the channel has no EPG data or no program is airing.
    /// This is a public helper so views (e.g. Channels grid) can reuse the
    /// preloaded EPG data without exposing the underlying storage.
    func currentProgram(forChannelId channelId: Int, at date: Date = Date()) -> Program? {
        guard let all = epg[channelId] else { return nil }
        return all.first { program in
            program.startDate <= date && program.endDate > date
        }
    }

    /// Convenience helper that resolves a `Channel` to its current program.
    func currentProgram(for channel: Channel, at date: Date = Date()) -> Program? {
        currentProgram(forChannelId: channel.id, at: date)
    }

    // MARK: - Search

    func searchPrograms(query: String) async -> [SearchResult] {
        let start = CFAbsoluteTimeGetCurrent()
        let q = query.lowercased()
        let epg = self.epg
        let channelMap = self.channelMap

        let results = await Task.detached(priority: .userInitiated) {
            var matches: [SearchResult] = []

            for (channelId, programs) in epg {
                guard !Task.isCancelled else { return [SearchResult]() }
                guard let channel = channelMap[channelId] else { continue }

                for program in programs {
                    let text = [
                        program.name,
                        program.subtitle ?? "",
                        program.desc ?? ""
                    ].joined(separator: " ").lowercased()

                    if text.contains(q) {
                        matches.append(SearchResult(program: program, channel: channel))
                    }
                }
            }

            let now = Date()
            return matches.sorted { a, b in
                let aUpcoming = a.program.endDate > now
                let bUpcoming = b.program.endDate > now
                if aUpcoming != bUpcoming { return aUpcoming }
                return a.program.startDate < b.program.startDate
            }
        }.value
        print("[EPGCache] Search '\(query)': \(results.count) results in \(ms(since: start))ms")
        return results
    }

    func searchProgramsCount(query: String) async -> Int {
        let q = query.lowercased()
        let epg = self.epg

        return await Task.detached(priority: .userInitiated) {
            var count = 0
            for (_, programs) in epg {
                guard !Task.isCancelled else { return 0 }
                for program in programs {
                    let text = [
                        program.name,
                        program.subtitle ?? "",
                        program.desc ?? ""
                    ].joined(separator: " ").lowercased()
                    if text.contains(q) {
                        count += 1
                    }
                }
            }
            return count
        }.value
    }

    // MARK: - Topic Matching

    func matchingPrograms(
        keywords: [String],
        includesCatchup: Bool = false
    ) async -> [MatchingProgram] {
        let start = CFAbsoluteTimeGetCurrent()
        let epg = self.epg
        let channelMap = self.channelMap
        let lowercasedKeywords = keywords.map { $0.lowercased() }

        let results = await Task.detached(priority: .userInitiated) {
            var matches: [MatchingProgram] = []
            let now = Date()

            for (channelId, programs) in epg {
                guard !Task.isCancelled else { return [MatchingProgram]() }
                guard let channel = channelMap[channelId] else { continue }

                for program in programs {
                    let isUpcoming = program.endDate > now
                    let isCatchupAvailable = includesCatchup && CatchupAvailability.isAvailable(
                        program: program,
                        channelIsCatchup: channel.isCatchup,
                        catchupDays: channel.catchupDays,
                        now: now
                    )
                    guard isUpcoming || isCatchupAvailable else { continue }

                    let searchText = [
                        program.name,
                        program.subtitle ?? "",
                        program.desc ?? ""
                    ].joined(separator: " ").lowercased()

                    for (i, keyword) in lowercasedKeywords.enumerated() {
                        if searchText.contains(keyword) {
                            matches.append(MatchingProgram(
                                program: program,
                                channel: channel,
                                matchedKeyword: keywords[i]
                            ))
                            break
                        }
                    }
                }
            }

            return matches.sorted { $0.program.startDate < $1.program.startDate }
        }.value
        print("[EPGCache] Topics (\(keywords.count) keywords): \(results.count) matches in \(ms(since: start))ms")
        return results
    }

    // MARK: - Invalidation

    func invalidate() {
        loadGeneration &+= 1
        backgroundLoadTask?.cancel()
        backgroundLoadTask = nil
        channels = []
        visibleChannels = []
        guideSidebarChannels = []
        channelProfiles = []
        channelGroups = []
        channelMap = [:]
        replaceEPG(with: [:])
        loadedProfileId = nil
        isLoading = false
        hasLoaded = false
        isFullyLoaded = false
        isLoadInProgress = false
        error = nil
        lastRefreshDate = nil
    }

    /// Whether returning to the foreground should call `refresh` — the one
    /// check the Guide and Channels pages share (#166).
    func shouldRefreshOnActivation(using client: PVRClient, now: Date = Date()) -> Bool {
        EPGActivationRefreshPolicy.shouldRefresh(
            isConfigured: client.isConfigured,
            hasLoaded: hasLoaded,
            isLoading: isLoading,
            isRefreshing: isRefreshing,
            hasActiveLiveStream: client.hasActiveLiveStream,
            lastRefreshDate: lastRefreshDate,
            now: now
        )
    }

    // MARK: - Date Bounds

    nonisolated static func earliestProgramDate(in listings: [Int: [Program]]) -> Date? {
        var earliest: Date?
        for programs in listings.values {
            for program in programs {
                if earliest.map({ program.startDate < $0 }) ?? true {
                    earliest = program.startDate
                }
            }
        }
        return earliest
    }

    // MARK: - Merging

    /// `listings` added to `epg`, skipping programs already there by id — a
    /// program spanning midnight comes back with both of its days — and
    /// keeping each channel sorted by start.
    nonisolated static func merging(_ listings: [Int: [Program]], into epg: [Int: [Program]]) -> [Int: [Program]] {
        var merged = epg
        for (channelId, programs) in listings where !programs.isEmpty {
            var combined = merged[channelId] ?? []
            var seen = Set(combined.map(\.id))
            for program in programs where seen.insert(program.id).inserted {
                combined.append(program)
            }
            combined.sort { $0.start < $1.start }
            merged[channelId] = combined
        }
        return merged
    }

    private func merge(_ listings: [Int: [Program]]) {
        epg = Self.merging(listings, into: epg)
        if let earliest = Self.earliestProgramDate(in: listings),
           earliestEPGDate.map({ earliest < $0 }) ?? true {
            earliestEPGDate = earliest
        }
    }

    /// Swaps the whole EPG for `listings`, forgetting which days were loaded
    /// and disowning any day request still in flight.
    private func replaceEPG(with listings: [Int: [Program]]) {
        epgEpoch &+= 1
        for task in dayLoads.values { task.cancel() }
        dayLoads = [:]
        epg = listings
        earliestEPGDate = Self.earliestProgramDate(in: listings)
        loadedDays = []
        hasCompleteEPG = false
    }

    // MARK: - Private

    private func markLoadedDays(from listings: [Int: [Program]]) {
        for programs in listings.values {
            for program in programs {
                let key = Self.dayFormatter.string(from: program.startDate)
                loadedDays.insert(key)
            }
        }
    }

    private func ms(since start: CFAbsoluteTime) -> String {
        String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}
