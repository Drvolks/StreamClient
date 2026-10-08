//
//  ChannelGroupBadge.swift
//  nextpvr-apple-client
//
//  Which group names a channel in its corner badge (macOS guide column and
//  channel cards).
//

import Foundation

nonisolated enum ChannelGroupBadge {
    /// How many of `channels` each group holds, keyed by group id.
    static func groupSizes(_ groups: [ChannelGroup], in channels: [Channel]) -> [Int: Int] {
        var sizes: [Int: Int] = [:]
        for group in groups {
            sizes[group.id] = channels.reduce(0) { $0 + ($1.isMember(ofGroup: group.id) ? 1 : 0) }
        }
        return sizes
    }

    /// The channel's most specific group: the smallest one it belongs to.
    /// A group holding every channel (NextPVR's built-in "All Channels") says
    /// nothing about the channel, so it never names the badge; a channel in
    /// no other group gets no badge.
    static func name(
        for channel: Channel,
        groups: [ChannelGroup],
        sizes: [Int: Int],
        channelCount: Int
    ) -> String? {
        groups
            .filter { channel.isMember(ofGroup: $0.id) }
            .filter { (sizes[$0.id] ?? 0) < channelCount }
            .min { (sizes[$0.id] ?? 0) < (sizes[$1.id] ?? 0) }?
            .name
    }
}
