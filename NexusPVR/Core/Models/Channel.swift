//
//  Channel.swift
//  nextpvr-apple-client
//
//  NextPVR channel model
//

import Foundation

nonisolated struct Channel: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let number: Int
    let hasIcon: Bool
    let streamURL: String?
    let groupId: Int?
    let logoURL: String?
    /// Dispatcharr catch-up (timeshift) capability (#119). Always `false`/`0`
    /// on NextPVR, which has no equivalent server-side archive.
    let isCatchup: Bool
    let catchupDays: Int

    enum CodingKeys: String, CodingKey {
        case id = "channelId"
        case name = "channelName"
        case number = "channelNumber"
        case hasIcon = "channelIcon"
        case streamURL = "channelDetails"
    }

    init(id: Int, name: String, number: Int, hasIcon: Bool = false, streamURL: String? = nil, groupId: Int? = nil, logoURL: String? = nil, isCatchup: Bool = false, catchupDays: Int = 0) {
        self.id = id
        self.name = name
        self.number = number
        self.hasIcon = hasIcon
        self.streamURL = streamURL
        self.groupId = groupId
        self.logoURL = logoURL
        self.isCatchup = isCatchup
        self.catchupDays = catchupDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        hasIcon = try container.decodeIfPresent(Bool.self, forKey: .hasIcon) ?? false
        streamURL = try container.decodeIfPresent(String.self, forKey: .streamURL)?.trimmingCharacters(in: .whitespaces)
        groupId = nil
        logoURL = nil
        isCatchup = false
        catchupDays = 0
    }

    func iconURL(baseURL: String) -> URL? {
        URL(string: "\(baseURL)/service?method=channel.icon&channel_id=\(id)")
    }

    /// Returns a copy with catch-up capability replaced (#119) — used to
    /// backfill `isCatchup`/`catchupDays` onto a channel decoded from
    /// Dispatcharr's `summary/` endpoint, whose serializer omits both
    /// fields. See `EPGCache`'s catch-up enrichment pass.
    func withCatchup(isCatchup: Bool, catchupDays: Int) -> Channel {
        Channel(
            id: id,
            name: name,
            number: number,
            hasIcon: hasIcon,
            streamURL: streamURL,
            groupId: groupId,
            logoURL: logoURL,
            isCatchup: isCatchup,
            catchupDays: catchupDays
        )
    }
}
