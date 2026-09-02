//
//  Notification+Extensions.swift
//  nextpvr-apple-client
//
//  Notification names for app events
//

import Foundation

nonisolated extension Notification.Name {
    static let preferencesDidSync = Notification.Name("preferencesDidSync")
    static let recordingsDidChange = Notification.Name("recordingsDidChange")
    /// Posted by the player when a downloaded file's playback position moves.
    /// `DownloadManager` listens and writes it to the item's sidecar — the
    /// player has no business knowing where downloads are stored, and the
    /// server has no record of a local file's position.
    /// userInfo: `downloadId: UUID`, `position: Double` (seconds).
    static let downloadPositionDidChange = Notification.Name("downloadPositionDidChange")
}
