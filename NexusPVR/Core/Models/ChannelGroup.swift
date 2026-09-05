//
//  ChannelGroup.swift
//  nextpvr-apple-client
//
//  Channel group model
//

import Foundation

nonisolated struct ChannelGroup: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    /// Builds a group from a name-only backend (#158).
    ///
    /// NextPVR identifies channel groups by name: `channel.groups` lists names
    /// and `channel.list&group_id=<name>` filters by one. The shared sidebar,
    /// filter and preference plumbing is keyed on `Int`, so derive the id from
    /// the name instead of inventing a per-session number.
    init(name: String) {
        self.init(id: Self.stableId(forName: name), name: name)
    }

    /// Deterministic 32-bit FNV-1a hash of a group name.
    ///
    /// Unlike `String.hashValue`, which Swift seeds per process, this is stable
    /// across launches and devices — required because the ids end up in
    /// `UserPreferences.guideGroupIds`, which is persisted and synced via
    /// iCloud.
    static func stableId(forName name: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        // Keep it non-negative and inside Int32 so it round-trips unchanged
        // through JSON and property-list encodings.
        return Int(hash & 0x7FFF_FFFF)
    }
}
