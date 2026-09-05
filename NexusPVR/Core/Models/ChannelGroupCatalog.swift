//
//  ChannelGroupCatalog.swift
//  nextpvr-apple-client
//
//  Backend-neutral channel group listing plus channel membership (#158).
//

import Foundation

/// The groups a server exposes together with the channels in each of them.
///
/// NextPVR reports groups and their members through separate requests, so this
/// bundles both into one value the cache can apply atomically. An empty
/// catalogue is the documented "this server has no groups" answer — never an
/// error — so callers keep working with the full channel list.
nonisolated struct ChannelGroupCatalog: Sendable, Equatable {
    let groups: [ChannelGroup]
    /// Channel id → ids of every group that channel belongs to.
    let membership: [Int: [Int]]

    init(groups: [ChannelGroup], membership: [Int: [Int]]) {
        self.groups = groups
        self.membership = membership
    }

    /// Builds a catalogue from each group's channel ids, inverting it into the
    /// per-channel membership the cache needs. Duplicate ids inside a group and
    /// duplicate group entries for a channel are both collapsed.
    init(groups: [ChannelGroup], channelIdsByGroupId: [Int: [Int]]) {
        var membership: [Int: [Int]] = [:]
        for group in groups {
            for channelId in channelIdsByGroupId[group.id] ?? [] {
                var ids = membership[channelId] ?? []
                if !ids.contains(group.id) {
                    ids.append(group.id)
                    membership[channelId] = ids
                }
            }
        }
        self.init(groups: groups, membership: membership)
    }

    static let empty = ChannelGroupCatalog(groups: [], membership: [:])

    var isEmpty: Bool { groups.isEmpty }

    /// Ids of the channels in `groupId`, in no particular order.
    func channelIds(inGroup groupId: Int) -> Set<Int> {
        Set(membership.compactMap { $0.value.contains(groupId) ? $0.key : nil })
    }
}
