//
//  RecordingPositionStore.swift
//  DispatcherPVR
//
//  Resume positions for Dispatcharr recordings, synced between devices
//  through iCloud Key-Value Storage (#183). Dispatcharr stores no playback
//  position, so without this each device only knows what it played itself.
//

import Foundation

nonisolated struct RecordingPositionStore: Codable, Equatable, Sendable {
    private(set) var entries: [String: RecordingPosition] = [:]

    static let storageKey = "RecordingPositions_Dispatcharr"
    /// Oldest entries are dropped past this. At roughly 60 bytes each the
    /// whole store stays far below the 1 MB iCloud KVS limit, in a single key.
    static let maxEntries = 500
    /// Where positions lived before they were synced, one key per recording.
    static let legacyKeyPrefix = "recording_position_"
    static let legacyImportedKey = "RecordingPositionsLegacyImported"
    /// Timestamp given to imported legacy positions: they have no date of
    /// their own, and must lose to anything saved since.
    static let legacyDate = Date(timeIntervalSince1970: 0)

    private static var ubiquitousStore: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }

    subscript(recordingId: Int) -> RecordingPosition? { entries[String(recordingId)] }

    /// The position to resume from, nil when there is none (never played, or
    /// reset to the beginning).
    func resumePosition(for recordingId: Int) -> Int? {
        guard let position = self[recordingId]?.position, position > 0 else { return nil }
        return position
    }

    mutating func set(recordingId: Int, position: Int, at date: Date = Date()) {
        entries[String(recordingId)] = RecordingPosition(position: max(0, position), updatedAt: date)
        prune()
    }

    /// Takes the newer entry per recording from `other`.
    mutating func merge(_ other: RecordingPositionStore) {
        for (key, theirs) in other.entries {
            if let ours = entries[key], !theirs.supersedes(ours) { continue }
            entries[key] = theirs
        }
        prune()
    }

    /// Adds the positions saved under the old per-recording keys, for
    /// recordings the store doesn't know yet. The old keys are left in place.
    mutating func importLegacy(from values: [String: Any]) {
        for (key, value) in values where key.hasPrefix(Self.legacyKeyPrefix) {
            let id = String(key.dropFirst(Self.legacyKeyPrefix.count))
            guard Int(id) != nil, entries[id] == nil,
                  let position = value as? Int, position > 0 else { continue }
            entries[id] = RecordingPosition(position: position, updatedAt: Self.legacyDate)
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

    static func decode(_ data: Data?) -> RecordingPositionStore? {
        data.flatMap { try? JSONDecoder().decode(RecordingPositionStore.self, from: $0) }
    }

    /// Local copy merged with the iCloud copy, written back locally. The
    /// first call also imports the legacy per-recording keys.
    static func load(from defaults: UserDefaults = .standard,
                     cloudData: Data? = ubiquitousStore.data(forKey: storageKey)) -> RecordingPositionStore {
        let local = decode(defaults.data(forKey: storageKey))
        var store = local ?? RecordingPositionStore()
        if !defaults.bool(forKey: legacyImportedKey) {
            store.importLegacy(from: defaults.dictionaryRepresentation())
            defaults.set(true, forKey: legacyImportedKey)
        }
        if let cloud = decode(cloudData) {
            store.merge(cloud)
        }
        if store != local {
            store.saveLocally(to: defaults)
        }
        return store
    }

    func saveLocally(to defaults: UserDefaults = .standard) {
        guard let encoded else { return }
        defaults.set(encoded, forKey: Self.storageKey)
    }

    /// Saves locally and publishes to iCloud.
    func save() {
        guard let encoded else { return }
        UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        Self.ubiquitousStore.set(encoded, forKey: Self.storageKey)
    }

    // MARK: - Sync

    /// Merges the iCloud copy into the local one. `localChanged` tells the
    /// caller another device's positions arrived; `cloudIsBehind` that this
    /// device holds entries iCloud lacks (saved offline, imported from the
    /// legacy keys, or overwritten by a device that hadn't seen them yet).
    static func reconcile(defaults: UserDefaults = .standard,
                          cloudData: Data?) -> (store: RecordingPositionStore, localChanged: Bool, cloudIsBehind: Bool) {
        let before = decode(defaults.data(forKey: storageKey)) ?? RecordingPositionStore()
        let store = load(from: defaults, cloudData: cloudData)
        let cloud = decode(cloudData) ?? RecordingPositionStore()
        return (store, store != before, store != cloud)
    }

    /// Call once at launch. Brings the two copies in line, then keeps doing
    /// so whenever another device publishes, calling `onChange` when that
    /// changed a position here.
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
        let result = reconcile(cloudData: ubiquitousStore.data(forKey: storageKey))
        if result.cloudIsBehind, let encoded = result.store.encoded {
            ubiquitousStore.set(encoded, forKey: storageKey)
        }
        return result.localChanged
    }
}
