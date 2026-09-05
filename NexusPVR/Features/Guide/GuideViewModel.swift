//
//  GuideViewModel.swift
//  nextpvr-apple-client
//
//  View model for the TV guide/EPG
//

import SwiftUI
import Combine

@MainActor
final class GuideViewModel: ObservableObject {
    @Published var recordings: [Recording] = [] {
        didSet {
            recordingsByEventId = Dictionary(
                recordings.compactMap { r in r.epgEventId.map { ($0, r) } },
                uniquingKeysWith: { first, _ in first }
            )
            // Secondary lookup by name + start time for Dispatcharr where epgEventId may not match
            recordingsByNameAndStart = Dictionary(
                recordings.compactMap { r in
                    r.startTime.map { ("\(r.name.lowercased())_\($0)", r) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var error: String?

    @Published var selectedDate = Date()

    /// Whether the date navigator can go earlier than today. Off by
    /// default — NextPVR has no server-side program archive, so browsing
    /// history there would only ever show dead air. Dispatcharr's catch-up
    /// feature (#119) is the reason to allow it.
    #if DISPATCHERPVR
    var allowsPastDates = true
    #else
    var allowsPastDates = false
    #endif

    @Published var showChannelSearch: Bool = false
    @Published var channelSearchText: String = ""
    @Published var selectedProfileId: Int? = nil
    @Published var selectedGroupId: Int? = nil
    @Published var showFilters: Bool = false

    // O(1) lookup for recording status by program ID
    private var recordingsByEventId: [Int: Recording] = [:]
    // Fallback lookup by name + start time
    private var recordingsByNameAndStart: [String: Recording] = [:]

    // Cached sport detection results (avoids re-running regex per render)
    private var sportCache: [Int: Sport?] = [:]

    // Cached per-channel programs for the selected day (#141)
    private var programsCache: [Int: [Program]] = [:]
    private var programsCacheDayStart: Date?
    private var programsCacheGeneration: Int?

    // Cached catch-up availability per program (#141) — the underlying check
    // walks the calendar, and the guide asked it once per cell per pass.
    private var catchupAvailabilityCache: [Int: Bool] = [:]
    private var catchupAvailabilityBucket: Int?

    // Keyword-matched program IDs (O(1) lookup per cell)
    @Published private(set) var keywordMatchedProgramIds: Set<Int> = []

    // Reference to EPGCache (set during loadData)
    weak var epgCache: EPGCache?

    /// Memoized timeline geometry (#141).
    ///
    /// `timelineStart` / `hoursToShow` / `hourSlotCount` are read once per
    /// program cell during a guide pass, and each recomputation walked the
    /// calendar 24 times. They only actually change when the selected day, the
    /// past-dates flag, or the current half-hour changes — so they are
    /// computed once per those inputs and served from here afterwards.
    /// Validity is checked with plain `Date` comparisons and one integer
    /// division, no calendar arithmetic.
    private struct TimelineGeometry {
        let dayStart: Date
        let dayEnd: Date
        let allowsPastDates: Bool
        let halfHourBucket: Int
        let start: Date
        let hours: [Date]

        func isValid(for date: Date, allowsPastDates: Bool, bucket: Int) -> Bool {
            self.allowsPastDates == allowsPastDates
                && self.halfHourBucket == bucket
                && date >= dayStart
                && date < dayEnd
        }
    }

    private var timelineGeometry: TimelineGeometry?
    private var cachedScrollTarget: Date?
    private var cachedScrollTargetBucket: Int?

    private static func halfHourBucket(for now: Date) -> Int {
        Int(now.timeIntervalSince1970 / 1800)
    }

    private func geometry(now: Date = Date()) -> TimelineGeometry {
        let bucket = Self.halfHourBucket(for: now)
        if let cached = timelineGeometry,
           cached.isValid(for: selectedDate, allowsPastDates: allowsPastDates, bucket: bucket) {
            return cached
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)

        let start: Date
        if isToday && !allowsPastDates {
            // Start from current half-hour (round down to :00 or :30)
            let minute = calendar.component(.minute, from: now)
            let roundedMinute = minute >= 30 ? 30 : 0
            start = calendar.date(bySettingHour: calendar.component(.hour, from: now),
                                  minute: roundedMinute, second: 0, of: now) ?? now
        } else {
            start = dayStart
        }

        let count = Self.hourCount(for: selectedDate, now: now, includesPastHours: allowsPastDates)
        var hours: [Date] = []
        hours.reserveCapacity(count)
        var current = start
        for _ in 0..<count {
            hours.append(current)
            current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current
        }

        let geometry = TimelineGeometry(
            dayStart: dayStart,
            dayEnd: dayEnd,
            allowsPastDates: allowsPastDates,
            halfHourBucket: bucket,
            start: start,
            hours: hours
        )
        timelineGeometry = geometry
        return geometry
    }

    var timelineStart: Date {
        geometry().start
    }

    /// Number of hour slots in the rendered timeline, without rebuilding the
    /// hour array to count it.
    var hourSlotCount: Int {
        geometry().hours.count
    }

    var hasActiveFilters: Bool {
        selectedProfileId != nil || selectedGroupId != nil
    }

    /// Channels to display in the guide (reads from EPGCache, filtered by profile, group, and search)
    /// Uses visibleChannels which starts with first 20, expands to all after EPG loads
    /// Profile takes precedence over group — when a profile is selected, the group filter is ignored.
    var channels: [Channel] {
        guard let cache = epgCache else { return [] }
        var result: [Channel]
        if let profileId = selectedProfileId {
            result = cache.channels(inProfile: profileId)
        } else {
            result = cache.channels(inProfile: nil)
            if let groupId = selectedGroupId {
                result = result.filter { $0.isMember(ofGroup: groupId) }
            }
        }
        if !channelSearchText.isEmpty {
            let query = channelSearchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) || String($0.number).contains(query) }
        }
        return result
    }

    /// Returns the number of hour slots to display for a given selected date.
    /// Catch-up builds keep all of today in the timeline so viewers can scroll
    /// backward; other builds retain the smaller future-only window.
    /// Accepts an explicit `now` for testability.
    static func hourCount(
        for selectedDate: Date,
        now: Date = Date(),
        includesPastHours: Bool = false
    ) -> Int {
        let calendar = Calendar.current
        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)
        if isToday && includesPastHours { return 24 }
        let remainingHours = isToday ? (24 - calendar.component(.hour, from: now)) : 24
        let startsAtHalfHour = isToday && calendar.component(.minute, from: now) >= 30
        return max(remainingHours + (startsAtHalfHour ? 1 : 0), 6)
    }

    var hoursToShow: [Date] {
        geometry().hours
    }

    /// The half-hour the guide scrolls to and aligns live cell text against,
    /// memoized per half-hour bucket (#141) — it was recomputed per row.
    var scrollTargetTime: Date {
        let bucket = Self.halfHourBucket(for: Date())
        if let cached = cachedScrollTarget, cachedScrollTargetBucket == bucket {
            return cached
        }
        let target = GuideScrollHelper.calculateScrollTarget(currentTime: Date())
        cachedScrollTarget = target
        cachedScrollTargetBucket = bucket
        return target
    }

    #if DISPATCHERPVR
    /// Whether `program` can be played back via catch-up, memoized per program
    /// for the current half-hour (#141). The window slides with `now`, so the
    /// cache is dropped whenever the half-hour bucket changes.
    func isCatchupAvailable(_ program: Program, on channel: Channel) -> Bool {
        let bucket = Self.halfHourBucket(for: Date())
        if catchupAvailabilityBucket != bucket {
            catchupAvailabilityCache = [:]
            catchupAvailabilityBucket = bucket
        }
        if let cached = catchupAvailabilityCache[program.id] { return cached }
        let available = CatchupAvailability.isAvailable(
            program: program,
            channelIsCatchup: channel.isCatchup,
            catchupDays: channel.catchupDays
        )
        catchupAvailabilityCache[program.id] = available
        return available
    }
    #endif

    /// Returns cached sport detection result for a program
    func detectedSport(for program: Program) -> Sport? {
        if let cached = sportCache[program.id] {
            return cached
        }
        let sport = SportDetector.detect(from: program)
        sportCache[program.id] = sport
        return sport
    }

    /// Compute keyword matches for programs of a specific channel
    func updateKeywordMatches(keywords: [String]) {
        guard !keywords.isEmpty, let cache = epgCache else {
            keywordMatchedProgramIds = []
            return
        }
        let lowercasedKeywords = keywords.map { $0.lowercased() }
        var matched = Set<Int>()
        for channel in channels {
            for program in cache.programs(for: channel.id, on: selectedDate) {
                let searchText = [
                    program.name,
                    program.subtitle ?? "",
                    program.desc ?? ""
                ].joined(separator: " ").lowercased()
                if lowercasedKeywords.contains(where: { searchText.contains($0) }) {
                    matched.insert(program.id)
                }
            }
        }
        keywordMatchedProgramIds = matched
    }

    func loadData(using client: PVRClient, epgCache: EPGCache) async {
        self.epgCache = epgCache

        guard client.isConfigured else { return }

        isLoading = true
        error = nil
        sportCache = [:]

        // Wait for EPGCache channels to be ready (may already be loaded by ContentView)
        while !epgCache.hasLoaded && epgCache.error == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }

        if let cacheError = epgCache.error {
            self.error = cacheError
            isLoading = false
            hasLoaded = true
            return
        }

        showChannelSearch = epgCache.channels.count > 25

        do {
            // Load recordings
            let recordingsStart = CFAbsoluteTimeGetCurrent()
            let (completed, recording, scheduled) = try await client.getAllRecordings()
            recordings = completed + recording + scheduled
            print("[Guide] Loaded \(recordings.count) recordings in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - recordingsStart) * 1000))ms")

            isLoading = false
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            hasLoaded = true
        }
    }

    /// User-initiated refresh of the guide: re-fetch channels + EPG from the
    /// server (so channels added server-side appear) and reload recordings.
    /// The grid keeps showing the current data while this runs.
    func refresh(using client: PVRClient) async {
        guard let cache = epgCache, client.isConfigured else { return }
        sportCache = [:]
        await cache.refresh(using: client, profileId: selectedProfileId)
        showChannelSearch = cache.channels.count > 25
        error = cache.error
        await reloadRecordings(client: client)
    }

    /// Handle date navigation — ensure EPG data is cached for the new date
    func navigateToDate(using client: PVRClient) async {
        guard let cache = epgCache else { return }
        sportCache = [:]
        await cache.ensureDay(selectedDate, using: client)
        // Prefetch adjacent days in background
        Task {
            await cache.prefetchAdjacentDays(around: selectedDate, using: client)
        }
    }

    func programs(for channel: Channel) -> [Program] {
        epgCache?.epg[channel.id] ?? []
    }

    /// Lazily look up programs for a channel on the selected date from the cache.
    /// On today, only discard programs before the actual timeline start. That
    /// preserves earlier programs when catch-up expands today's timeline to
    /// midnight, while keeping the existing future-only behavior elsewhere.
    func visiblePrograms(for channel: Channel) -> [Program] {
        let programs = programsOnSelectedDate(for: channel)
        if isOnToday {
            // Show any program that overlaps the visible timeline (ends after timeline start)
            let start = timelineStart
            return programs.filter { $0.endDate > start }
        }
        return programs
    }

    /// The selected day's programs for a channel, memoized (#141).
    ///
    /// `EPGCache.programs(for:on:)` scans the channel's whole multi-day array
    /// and does calendar work to bound the day; the guide asked for it once per
    /// row per pass. The cache is keyed on the selected day plus the cache's
    /// `epgGeneration`, so a background merge or a refresh drops it.
    private func programsOnSelectedDate(for channel: Channel) -> [Program] {
        guard let cache = epgCache else { return [] }
        let geometry = geometry()
        let generation = cache.epgGeneration

        if programsCacheDayStart != geometry.dayStart || programsCacheGeneration != generation {
            programsCache = [:]
            programsCacheDayStart = geometry.dayStart
            programsCacheGeneration = generation
        }

        if let cached = programsCache[channel.id] { return cached }
        let programs = cache.programs(for: channel.id, on: selectedDate)
        programsCache[channel.id] = programs
        return programs
    }

    func programWidth(for program: Program, hourWidth: CGFloat, startTime: Date) -> CGFloat {
        let visibleStart = max(program.startDate, startTime)
        let timelineEnd = startTime.addingTimeInterval(Double(hourSlotCount) * 3600)
        let visibleEnd = min(program.endDate, timelineEnd)
        let duration = visibleEnd.timeIntervalSince(visibleStart)
        return max(CGFloat(duration / 3600) * hourWidth, 50)
    }

    func programOffset(for program: Program, hourWidth: CGFloat, startTime: Date) -> CGFloat {
        let visibleStart = max(program.startDate, startTime)
        let offset = visibleStart.timeIntervalSince(startTime)
        return CGFloat(offset / 3600) * hourWidth
    }

    var isOnToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Earliest day the guide can display. Dispatcharr may browse history,
    /// but never before the oldest program actually present in EPGCache.
    /// A nil cache preserves the standalone ViewModel behavior used by tests.
    private var minimumNavigableDate: Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard allowsPastDates else { return today }
        guard let epgCache else { return nil }
        guard let earliestEPGDate = epgCache.earliestEPGDate else { return today }
        return min(today, calendar.startOfDay(for: earliestEPGDate))
    }

