//
//  TVGuideTimeRuler.swift
//  nextpvr-apple-client
//
//  The time ruler over the tvOS guide grid (Midnight): a tick every 30
//  minutes across the visible window, and the now-line.
//

#if os(tvOS)
import SwiftUI

struct TVGuideTimeRuler: View {
    static var height: CGFloat { Theme.scaledMetric(40) }

    let windowStart: Date
    let windowMinutes: Double
    let channelWidth: CGFloat
    let gridWidth: CGFloat

    var body: some View {
        let pxPerMinute = gridWidth / windowMinutes
        let firstTick = Self.firstHalfHour(atOrAfter: windowStart)
        let ticks = stride(from: 0.0, to: windowMinutes, by: 30).compactMap { offset -> Date? in
            let tick = firstTick.addingTimeInterval(offset * 60)
            return tick < windowStart.addingTimeInterval(windowMinutes * 60) ? tick : nil
        }
        return ZStack(alignment: .leading) {
            ForEach(ticks, id: \.self) { tick in
                let x = channelWidth + CGFloat(tick.timeIntervalSince(windowStart) / 60) * pxPerMinute
                HStack(spacing: 0) {
                    Rectangle().fill(MidnightPalette.line).frame(width: 1)
                    Text(GuideCellTimeLabel.time(tick))
                        .midnightMeta(Theme.scaledFont(15))
                        .foregroundStyle(MidnightPalette.inkSoft)
                        .padding(.leading, 8)
                }
                .offset(x: x)
            }
            TimelineView(.everyMinute) { context in
                let minutes = context.date.timeIntervalSince(windowStart) / 60
                if minutes >= 0, minutes < windowMinutes {
                    Rectangle()
                        .fill(MidnightPalette.accent)
                        .frame(width: 3, height: Self.height)
                        .offset(x: channelWidth + CGFloat(minutes) * pxPerMinute - 1)
                }
            }
            Text("Channel")
                .midnightKicker(Theme.scaledFont(13))
                .foregroundStyle(MidnightPalette.inkSoft)
                .padding(.leading, 18)
                .frame(width: channelWidth, height: Self.height, alignment: .leading)
                .background(MidnightPalette.railHead)
        }
        .frame(height: Self.height, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MidnightPalette.railHead)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
        .clipped()
    }

    private static func firstHalfHour(atOrAfter date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let toNext = (30 - minute % 30) % 30
        let rounded = calendar.date(byAdding: .minute, value: toNext, to: date) ?? date
        return rounded.addingTimeInterval(-Double(second))
    }
}
#endif
