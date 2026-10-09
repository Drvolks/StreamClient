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

    enum CodingKeys: String, CodingKey {
        case id, name
        case categoryType = "category_type"
    }

    init(id: Int, name: String, categoryType: String) {
        self.id = id
        self.name = name
        self.categoryType = categoryType
    }

    /// Value of the list endpoints' `category` filter.
    var filterValue: String { "\(name)|\(categoryType)" }
}
