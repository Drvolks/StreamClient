//
//  ChannelGroupListResponse.swift
//  nextpvr-apple-client
//
//  NextPVR `channel.groups` API response (#158).
//

import Foundation

/// Decodes the NextPVR `channel.groups` payload into plain group names.
///
/// NextPVR's JSON serializer is hand-written per method and its group listing
/// is name-based rather than the integer-id objects Dispatcharr returns, so
/// this accepts either shape a server may emit:
///
/// ```json
/// { "groups": ["Sports", "News"] }
/// { "groups": [{ "name": "Sports" }, { "name": "News" }] }
/// ```
///
/// A missing `groups` key decodes to no names rather than throwing — servers
/// that don't implement the method must not break the channel load.
nonisolated struct ChannelGroupListResponse: Decodable {
    /// Trimmed, de-duplicated group names in server order.
    let groupNames: [String]

    init(groupNames: [String]) {
        self.groupNames = groupNames
    }

    private enum CodingKeys: String, CodingKey {
        case groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([GroupEntry].self, forKey: .groups) ?? []
        var seen = Set<String>()
        groupNames = entries.compactMap { entry in
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }

    /// One entry of the `groups` array — a bare string, or an object carrying
    /// the name under one of the keys NextPVR builds have used.
    private struct GroupEntry: Decodable {
        let name: String

        private enum NameKeys: String, CodingKey {
            case name
            case group
            case groupName
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let value = try? single.decode(String.self) {
                name = value
                return
            }
            let container = try decoder.container(keyedBy: NameKeys.self)
            for key in [NameKeys.name, .groupName, .group] {
                if let value = try? container.decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                    name = value
                    return
                }
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Channel group entry has no name"
                )
            )
        }
    }
}
