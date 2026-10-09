//
//  VODCounts.swift
//  DispatcherPVR
//
//  How much on-demand content the server offers; decides whether the
//  On Demand menu shows at all (#17)
//

import Foundation

nonisolated struct VODCounts: Equatable, Sendable {
    var movies: Int
    var series: Int

    static let none = VODCounts(movies: 0, series: 0)

    var isEmpty: Bool { movies == 0 && series == 0 }

    func count(for kind: VODKind) -> Int {
        switch kind {
        case .movies: movies
        case .series: series
        }
    }

    /// Kinds that have something to browse, in menu order.
    var availableKinds: [VODKind] {
        VODKind.allCases.filter { count(for: $0) > 0 }
    }
}
