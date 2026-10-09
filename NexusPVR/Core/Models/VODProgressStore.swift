//
//  VODProgressStore.swift
//  DispatcherPVR
//
//  Device-local playback positions for VOD, keyed by the movie's or
//  episode's uuid (#17)
//

import Foundation

nonisolated struct VODProgressStore: Codable, Equatable, Sendable {
    private(set) var entries: [String: VODProgress] = [:]

    static let storageKey = "VODProgress_Dispatcharr"
    /// Oldest entries are dropped past this, so the store can't grow forever.
    static let maxEntries = 500

    subscript(uuid: String) -> VODProgress? { entries[uuid] }

    /// Records a position. Near the end counts as watched; a few seconds in
    /// is ignored, so an accidental play doesn't mark an item as started.
    mutating func record(uuid: String, position: Int, duration: Int, at date: Date = Date()) {
        guard !uuid.isEmpty, position > 10 else { return }
        let watched = duration > 0 && position > duration - 30
        entries[uuid] = VODProgress(
            position: watched ? duration : position,
            duration: duration,
            updatedAt: date
        )
        if entries.count > Self.maxEntries {
            let overflow = entries.count - Self.maxEntries
            for key in entries.sorted(by: { $0.value.updatedAt < $1.value.updatedAt }).prefix(overflow).map(\.key) {
                entries.removeValue(forKey: key)
            }
        }
    }

    mutating func clear(uuid: String) {
        entries.removeValue(forKey: uuid)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> VODProgressStore {
        guard let data = defaults.data(forKey: storageKey),
              let store = try? JSONDecoder().decode(VODProgressStore.self, from: data) else {
            return VODProgressStore()
        }
        return store
    }
}
