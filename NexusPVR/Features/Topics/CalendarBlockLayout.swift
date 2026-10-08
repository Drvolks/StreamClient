//
//  CalendarBlockLayout.swift
//  nextpvr-apple-client
//
//  Where each program block sits on a calendar day: its column among
//  overlapping programs, and how tall it can be drawn.
//

import Foundation

nonisolated enum CalendarBlockLayout {
    struct Item {
        let id: String
        let start: Date
        let end: Date
    }

    struct Slot: Equatable {
        let column: Int
        let totalColumns: Int
        let height: CGFloat
    }

    /// Lays out one day's programs. Overlapping programs share the width in
    /// columns. A block is at least `minHeight` tall so its title stays
    /// readable, but never runs into the next block in its column: it stops
    /// `gap` short of it, even if that leaves it shorter than `minHeight`.
    static func layout(
        _ items: [Item],
        hourHeight: CGFloat,
        minHeight: CGFloat,
        gap: CGFloat = 1
    ) -> [String: Slot] {
        let sorted = items.sorted { $0.start < $1.start }
        var assignments: [(item: Item, column: Int)] = []
        for item in sorted {
            var column = 0
            while assignments.contains(where: { $0.column == column && $0.item.end > item.start && $0.item.start < item.end }) {
                column += 1
            }
            assignments.append((item, column))
        }

        // Mutually overlapping programs share one column count.
        var totals: [String: Int] = [:]
        for assignment in assignments {
            let overlapping = assignments.filter { $0.item.end > assignment.item.start && $0.item.start < assignment.item.end }
            totals[assignment.item.id] = (overlapping.map(\.column).max() ?? 0) + 1
        }
        for assignment in assignments {
            let overlapping = assignments.filter { $0.item.end > assignment.item.start && $0.item.start < assignment.item.end }
            let maxTotal = overlapping.compactMap { totals[$0.item.id] }.max() ?? 1
            for other in overlapping where (totals[other.item.id] ?? 1) < maxTotal {
                totals[other.item.id] = maxTotal
            }
        }

        var slots: [String: Slot] = [:]
        for assignment in assignments {
            let item = assignment.item
            let points = CGFloat(item.end.timeIntervalSince(item.start) / 3600) * hourHeight
            var height = max(points, minHeight)
            if let next = assignments
                .filter({ $0.column == assignment.column && $0.item.start >= item.end })
                .map(\.item.start)
                .min() {
                let room = CGFloat(next.timeIntervalSince(item.start) / 3600) * hourHeight - gap
                height = min(height, max(room, 0))
            }
            slots[item.id] = Slot(column: assignment.column, totalColumns: totals[item.id] ?? 1, height: height)
        }
        return slots
    }
}
