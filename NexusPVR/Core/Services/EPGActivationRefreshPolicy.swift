//
//  EPGActivationRefreshPolicy.swift
//  PVR Client
//
//  Decides whether returning to the foreground should refresh the EPG (#166).
//

import Foundation

/// Whether a scene activation should refresh the shared `EPGCache`.
///
/// Activation fires often on tvOS (screensaver, Control Center, app switcher),
/// so the refresh only runs when it can't collide with other work:
/// - before the first load completes, `loadData` owns the cache — a refresh would
///   cancel its background full-EPG load and fetch the same data again;
/// - while a refresh is already in flight, the new request is coalesced into it;
/// - while a live stream is open, it's skipped: the player covers the page, and a
///   refresh that has to re-authenticate would rotate the SID that owns the
///   server-side stream (see `ForegroundAuthPolicy`, #133).
enum EPGActivationRefreshPolicy {
    static func shouldRefresh(
        isConfigured: Bool,
        hasLoaded: Bool,
        isLoading: Bool,
        isRefreshing: Bool,
        hasActiveLiveStream: Bool
    ) -> Bool {
        isConfigured && hasLoaded && !isLoading && !isRefreshing && !hasActiveLiveStream
    }
}
