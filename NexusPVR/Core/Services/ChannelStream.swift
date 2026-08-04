//
//  ChannelStream.swift
//  DispatcherPVR
//
//  A stream assigned to a Dispatcharr channel (a selectable source)
//

import Foundation

nonisolated struct ChannelStream: Decodable, Identifiable, Sendable, Hashable {
    let id: Int
    let name: String?
    /// Id of the M3U account the stream comes from, when it isn't a custom stream.
    let m3uAccountId: Int?
    let isStale: Bool?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return "Stream #\(id)"
    }

    /// User-facing label matching the web app: `Stream name [M3U account]`.
    /// `accountNameLookup` resolves `m3u_account` ids to names (see `M3UAccount`).
    func label(accountNameLookup: ((Int) -> String?)?) -> String {
        guard let m3uAccountId else { return displayName }
        let account = accountNameLookup?(m3uAccountId) ?? "M3U #\(m3uAccountId)"
        return "\(displayName) [\(account)]"
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case m3uAccount = "m3u_account"
        case isStale = "is_stale"
    }

    init(id: Int, name: String?, m3uAccountId: Int?, isStale: Bool? = nil) {
        self.id = id
        self.name = name
        self.m3uAccountId = m3uAccountId
        self.isStale = isStale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // id can be Int or String
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = intId
        } else {
            let raw = try container.decode(String.self, forKey: .id)
            guard let parsed = Int(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Unparsable stream id")
            }
            id = parsed
        }

        name = try container.decodeIfPresent(String.self, forKey: .name)

        // m3u_account is normally a primary key, but can be nested or absent
        // (custom streams have no account).
        if let intAccount = try? container.decode(Int.self, forKey: .m3uAccount) {
            m3uAccountId = intAccount
        } else if let stringAccount = try? container.decode(String.self, forKey: .m3uAccount),
                  let parsed = Int(stringAccount) {
            m3uAccountId = parsed
        } else if let nested = try? container.decode(NestedID.self, forKey: .m3uAccount) {
            m3uAccountId = nested.id
        } else {
            m3uAccountId = nil
        }

        isStale = try? container.decodeIfPresent(Bool.self, forKey: .isStale)
    }

    private struct NestedID: Decodable {
        let id: Int
    }
}
