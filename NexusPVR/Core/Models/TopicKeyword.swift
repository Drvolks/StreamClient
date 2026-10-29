//
//  TopicKeyword.swift
//  nextpvr-apple-client
//
//  One topic keyword in `TopicKeywordStore`, with when it was last changed.
//

import Foundation

nonisolated struct TopicKeyword: Codable, Equatable, Sendable {
    /// The keyword as the user typed it.
    let name: String
    /// Where it sits in the topic list; ties are broken by keyword.
    let order: Int
    /// A removed keyword is kept as an entry rather than dropped, so the
    /// removal wins over an older copy on another device.
    let isRemoved: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name, order, updatedAt
        case isRemoved = "removed"
    }

    /// Which of two entries for the same keyword to keep: the newer one. On a
    /// tie every device must pick the same winner, so the removal, then the
    /// later position, then the name decides.
    func supersedes(_ other: TopicKeyword) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if isRemoved != other.isRemoved { return isRemoved }
        if order != other.order { return order > other.order }
        return name > other.name
    }
}
