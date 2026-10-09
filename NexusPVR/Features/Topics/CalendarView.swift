//
//  CalendarView.swift
//  NexusPVR
//
//  Calendar view for topic programs schedule
//

import SwiftUI

#if !os(tvOS)

// MARK: - Constants

// Tall hours, so a 15-minute program still gets a readable line.
private let hourHeight: CGFloat = 80
/// Shortest a block is drawn, unless the next program leaves less room.
private let minimumBlockHeight: CGFloat = 20
private let timeColumnWidth: CGFloat = 50
private let startHour = 0
private let endHour = 24

// Light pastel colors for topic keywords — deterministic by keyword hash
private let topicColors: [Color] = [
    Color(red: 0.40, green: 0.73, blue: 0.88),  // sky blue
    Color(red: 0.56, green: 0.83, blue: 0.56),  // light green
    Color(red: 0.91, green: 0.58, blue: 0.48),  // salmon
    Color(red: 0.73, green: 0.58, blue: 0.88),  // lavender
    Color(red: 0.95, green: 0.75, blue: 0.40),  // golden
    Color(red: 0.48, green: 0.82, blue: 0.75),  // teal
    Color(red: 0.88, green: 0.52, blue: 0.72),  // pink
    Color(red: 0.65, green: 0.78, blue: 0.45),  // lime
    Color(red: 0.55, green: 0.68, blue: 0.90),  // periwinkle
    Color(red: 0.90, green: 0.68, blue: 0.50),  // peach
]

private func colorForKeyword(_ keyword: String) -> Color {
    var hash: UInt64 = 5381
    for char in keyword.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(char)
    }
    return topicColors[Int(hash % UInt64(topicColors.count))]
}

// MARK: - CalendarView

struct CalendarView: View {
    let programs: [MatchingProgram]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var epgCache: EPGCache
    @State private var viewMode: ViewMode = .day
    @State private var selectedProgramDetail: ProgramTopicDetail?
    @State private var selectedKeyword: String = ""
    @State private var contentWidth: CGFloat = 0
    @State private var scheduledProgramIds: Set<Int> = []
    @State private var catchupAwareTopicPrograms: [MatchingProgram]?

    enum ViewMode: String, CaseIterable {
        case day = "Day"
        case week = "Week"
    }

    private var selectedDate: Date {
        get { appState.calendarSelectedDate }
        nonmutating set { appState.calendarSelectedDate = newValue }
    }

    private var keywords: [String] {
        Array(Set(calendarPrograms.map(\.matchedKeyword))).sorted()
    }

    private var calendarPrograms: [MatchingProgram] {
        #if DISPATCHERPVR
        let topicPrograms = catchupAwareTopicPrograms
            ?? programs.filter { $0.matchedKeyword != MatchingProgram.scheduledKeyword }
        let scheduledPrograms = programs.filter {
            $0.matchedKeyword == MatchingProgram.scheduledKeyword
        }
        return topicPrograms + scheduledPrograms
        #else
        return programs
        #endif
    }

    private var filteredPrograms: [MatchingProgram] {
        if selectedKeyword == MatchingProgram.scheduledKeyword {
            // Show all scheduled recordings
            return calendarPrograms.filter { $0.matchedKeyword == MatchingProgram.scheduledKeyword }
        } else if !selectedKeyword.isEmpty {
            // Show only the selected topic keyword
            return calendarPrograms.filter { $0.matchedKeyword == selectedKeyword }
        }
        // "All": deduplicate — if a program has both a topic and "Scheduled" entry, keep the topic one
        let scheduledIds = Set(
            calendarPrograms.filter { $0.matchedKeyword == MatchingProgram.scheduledKeyword }.map { $0.program.id }
        )
        let topicIds = Set(
            calendarPrograms.filter { $0.matchedKeyword != MatchingProgram.scheduledKeyword }.map { $0.program.id }
        )
        let duplicateIds = scheduledIds.intersection(topicIds)
        return calendarPrograms.filter {
            !($0.matchedKeyword == MatchingProgram.scheduledKeyword && duplicateIds.contains($0.program.id))
        }
    }