    /// Whether the previous-day control would remain inside the cached EPG.
    var canGoToPreviousDay: Bool {
        guard let minimumNavigableDate else { return true }
        return Calendar.current.startOfDay(for: selectedDate) > minimumNavigableDate
    }

    func scrollToNow() {
        selectedDate = Date()
    }

    func previousDay() {
        guard canGoToPreviousDay else { return }
        let previousDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        if let minimumNavigableDate {
            selectedDate = max(previousDate, minimumNavigableDate)
        } else {
            selectedDate = previousDate
        }
    }

    func clampSelectedDateToAvailableEPG() {
        guard let minimumNavigableDate,
              Calendar.current.startOfDay(for: selectedDate) < minimumNavigableDate else { return }
        selectedDate = minimumNavigableDate
    }

    func nextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
    }

    private func findRecording(for program: Program) -> Recording? {
        recordingsByEventId[program.id]
            ?? recordingsByNameAndStart["\(program.name.lowercased())_\(program.start)"]
    }

    func isScheduledRecording(_ program: Program) -> Bool {
        findRecording(for: program) != nil
    }

    func recordingStatus(_ program: Program) -> RecordingStatus? {
        findRecording(for: program)?.recordingStatus
    }

    func recordingId(for program: Program) -> Int? {
        if let id = findRecording(for: program)?.id {
            return id
        }
        guard let channelId = program.channelId else { return nil }
        return findOverlappingRecording(channelId: channelId, programStart: program.startDate, programEnd: program.endDate)?.id
    }

    func activeRecordingId(for program: Program, channelId: Int) -> Int? {
        if let id = findRecording(for: program)?.id {
            return id
        }
        return findOverlappingRecording(channelId: channelId, programStart: program.startDate, programEnd: program.endDate)?.id
    }

    private func findOverlappingRecording(channelId: Int, programStart: Date, programEnd: Date) -> Recording? {
        for r in recordings {
            guard r.channelId == channelId else { continue }
            guard r.recordingStatus == .recording else { continue }
            guard let rStart = r.startDate, let rEnd = r.endDate else { continue }
            if rStart < programEnd && rEnd > programStart {
                return r
            }
        }
        return nil
    }

    func reloadRecordings(client: PVRClient) async {
        do {
            let (completed, recording, scheduled) = try await client.getAllRecordings()
            recordings = completed + recording + scheduled
        } catch {
            // Silently fail - recordings indicator will update on next full reload
        }
    }
}
