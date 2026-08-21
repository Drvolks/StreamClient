//
//  DispatcharrChannel.swift
//  DispatcherPVR
//
//  Dispatcharr channel API model
//

import Foundation

nonisolated struct DispatcharrChannel: Decodable {
    let id: Int
    let name: String
    let channelNumber: Double?
    let tvgId: String?
    let logoId: Int?
    let uuid: String?
    let epgDataId: Int?
    let channelGroupId: Int?
    /// Whether any stream on this channel supports catch-up (#119). Rolled
    /// up server-side from the underlying streams' `tv_archive` flag.
    /// Missing on endpoints/server versions that don't expose it yet —
    /// defaults to `false` so the guide simply shows no catch-up badge.
    let isCatchup: Bool
    /// Max catch-up archive window (days) across the channel's streams.
    /// Pairs with `isCatchup` to bound how far back a program can still
    /// be requested.
    let catchupDays: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case channelNumber = "channel_number"
        case tvgId = "tvg_id"
        case logoId = "logo_id"
        case uuid
        case epgDataId = "epg_data_id"
        case channelGroupId = "channel_group_id"
        case isCatchup = "is_catchup"
        case catchupDays = "catchup_days"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // id can be Int or String
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = intId
        } else if let stringId = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(stringId) {
            id = parsed
        } else {
            let raw = try container.decode(String.self, forKey: .id)
            id = abs(raw.hashValue)
        }

        name = try container.decode(String.self, forKey: .name)
        channelNumber = try container.decodeIfPresent(Double.self, forKey: .channelNumber)
        tvgId = try container.decodeIfPresent(String.self, forKey: .tvgId)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)

        // logo_id can be Int or String
        if let intLogo = try? container.decode(Int.self, forKey: .logoId) {
            logoId = intLogo
        } else if let stringLogo = try? container.decodeIfPresent(String.self, forKey: .logoId),
                  let parsed = Int(stringLogo) {
            logoId = parsed
        } else {
            logoId = nil
        }

        // epg_data_id can be Int or String
        if let intEpg = try? container.decode(Int.self, forKey: .epgDataId) {
            epgDataId = intEpg
        } else if let stringEpg = try? container.decodeIfPresent(String.self, forKey: .epgDataId),
                  let parsed = Int(stringEpg) {
            epgDataId = parsed
        } else {
            epgDataId = nil
        }

        // channel_group_id can be Int or String
        if let intGroup = try? container.decode(Int.self, forKey: .channelGroupId) {
            channelGroupId = intGroup
        } else if let stringGroup = try? container.decodeIfPresent(String.self, forKey: .channelGroupId),
                  let parsed = Int(stringGroup) {
            channelGroupId = parsed
        } else {
            channelGroupId = nil
        }

        isCatchup = try container.decodeIfPresent(Bool.self, forKey: .isCatchup) ?? false
        catchupDays = try container.decodeIfPresent(Int.self, forKey: .catchupDays) ?? 0
    }

    func toChannel() -> Channel {
        Channel(
            id: id,
            name: name,
            number: Int(channelNumber ?? 0),
            hasIcon: logoId != nil,
            groupId: channelGroupId,
            isCatchup: isCatchup,
            catchupDays: catchupDays
        )
    }
}