    private var programsByDate: [Date: [MatchingProgram]] {
        Dictionary(grouping: filteredPrograms) { item in
            Calendar.current.startOfDay(for: item.program.startDate)
        }
    }

    private var visibleDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: selectedDate)

        switch viewMode {
        case .day:
            return [today]
        case .week:
            let weekday = cal.component(.weekday, from: today)
            let diff = weekday - cal.firstWeekday
            let startOfWeek = cal.date(byAdding: .day, value: -(diff < 0 ? diff + 7 : diff), to: today) ?? today
            return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startOfWeek) }
        }
    }

    private var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE dd"
        switch viewMode {
        case .day:
            return formatter.string(from: selectedDate)
        case .week:
            let dates = visibleDates
            guard let first = dates.first, let last = dates.last else { return "" }
            let monthDay = DateFormatter()
            monthDay.dateFormat = "MMM dd"
            let dd = DateFormatter()
            dd.dateFormat = "dd"
            return "\(monthDay.string(from: first))-\(dd.string(from: last))"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if !os(iOS)
                navigationBar
                #endif

                switch viewMode {
                case .day:
                    dayView
                case .week:
                    weekView
                }
            }
            .accessibilityIdentifier("calendar-view")
            .frame(maxHeight: .infinity)
            .background(MidnightGradients.ground(colorScheme))
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.size.width
            } action: { newWidth in
                contentWidth = newWidth
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MidnightPalette.railHead, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sidebarMenuToolbar()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Button { navigateBack() } label: {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                        }
                        .disabled(!canNavigateBack)

                        Text(dateRangeLabel)
                            .font(.archivo(15, .extraBold))
                            .textCase(.uppercase)
                            .foregroundStyle(MidnightPalette.ink)
                            .lineLimit(1)

                        Button { navigateForward() } label: {
                            Image(systemName: "chevron.right")
                                .fontWeight(.semibold)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { selectedKeyword = "" } label: {
                            if selectedKeyword.isEmpty {
                                Label("All", systemImage: "checkmark")
                            } else {
                                Text("All")
                            }
                        }
                        ForEach(keywords, id: \.self) { keyword in
                            Button {
                                selectedKeyword = keyword
                            } label: {
                                Label(keyword, systemImage: keyword == selectedKeyword ? "checkmark.circle.fill" : "circle.fill")
                            }
                            .tint(colorForKeyword(keyword))
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if !selectedKeyword.isEmpty {
                                Circle()
                                    .fill(colorForKeyword(selectedKeyword))
                                    .frame(width: 8, height: 8)
                            }
                            Text(selectedKeyword.isEmpty ? "All" : selectedKeyword)
                                .font(.caption)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.tvScaled(size: 10))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            #endif
            .programDetailPopover(item: $selectedProgramDetail, onDismiss: {
                Task { await loadScheduledRecordings() }
            }) { detail in
                ProgramDetailView(
                    program: detail.program,
                    channel: detail.channel,
                    initialRecordingId: detail.recordingId,
                    initialCompletedRecording: detail.completedRecording
                )
                .environmentObject(client)
                .environmentObject(appState)
            }
        }
        .task {
            await loadScheduledRecordings()
        }
        #if DISPATCHERPVR
        .task(id: catchupLoadIdentifier) {
            await loadCatchupPrograms()
        }
        #endif
    }

    private func loadScheduledRecordings() async {
        do {
            let (_, recording, scheduled) = try await client.getAllRecordings()
            let ids = Set((recording + scheduled).compactMap(\.epgEventId))
            scheduledProgramIds = ids
        } catch {
            // Silently fail
        }
    }

    #if DISPATCHERPVR
    private var maximumCatchupDays: Int {
        epgCache.channels
            .filter(\.isCatchup)
            .map(\.catchupDays)
            .filter { $0 > 0 }
            .max() ?? 0
    }

    private var catchupLoadIdentifier: String {
        let earliestTimestamp = epgCache.earliestEPGDate?.timeIntervalSince1970 ?? 0
        return "\(maximumCatchupDays)-\(earliestTimestamp)"
    }

    /// Reloads the topic matches with archived programs included. Waiting for
    /// the oldest relevant day also joins any full-EPG load already running,
    /// so past calendar pages do not briefly appear empty.
    private func loadCatchupPrograms() async {
        let now = Date()
        if maximumCatchupDays > 0,
           let oldestArchiveDate = Calendar.current.date(
               byAdding: .day,
               value: -maximumCatchupDays,
               to: now
           ) {
            await epgCache.ensureDays(from: oldestArchiveDate, through: now, using: client)
        }

        guard !Task.isCancelled else { return }
        if Calendar.current.startOfDay(for: selectedDate) < earliestNavigableDate {
            selectedDate = earliestNavigableDate
        }
        catchupAwareTopicPrograms = await epgCache.matchingPrograms(
            keywords: UserPreferences.load().keywords,
            includesCatchup: true
        )
    }
    #endif

    // MARK: - Navigation Bar

    #if os(macOS)
    private var navigationBar: some View {
        MacCalendarHeader(
            title: macRangeTitle,
            canGoBack: canNavigateBack,
            viewMode: $viewMode,
            selectedKeyword: $selectedKeyword,
            keywordOptions: [("All topics", "")] + keywords.map { ($0, $0) },
            onBack: navigateBack,
            onForward: navigateForward,
            onToday: { selectedDate = Date() }
        )
    }

    /// "Thu, Oct 8" for a day; "Oct 4 – 10" (or "Sep 28 – Oct 4") for a week.
    private var macRangeTitle: String {
        let day = DateFormatter()
        switch viewMode {
        case .day:
            day.setLocalizedDateFormatFromTemplate("EEEMMMd")
            return day.string(from: selectedDate)
        case .week:
            guard let first = visibleDates.first, let last = visibleDates.last else { return "" }
            day.setLocalizedDateFormatFromTemplate("MMMd")
            let cal = Calendar.current
            if cal.isDate(first, equalTo: last, toGranularity: .month) {
                let dayOnly = DateFormatter()
                dayOnly.setLocalizedDateFormatFromTemplate("d")
                return "\(day.string(from: first)) – \(dayOnly.string(from: last))"
            }
            return "\(day.string(from: first)) – \(day.string(from: last))"
        }
    }
    #endif

    /// The accent now-line across a day column, while that day is today.
    @ViewBuilder
    private func nowLine(xOffset: CGFloat, width: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            let cal = Calendar.current
            let minutes = CGFloat(cal.component(.hour, from: context.date) * 60 + cal.component(.minute, from: context.date))
            Rectangle()
                .fill(MidnightPalette.accent)
                .frame(width: max(width, 0), height: 2)
                .offset(x: xOffset, y: minutes / 60 * hourHeight - 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Day View

    private var dayView: some View {
        let cal = Calendar.current
        let date = cal.startOfDay(for: selectedDate)
        let dayPrograms = programsByDate[date] ?? []
        let availableWidth = contentWidth - timeColumnWidth - Theme.spacingSM
        let columns = layoutColumns(for: dayPrograms)

        let scrollTarget: Int = {
            if cal.isDateInToday(selectedDate) {
                return max(0, cal.component(.hour, from: Date()) - 1)
            }
            if let first = dayPrograms.min(by: { $0.program.startDate < $1.program.startDate }) {
                return max(0, cal.component(.hour, from: first.program.startDate) - 1)
            }
            return 0
        }()

        return ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // VStack grid for real layout positions (scroll targets)
                    timelineVStack

                    // Program blocks overlaid
                    if availableWidth > 0 {
                        ForEach(dayPrograms) { item in
                            let layout = columns[item.id]
                            programBlock(item, columnOffset: timeColumnWidth, columnWidth: availableWidth, slot: layout)
                        }
                        if cal.isDateInToday(selectedDate) {
                            nowLine(xOffset: timeColumnWidth, width: availableWidth)
                        }
                    }
                }
                .padding(.trailing, Theme.spacingSM)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
            .onChange(of: selectedDate) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
        }
    }

    // MARK: - Week View

    private var weekView: some View {
        let dates = visibleDates
        let cal = Calendar.current
        let dayFormatter = DateFormatter()
        let totalHeight = CGFloat(endHour - startHour) * hourHeight
        let columnWidth = contentWidth > 0 ? (contentWidth - timeColumnWidth) / CGFloat(dates.count) : 0
        let weekPrograms = dates.flatMap {
            programsByDate[cal.startOfDay(for: $0)] ?? []
        }
        let scrollTarget: Int = {
            if dates.contains(where: { cal.isDateInToday($0) }) {
                return max(0, cal.component(.hour, from: Date()) - 1)
            }
            if let first = weekPrograms.min(by: { $0.program.startDate < $1.program.startDate }) {
                return max(0, cal.component(.hour, from: first.program.startDate) - 1)
            }
            return 0
        }()

        return VStack(spacing: 0) {
            // Day headers
            HStack(spacing: 0) {
                Color.clear.frame(width: timeColumnWidth, height: 1)
                ForEach(dates, id: \.self) { date in
                    let isToday = cal.isDateInToday(date)
                    VStack(spacing: 1) {
                        Text({
                            dayFormatter.dateFormat = "EEE"
                            return dayFormatter.string(from: date)
                        }())
                            .midnightKicker(9.5)
                            .foregroundStyle(isToday ? MidnightPalette.accent : MidnightPalette.inkSoft)
                        Text("\(cal.component(.day, from: date))")
                            .font(.archivo(18, .extraBold))
                            .foregroundStyle(isToday ? MidnightPalette.accent : MidnightPalette.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        if isToday {
                            Rectangle().fill(MidnightPalette.accent).frame(height: 2)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(MidnightPalette.railHead)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MidnightPalette.line).frame(height: 1)
            }


            // Timeline
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // VStack grid for real layout positions (scroll targets)
                        timelineVStack

                        if columnWidth > 0 {
                            // Vertical column dividers
                            ForEach(0..<dates.count, id: \.self) { index in
                                Rectangle()
                                    .fill(MidnightPalette.lineSoft)
                                    .frame(width: 1)
                                    .offset(x: timeColumnWidth + columnWidth * CGFloat(index))
                            }

                            // Program blocks per day
                            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                                let dayPrograms = programsByDate[Calendar.current.startOfDay(for: date)] ?? []
                                let xOffset = timeColumnWidth + columnWidth * CGFloat(index)
                                let columns = layoutColumns(for: dayPrograms)

                                ForEach(dayPrograms) { item in
                                    let layout = columns[item.id]
                                    programBlock(item, columnOffset: xOffset + 1, columnWidth: columnWidth - 2, slot: layout)
                                }
                            }
                            if let todayIndex = dates.firstIndex(where: { cal.isDateInToday($0) }) {
                                nowLine(xOffset: timeColumnWidth + columnWidth * CGFloat(todayIndex), width: columnWidth)
                            }
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        proxy.scrollTo(scrollTarget, anchor: .top)
                    }
                }
                .onChange(of: selectedDate) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        proxy.scrollTo(scrollTarget, anchor: .top)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Timeline Grid

    /// VStack-based timeline — each hour row has real layout height so ScrollViewReader can find it
    private var timelineVStack: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                // The rule sits exactly on the hour, where the blocks are
                // positioned; the label is centred on it.
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(MidnightPalette.lineSoft)
                        .frame(height: 1)
                        .padding(.leading, timeColumnWidth + 4)
                    Text(hourLabel(hour))
                        .midnightMeta(10)
                        .foregroundStyle(MidnightPalette.inkSoft)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                        .offset(y: hour == startHour ? 0 : -6)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    // MARK: - Overlap Layout

    /// Column and height for each of a day's program blocks (see
    /// `CalendarBlockLayout`).
    private func layoutColumns(for programs: [MatchingProgram]) -> [String: CalendarBlockLayout.Slot] {
        CalendarBlockLayout.layout(
            programs.map { .init(id: $0.id, start: $0.program.startDate, end: $0.program.endDate) },
            hourHeight: hourHeight,
            minHeight: minimumBlockHeight
        )
    }

    // MARK: - Program Block

    private func programBlock(_ item: MatchingProgram, columnOffset: CGFloat, columnWidth: CGFloat?, slot: CalendarBlockLayout.Slot?) -> some View {
        let colIndex = slot?.column ?? 0
        let totalCols = slot?.totalColumns ?? 1
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: item.program.startDate)
        let startMinutes = cal.dateComponents([.hour, .minute], from: dayStart, to: item.program.startDate)
        let totalStartMinutes = CGFloat((startMinutes.hour ?? 0) * 60 + (startMinutes.minute ?? 0))
        let durationMinutes = CGFloat(item.program.durationMinutes)
        let yOffset = (totalStartMinutes / 60.0) * hourHeight
        let blockHeight = slot?.height ?? max((durationMinutes / 60.0) * hourHeight, minimumBlockHeight)
        #if DISPATCHERPVR
        let catchupAvailable = CatchupAvailability.isAvailable(
            program: item.program,
            channelIsCatchup: item.channel.isCatchup,
            catchupDays: item.channel.catchupDays
        )
        #else
        let catchupAvailable = false
        #endif

        return Button {
            selectedProgramDetail = ProgramTopicDetail(
                program: item.program,
                channel: item.channel
            )
        } label: {
            CalendarBlock(
                program: item.program,
                channel: item.channel,
                topicColor: colorForKeyword(item.matchedKeyword),
                height: blockHeight,
                isScheduled: scheduledProgramIds.contains(item.program.id),
                isCatchupAvailable: catchupAvailable
            )
            .padding(.horizontal, 1)
        }
        .buttonStyle(.plain)
        .offset(x: {
            if let w = columnWidth {
                let colWidth = w / CGFloat(totalCols)
                return columnOffset + colWidth * CGFloat(colIndex)
            }
            return columnOffset
        }(), y: yOffset)
        .frame(width: {
            if let w = columnWidth {
                return w / CGFloat(totalCols)
            }
            return nil
        }())
    }

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let cal = Calendar.current
        let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }

    private var canNavigateBack: Bool {
        let cal = Calendar.current
        switch viewMode {
        case .day:
            return cal.startOfDay(for: selectedDate) > earliestNavigableDate
        case .week:
            return visibleDates.first.map {
                cal.startOfDay(for: $0) > earliestNavigableWeekStart
            } ?? false
        }
    }

    private var earliestNavigableDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        #if DISPATCHERPVR
        let archiveStart = cal.date(
            byAdding: .day,
            value: -maximumCatchupDays,
            to: today
        ) ?? today
        guard let earliestEPGDate = epgCache.earliestEPGDate else { return today }
        let epgStart = min(today, cal.startOfDay(for: earliestEPGDate))
        return max(archiveStart, epgStart)
        #else
        return today
        #endif
    }

    private var earliestNavigableWeekStart: Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: earliestNavigableDate)
        let diff = weekday - cal.firstWeekday
        return cal.date(
            byAdding: .day,
            value: -(diff < 0 ? diff + 7 : diff),
            to: earliestNavigableDate
        ) ?? earliestNavigableDate
    }

    private func navigateBack() {
        let cal = Calendar.current
        switch viewMode {
        case .day:
            let newDate = cal.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            selectedDate = max(newDate, earliestNavigableDate)
        case .week:
            let newDate = cal.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
            selectedDate = max(newDate, earliestNavigableDate)
        }
    }

    private func navigateForward() {
        let cal = Calendar.current
        switch viewMode {
        case .day:
            selectedDate = cal.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = cal.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        }
    }
}

/// Standalone calendar tab for macOS sidebar — loads its own topic data
struct CalendarTabView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var epgCache: EPGCache
    @StateObject private var viewModel = TopicsViewModel()

    var body: some View {
        CalendarView(programs: viewModel.matchingPrograms)
            .environmentObject(client)
            .environmentObject(appState)
            .task {
                viewModel.epgCache = epgCache
                viewModel.client = client
                await viewModel.loadData()
            }
    }
}
#endif
