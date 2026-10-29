//
//  TopicKeywordStore.swift
//  nextpvr-apple-client
//
//  The topic keywords, one timestamped entry per keyword, so two devices
//  editing the list at the same time both keep their changes. It is synced
//  through iCloud Key-Value Storage, and on Dispatcharr also through the
//  user's app data on the server (`DispatcharrPositionSync`), where it
//  follows the Dispatcharr user rather than the Apple ID.
//
//  This store is the source of truth. `UserPreferences.keywords` mirrors it
//  for the rest of the app and the Top Shelf extension; the preferences blob
//  is synced whole, newest wins, which would drop a keyword added on one
//  device while another saved its preferences.
//

import Foundation

nonisolated struct TopicKeywordStore: ServerSyncedStore {
    /// Keyed by `key(for:)`: one entry per keyword, whatever its case.
    private(set) var entries: [String: TopicKeyword] = [:]

    static let storageKey = "TopicKeywords"
    /// Set once the keywords from before this store were imported.
    static let legacyImportedKey = "TopicKeywordsLegacyImported"
    /// Timestamp of imported keywords: they must lose to any later edit,
    /// including a removal on a device that imported them earlier.
    static let legacyDate = Date(timeIntervalSince1970: 0)
    /// Removed keywords are dropped first past this.
    static let maxEntries = 500
    /// Posted when the keywords were edited on this device (not merged in
    /// from elsewhere), so the server copy gets the change.
    static let didSaveNotification = Notification.Name("topicKeywordsSaved")

    private static var ubiquitousStore: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }

    static func key(for keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The topic list, in order.
    var keywords: [String] {
        entries
            .filter { !$0.value.isRemoved }
            .sorted { $0.value.order != $1.value.order ? $0.value.order < $1.value.order : $0.key < $1.key }
            .map(\.value.name)
    }

    var entryCount: Int { entries.count }

    // MARK: - Editing

    /// Makes `list` the topic list. Only the keywords that were added,
    /// removed, renamed or moved get a new timestamp, so a concurrent edit of
    /// another keyword on another device survives the merge.
    mutating func setKeywords(_ list: [String], at date: Date = Date()) {
        let date = date.wholeMilliseconds
        var seen = Set<String>()
        var order = 0
        for name in list {
            let key = Self.key(for: name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let current = entries[key]
            if current == nil || current?.isRemoved == true || current?.name != trimmed || current?.order != order {
                entries[key] = TopicKeyword(name: trimmed, order: order, isRemoved: false, updatedAt: date)
            }
            order += 1
        }
        for (key, entry) in entries where !entry.isRemoved && !seen.contains(key) {
            entries[key] = TopicKeyword(name: entry.name, order: entry.order, isRemoved: true, updatedAt: date)
        }
        prune()
    }

    mutating func add(_ keyword: String, at date: Date = Date()) {
        setKeywords(keywords + [keyword], at: date)
    }

    mutating func remove(_ keyword: String, at date: Date = Date()) {
        let key = Self.key(for: keyword)
        setKeywords(keywords.filter { Self.key(for: $0) != key }, at: date)
    }

    /// Swaps the keyword with its neighbour `offset` places away.
    mutating func move(_ keyword: String, by offset: Int, at date: Date = Date()) {
        var list = keywords
        let key = Self.key(for: keyword)
        guard let index = list.firstIndex(where: { Self.key(for: $0) == key }),
              list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        setKeywords(list, at: date)
    }

    // MARK: - Merging

    /// Takes the newer entry per keyword from `other`.
    mutating func merge(_ other: TopicKeywordStore) {
        for (key, theirs) in other.entries {
            if let ours = entries[key], !theirs.supersedes(ours) { continue }
            entries[key] = theirs
        }
        prune()
    }

    /// Adds keywords saved before this store existed, for keywords it doesn't
    /// know yet. They are dated 1970 so any later edit wins.
    mutating func importLegacy(_ list: [String]) {
        for (order, name) in list.enumerated() {
            let key = Self.key(for: name)
            guard !key.isEmpty, entries[key] == nil else { continue }
            entries[key] = TopicKeyword(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                order: order, isRemoved: false, updatedAt: Self.legacyDate
            )
        }
        prune()
    }

    private mutating func prune() {
        keepNewest(Self.maxEntries)
    }

    /// Drops removed keywords first, oldest first, then the oldest keywords.
    mutating func keepNewest(_ count: Int) {
        guard entries.count > count else { return }
        // Keys break timestamp ties so every device drops the same entries.
        let dropFirst = entries.sorted {
            if $0.value.isRemoved != $1.value.isRemoved { return $0.value.isRemoved }
            if $0.value.updatedAt != $1.value.updatedAt { return $0.value.updatedAt < $1.value.updatedAt }
            return $0.key < $1.key
        }
        for (key, _) in dropFirst.prefix(entries.count - max(count, 0)) {
            entries.removeValue(forKey: key)
        }
    }

    // MARK: - Persistence

    var encoded: Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> TopicKeywordStore? {
        data.flatMap { try? JSONDecoder().decode(TopicKeywordStore.self, from: $0) }
    }

    /// Local copy merged with the iCloud copy, written back locally. The
    /// first call also imports the keywords from the preferences.
    static func load(from defaults: UserDefaults = .standard,
                     cloudData: Data? = ubiquitousStore.data(forKey: storageKey),
                     legacyKeywords: () -> [String] = { UserPreferences.storedKeywords() }) -> TopicKeywordStore {
        let local = decode(defaults.data(forKey: storageKey))
        var store = local ?? TopicKeywordStore()
        if !defaults.bool(forKey: legacyImportedKey) {
            store.importLegacy(legacyKeywords())
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

    /// Saves locally and publishes to iCloud. `announcing` tells the server
    /// sync the keywords were edited here; it is false for keywords that came
    /// from the server in the first place.
    func save(announcing: Bool = true) {
        guard let encoded else { return }
        UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        Self.ubiquitousStore.set(encoded, forKey: Self.storageKey)
        if announcing {
            NotificationCenter.default.post(name: Self.didSaveNotification, object: nil)
        }
    }

    /// Applies one edit from the user and returns the new topic list. In demo
    /// mode the edit stays in the in-memory preferences.
    @discardableResult
    static func edit(_ change: (inout TopicKeywordStore) -> Void) -> [String] {
        if var demo = UserPreferences.demoStore {
            var store = TopicKeywordStore()
            store.setKeywords(demo.keywords)
            change(&store)
            demo.keywords = store.keywords
            UserPreferences.demoStore = demo
            return store.keywords
        }
        var store = load()
        let before = store
        change(&store)
        if store != before {
            store.save()
            // Refreshes the mirror in the preferences and the App Group.
            _ = UserPreferences.load()
        }
        return store.keywords
    }

    // MARK: - Sync

    /// Merges the iCloud copy into the local one. `localChanged` tells the
    /// caller another device's keywords arrived; `cloudIsBehind` that this
    /// device holds entries iCloud lacks.
    static func reconcile(defaults: UserDefaults = .standard,
                          cloudData: Data?,
                          legacyKeywords: () -> [String] = { UserPreferences.storedKeywords() })
        -> (store: TopicKeywordStore, localChanged: Bool, cloudIsBehind: Bool) {
        let before = decode(defaults.data(forKey: storageKey)) ?? TopicKeywordStore()
        let store = load(from: defaults, cloudData: cloudData, legacyKeywords: legacyKeywords)
        let cloud = decode(cloudData) ?? TopicKeywordStore()
        return (store, store != before, store != cloud)
    }

    /// Call once at launch. Brings the two copies in line, then keeps doing
    /// so whenever another device publishes, calling `onChange` when that
    /// changed the keywords here.
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
