//
//  EPGActivationRefreshPolicy.swift
//  PVR Client
//
//  Decides whether returning to the foreground should refresh the EPG (#166).
//

import Foundation

/// Whether a scene activation should refresh the shared `EPGCache`.
///
/// The Guide and Channels pages both ask this on activation, so they refresh
/// under the same rules. Activation fires often on tvOS (screensaver, Control
/// Center, app switcher), so the refresh only runs when it's useful and can't
/// collide with other work:
/// - before the first load completes, `loadData` owns the cache — a refresh would
///   cancel its background full-EPG load and fetch the same data again;
/// - while a refresh is already in flight, the new request is coalesced into it;
/// - while a live stream is open, it's skipped: the player covers the page, and a
///   refresh that has to re-authenticate would rotate the SID that owns the
///   server-side stream (see `ForegroundAuthPolicy`, #133);
/// - when the data was fetched less than `minimumInterval` ago, a brief trip out
///   of the app doesn't re-download channels and the multi-day EPG.
enum EPGActivationRefreshPolicy {
    static let minimumInterval: TimeInterval = 5 * 60

    static func shouldRefresh(
        isConfigured: Bool,
        hasLoaded: Bool,
        isLoading: Bool,
        isRefreshing: Bool,
        hasActiveLiveStream: Bool,
        lastRefreshDate: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isConfigured, hasLoaded, !isLoading, !isRefreshing, !hasActiveLiveStream else {
            return false
        }
        // No successful fetch yet (the initial load failed): retry.
        guard let lastRefreshDate else { return true }
        return now.timeIntervalSince(lastRefreshDate) >= minimumInterval
    }
}
