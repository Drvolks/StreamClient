//
//  VODStream.swift
//  DispatcherPVR
//
//  One source of an On Demand title: the same movie or series can come from
//  several M3U accounts, or several streams of one account. Listed by
//  `/api/vod/movies|series/<id>/providers/`; the player asks for one with
//  `stream_id` / `m3u_account_id` on the proxy URL.
//

import Foundation

nonisolated struct VODStream: Decodable, Identifiable, Hashable, Sendable {
    /// The relation's id on the server.
    let id: Int
    let accountId: Int
    let accountName: String
    /// The provider's stream id. Movies and episodes have one; a series
    /// relation doesn't, and is chosen by account instead.
    let streamId: String?
    /// "1080p", "4K", a bitrate, whatever the server could tell.
    let quality: String?

    enum CodingKeys: String, CodingKey {
        case id
        case account = "m3u_account"
        case streamId = "stream_id"
        case qualityInfo = "quality_info"
    }

    private struct Account: Decodable {
        let id: Int
        let name: String?
    }

    private struct QualityInfo: Decodable {
        let quality: String?
        let resolution: String?
        let bitrate: String?
    }

    init(id: Int, accountId: Int, accountName: String, streamId: String? = nil, quality: String? = nil) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.streamId = streamId
        self.quality = quality
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        let account = try container.decode(Account.self, forKey: .account)
        accountId = account.id
        accountName = account.name?.isEmpty == false ? account.name ?? "" : "Account \(account.id)"
        // Stored as text, but tolerate a number.
        if let text = try? container.decodeIfPresent(String.self, forKey: .streamId) {
            streamId = text.isEmpty ? nil : text
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .streamId) {
            streamId = String(number)
        } else {
            streamId = nil
        }
        let info = try? container.decodeIfPresent(QualityInfo.self, forKey: .qualityInfo)
        quality = [info?.quality, info?.resolution, info?.bitrate]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// As Dispatcharr's web UI shows it: "Strong (remy) - 1080p (Stream 771230)".
    var label: String {
        var text = accountName
        if let quality { text += " - \(quality)" }
        if let streamId { text += " (Stream \(streamId))" }
        return text
    }

    /// What the proxy reads to play this source: the stream when there is
    /// one (with its account, for the server's stricter lookup), else the
    /// account.
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let streamId {
            items.append(URLQueryItem(name: "stream_id", value: streamId))
        }
        items.append(URLQueryItem(name: "m3u_account_id", value: String(accountId)))
        return items
    }
}
