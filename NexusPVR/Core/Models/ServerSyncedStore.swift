//
//  ServerSyncedStore.swift
//  DispatcherPVR
//
//  What `DispatcharrPositionSync` needs from a store to keep a copy of it in
//  Dispatcharr's per-user app data: the playback positions (#199) and the
//  topic keywords.
//

import Foundation

nonisolated protocol ServerSyncedStore: Codable, Equatable, Sendable {
    init()
    var entryCount: Int { get }
    /// Takes the newer entry per item from `other`.
    mutating func merge(_ other: Self)
    /// Drops the oldest entries so at most `count` remain.
    mutating func keepNewest(_ count: Int)
}
