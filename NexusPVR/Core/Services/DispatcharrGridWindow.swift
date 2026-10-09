//
//  DispatcharrGridWindow.swift
//  DispatcherPVR
//
//  Request building and response checks for Dispatcharr's windowed
//  `/api/epg/grid/` endpoint (#157).
//

import Foundation

nonisolated enum DispatcharrGridWindow {
    /// Status a window-aware server answers `probeURL` with.
    static let rejectedWindowStatus = 400

    /// Grid URL for `window`, or for the server's default window (now-1h to
    /// now+24h) when nil. `profileId` narrows the result to one channel
    /// profile; nil leaves the caller's default channel set.
    static func url(baseURL: String, window: DateInterval?, profileId: Int?) -> URL? {
        guard var components = URLComponents(string: "\(baseURL)/api/epg/grid/") else { return nil }
        var queryItems: [URLQueryItem] = []
        if let window {
            queryItems.append(URLQueryItem(name: "start", value: timestamp(window.start)))
            queryItems.append(URLQueryItem(name: "end", value: timestamp(window.end)))
        }
        if let profileId {
            queryItems.append(URLQueryItem(name: "channel_profile_id", value: String(profileId)))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    /// A window that ends before it starts. A server that reads `start`/`end`
    /// rejects it outright; one that predates them ignores both.
    static func probeURL(baseURL: String) -> URL? {
        guard var components = URLComponents(string: "\(baseURL)/api/epg/grid/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "start", value: "2000-01-02T00:00:00Z"),
            URLQueryItem(name: "end", value: "2000-01-01T00:00:00Z")
        ]
        return components.url
    }

    /// What the answer to `probeURL` says about the server: true when it
    /// rejected the window, false when it served a grid anyway, nil when the
    /// status says nothing either way (a server error, say).
    static func supportsWindows(probeStatus status: Int) -> Bool? {
        if status == rejectedWindowStatus { return true }
        if (200...299).contains(status) { return false }
        return nil
    }

    /// Whether `programs` could be the answer to a request for `window`.
    ///
    /// Only stored programmes are judged: the server selects those with a
    /// strict overlap test, whereas the placeholders it generates for
    /// channels without EPG (synthetic ids) follow their own block layout.
    static func respectsWindow(_ programs: [DispatcharrProgram], window: DateInterval) -> Bool {
        programs.allSatisfy { program in
            guard !program.idWasSynthetic, let airTime = program.airTime else { return true }
            return airTime.end > window.start && airTime.start < window.end
        }
    }

    /// ISO 8601 in UTC, whole seconds, e.g. `2026-02-14T18:00:00Z`.
    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
