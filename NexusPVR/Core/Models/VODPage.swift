//
//  VODPage.swift
//  DispatcherPVR
//
//  One page of the VOD library (#17)
//

import Foundation

nonisolated struct VODPage: Sendable {
    let items: [VODItem]
    /// Size of the whole filtered library, not of this page.
    let totalCount: Int
    let hasMore: Bool
}
