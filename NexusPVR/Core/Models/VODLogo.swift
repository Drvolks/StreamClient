//
//  VODLogo.swift
//  DispatcherPVR
//
//  Poster reference attached to a VOD movie or series (#17)
//

import Foundation

nonisolated struct VODLogo: Decodable, Hashable, Sendable {
    /// Nil when the cover comes straight from the provider instead of a
    /// stored logo.
    let id: Int?
    let url: String?
    /// Dispatcharr's own copy of the image; preferred, as it needs no
    /// provider access from the device.
    let cacheURL: String?

    enum CodingKeys: String, CodingKey {
        case id, url
        case cacheURL = "cache_url"
    }

    init(id: Int? = nil, url: String? = nil, cacheURL: String? = nil) {
        self.id = id
        self.url = url
        self.cacheURL = cacheURL
    }

    /// The image to load: the cached copy when there is one.
    var preferredURLString: String? {
        [cacheURL, url].compactMap { $0 }.first { !$0.isEmpty }
    }
}
