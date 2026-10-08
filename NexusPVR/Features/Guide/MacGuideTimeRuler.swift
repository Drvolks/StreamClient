//
//  MacGuideTimeRuler.swift
//  nextpvr-apple-client
//
//  The sticky time ruler over the macOS guide grid: a tick every 30 minutes
//  and the now-line. Its "Channel" corner stays pinned like the channel
//  column.
//

#if os(macOS)
import SwiftUI

struct MacGuideTimeRuler: View {
    static let height: CGFloat = 30

    let timelineStart: Date
    let hourCount: Int
    let hourWidth: CGFloat
    let channelWidth: CGFloat
    /// Horizontal scroll offset, used to keep the corner cell pinned.
    let horizontalOffset: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: channelWidth)
                ForEach(0..<(hourCount * 2), id: \.self) { index in
                    tick(index: index)
                }
            }

            TimelineView(.everyMinute) { context in
                if let offset = nowOffset(at: context.date) {
                    Rectangle()
                        .fill(MidnightPalette.accent)
                        .frame(width: 2, height: Self.height)
                        .offset(x: channelWidth + offset - 1)
                }
            }

            Text("Channel")
                .midnightKicker(9.5)
                .foregroundStyle(MidnightPalette.inkSoft)
                .padding(.leading, 12)
                .frame(width: channelWidth, height: Self.height, alignment: .leading)
                .background(MidnightPalette.railHead)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(MidnightPalette.line).frame(width: 1)
                }
                .offset(x: horizontalOffset)
                .zIndex(1)
        }
        .frame(height: Self.height)
        .background(MidnightPalette.railHead)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }

    private func tick(index: Int) -> some View {
        let time = timelineStart.addingTimeInterval(Double(index) * 1800)
        let isLast = index == hourCount * 2 - 1
        return HStack(spacing: 0) {
            Rectangle().fill(MidnightPalette.line).frame(width: 1)
            // The last tick keeps its rule but drops the label, which would
            // otherwise run past the end of the timeline.
            if !isLast {
                Text(time, format: .dateTime.hour().minute())
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
                    .padding(.leading, 7)
            }
            Spacer(minLength: 0)
        }
        .frame(width: hourWidth / 2, height: Self.height)
    }

    private func nowOffset(at now: Date) -> CGFloat? {
        let elapsed = now.timeIntervalSince(timelineStart)
        guard elapsed >= 0, elapsed < Double(hourCount) * 3600 else { return nil }
        return CGFloat(elapsed / 3600) * hourWidth
    }
}
#endif
