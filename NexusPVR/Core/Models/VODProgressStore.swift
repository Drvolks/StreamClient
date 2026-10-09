//
//  VODProgressStore.swift
//  DispatcherPVR
//
//  Playback positions for VOD, keyed by the movie's or episode's uuid (#17).
//  Dispatcharr stores none, so they are kept here and synced between this
//  user's devices through iCloud Key-Value Storage (#183).
//

import Foundation

nonisolated struct VODProgressStore: Codable, Equatable, Sendable {
    /// Includes cleared items, kept at position 0 so that "mark as unwatched"
    /// reaches the other devices instead of being undone by their copy.
    private(set) var entries: [String: VODProgress] = [:]

    static let storageKey = "VODProgress_Dispatcharr"
    /// Oldest entries are dropped past this, so the store can't grow forever
    /// and stays far below the 1 MB iCloud KVS limit.
    static let maxEntries = 500

    private static var ubiquitousStore: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }

    /// Only the app's own defaults are mirrored to iCloud — not a scratch
    /// suite, and not demo mode's made-up library.
    private static func syncsWithCloud(_ defaults: UserDefaults) -> Bool {
        defaults === UserDefaults.standard && UserPreferences.demoStore == nil
    }

    /// nil for an item that was never played or has been cleared.
    subscript(uuid: String) -> VODProgress? {
        guard let progress = entries[uuid], progress.position > 0 else { return nil }
        return progress
    }

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
        prune()
    }

    mutating func clear(uuid: String, at date: Date = Date()) {
        guard let existing = entries[uuid] else { return }
        entries[uuid] = VODProgress(position: 0, duration: existing.duration, updatedAt: date)
    }

    /// Takes the newer entry per item from `other`.
    mutating func merge(_ other: VODProgressStore) {
        for (key, theirs) in other.entries {
            if let ours = entries[key], !theirs.supersedes(ours) { continue }
            entries[key] = theirs
        }
        prune()
    }

    private mutating func prune() {
        guard entries.count > Self.maxEntries else { return }
        // Keys break timestamp ties so every device drops the same entries.
        let oldestFirst = entries.sorted {
            $0.value.updatedAt != $1.value.updatedAt ? $0.value.updatedAt < $1.value.updatedAt : $0.key < $1.key
        }
        for (key, _) in oldestFirst.prefix(entries.count - Self.maxEntries) {
            entries.removeValue(forKey: key)
        }
    }

    // MARK: - Persistence

    var encoded: Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> VODProgressStore? {
        data.flatMap { try? JSONDecoder().decode(VODProgressStore.self, from: $0) }
    }

    /// Saves locally, and publishes to iCloud when `defaults` is the app's own.
    func save(to defaults: UserDefaults = .standard) {
        guard let encoded else { return }
        defaults.set(encoded, forKey: Self.storageKey)
        if Self.syncsWithCloud(defaults) {
            Self.ubiquitousStore.set(encoded, forKey: Self.storageKey)
        }
    }

    /// The local copy, merged with the iCloud copy when `defaults` is the
    /// app's own.
    static func load(from defaults: UserDefaults = .standard) -> VODProgressStore {
        let cloudData = syncsWithCloud(defaults) ? ubiquitousStore.data(forKey: storageKey) : nil
        return load(from: defaults, cloudData: cloudData)
    }

    /// Local copy merged with `cloudData`, written back locally.
    static func load(from defaults: UserDefaults, cloudData: Data?) -> VODProgressStore {
        let local = decode(defaults.data(forKey: storageKey))
        var store = local ?? VODProgressStore()
        if let cloud = decode(cloudData) {
            store.merge(cloud)
        }
        if store != (local ?? VODProgressStore()), let encoded = store.encoded {
            defaults.set(encoded, forKey: storageKey)
        }
        return store
    }

    // MARK: - Sync

    /// Merges the iCloud copy into the local one. `localChanged` tells the
    /// caller another device's progress arrived; `cloudIsBehind` that this
    /// device holds entries iCloud lacks (saved offline, or overwritten by a
    /// device that hadn't seen them yet).
    static func reconcile(defaults: UserDefaults,
                          cloudData: Data?) -> (store: VODProgressStore, localChanged: Bool, cloudIsBehind: Bool) {
        let before = decode(defaults.data(forKey: storageKey)) ?? VODProgressStore()
        let store = load(from: defaults, cloudData: cloudData)
        let cloud = decode(cloudData) ?? VODProgressStore()
        return (store, store != before, store != cloud)
    }

    /// Call once at launch. Brings the two copies in line, then keeps doing
    /// so whenever another device publishes, calling `onChange` when that
    /// changed something here.
    static func startObservingSync(onChange: @escaping @Sendable () -> Void) {
        syncWithCloud()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys?.contains(storageKey) ?? true else { return }
            if syncWithCloud() {
                onChange()
            }
        }
    }

    @discardableResult
    private static func syncWithCloud() -> Bool {
        let result = reconcile(defaults: .standard, cloudData: ubiquitousStore.data(forKey: storageKey))
        if result.cloudIsBehind, let encoded = result.store.encoded {
            ubiquitousStore.set(encoded, forKey: storageKey)
        }
        return result.localChanged
    }
}
