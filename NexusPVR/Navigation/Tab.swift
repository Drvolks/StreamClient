//
//  Tab.swift
//  nextpvr-apple-client
//
//  Navigation tab enumeration
//

import Foundation

enum Tab: String, Identifiable, Codable {
    case guide = "Guide"
    case channels = "Channels"
    case recordings = "Recordings"
    #if DISPATCHERPVR
    /// Dispatcharr's on-demand library: movies and series (#17).
    case vod = "On Demand"
    #endif
    case topics = "Topics"
    case calendar = "Calendar"
    case search = "Search"
    #if !os(tvOS)
    case downloads = "Downloads"
    #endif
    #if DISPATCHERPVR
    case stats = "Status"
    #endif
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .guide: return "calendar"
        case .channels: return "tv"
        case .topics: return "star.fill"
        case .calendar: return "calendar.badge.clock"
        case .search: return "magnifyingglass"
        case .recordings: return "recordingtape"
        #if DISPATCHERPVR
        case .vod: return "film.stack"
        #endif
        #if !os(tvOS)
        case .downloads: return "arrow.down.circle"
        #endif
        #if DISPATCHERPVR
        case .stats: return "chart.bar.fill"
        #endif
        case .settings: return "gear"
        }
    }

    var label: String { rawValue }

    /// True for the On Demand tab; always false where it doesn't exist.
    var isVOD: Bool {
        #if DISPATCHERPVR
        return self == .vod
        #else
        return false
        #endif
    }

    static var allCases: [Tab] {
        allCases(userLevel: 10)
    }

    /// `showsVOD` adds On Demand right under Recordings; it is only ever true
    /// on Dispatcharr, when the server has movies or series to offer (#17).
    static func allCases(userLevel: Int, hideRecordings: Bool = false, showsVOD: Bool = false) -> [Tab] {
        var cases: [Tab] = [.guide, .channels]
        if userLevel >= 1 && !hideRecordings { cases.append(.recordings) }
        appendVOD(to: &cases, showsVOD: showsVOD)
        cases.append(contentsOf: [.topics, .search])
        #if DISPATCHERPVR
        if userLevel >= 1 { cases.append(.stats) }
        #endif
        cases.append(.settings)
        return cases
    }

    private static func appendVOD(to cases: inout [Tab], showsVOD: Bool) {
        #if DISPATCHERPVR
        if showsVOD { cases.append(.vod) }
        #endif
    }

    #if os(iOS)
    /// Tabs shown in the iOS collapsible nav bar (search is integrated into the bar itself)
    static func iOSTabs(userLevel: Int, hideRecordings: Bool = false, showsVOD: Bool = false) -> [Tab] {
        var cases: [Tab] = [.guide, .channels]
        if userLevel >= 1 && !hideRecordings { cases.append(.recordings) }
        appendVOD(to: &cases, showsVOD: showsVOD)
        cases.append(contentsOf: [.topics, .calendar, .downloads])
        #if DISPATCHERPVR
        if userLevel >= 1 { cases.append(.stats) }
        #endif
        cases.append(.settings)
        return cases
    }
    #endif

    #if os(macOS)
    /// Tabs shown in the macOS sidebar (search is integrated into the guide floating bar)
    static func macOSTabs(userLevel: Int, hideRecordings: Bool = false, showsVOD: Bool = false) -> [Tab] {
        var cases: [Tab] = [.guide, .channels]
        if userLevel >= 1 && !hideRecordings { cases.append(.recordings) }
        appendVOD(to: &cases, showsVOD: showsVOD)
        cases.append(contentsOf: [.topics, .calendar, .downloads])
        #if DISPATCHERPVR
        if userLevel >= 1 { cases.append(.stats) }
        #endif
        cases.append(.settings)
        return cases
    }
    #endif

    #if os(tvOS)
    /// Tabs shown in the tvOS sidebar. Status (Dispatcharr) is left out of
    /// tvOS for now.
    static func tvOSTabs(userLevel: Int, hideRecordings: Bool = false, showsVOD: Bool = false) -> [Tab] {
        var cases: [Tab] = [.guide, .channels]
        if userLevel >= 1 && !hideRecordings { cases.append(.recordings) }
        appendVOD(to: &cases, showsVOD: showsVOD)
        cases.append(.topics)
        cases.append(.settings)
        return cases
    }
    #endif
}
