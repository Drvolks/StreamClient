//
//  VODCategory.swift
//  DispatcherPVR
//
//  A provider category of movies or series (#17)
//

import Foundation

nonisolated struct VODCategory: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    /// "movie" or "series".
    let categoryType: String
    /// Whether at least one M3U account has this category turned on in
    /// Dispatcharr's VOD category filter. `/api/vod/categories/` lists every
    /// category, filtered out or not, so the app has to hide the disabled ones
    /// itself, as Dispatcharr's web UI does. A server that doesn't send
    /// `m3u_accounts` counts as enabled.
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case categoryType = "category_type"
        case m3uAccounts = "m3u_accounts"
    }

    private struct AccountRelation: Decodable {
        let enabled: Bool?
    }

    init(id: Int, name: String, categoryType: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.categoryType = categoryType
        self.isEnabled = isEnabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        categoryType = try container.decode(String.self, forKey: .categoryType)
        if let accounts = try container.decodeIfPresent([AccountRelation].self, forKey: .m3uAccounts) {
            isEnabled = accounts.contains { $0.enabled == true }
        } else {
            isEnabled = true
        }
    }

    /// Value of the list endpoints' `category` filter.
    var filterValue: String { "\(name)|\(categoryType)" }
}
