//
//  TVDetailCoverGate.swift
//  nextpvr-apple-client
//
//  Keeps the tvOS player from presenting on top of a detail page.
//

import Foundation
import Combine

/// Tracks the detail pages (`detailCover`) on screen, so the tvOS player
/// cover is presented only once they are gone.
///
/// A detail page starts playback with `appState.playStream(...)` and then
/// `dismiss()`es itself. Both are full-screen covers, the player's one
/// higher in the hierarchy. When the player managed to present before the
/// dismissal, UIKit dismissed it together with the detail page: PlayerView
/// disappeared a moment after appearing, ended the catch-up session it had
/// just been handed (Dispatcharr then answered mpv's next request with a 400)
/// and stopped playback. Which one won depended on main-thread timing.
@MainActor
final class TVDetailCoverGate: ObservableObject {
    static let shared = TVDetailCoverGate()

    @Published private(set) var openCovers: Set<UUID> = []

    var hasOpenCover: Bool { !openCovers.isEmpty }

    init() {}

    func coverAppeared(_ id: UUID) {
        openCovers.insert(id)
    }

    /// Called once the cover has gone; `onDisappear` of a full-screen
    /// cover's content runs when its dismissal finishes.
    func coverDisappeared(_ id: UUID) {
        openCovers.remove(id)
    }
}
