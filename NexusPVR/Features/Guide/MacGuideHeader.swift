//
//  MacGuideHeader.swift
//  nextpvr-apple-client
//
//  The macOS guide header: page title, day stepper, "Now" pill, topics
//  legend and the refresh / filter controls. The search field sits in the
//  trailing slot (see `MacGuideHeaderMetrics`).
//

#if os(macOS)
import SwiftUI

struct MacGuideHeader: View {
    let title: String
    let selectedDate: Date
    let canGoToPreviousDay: Bool
    let isRefreshing: Bool
    let showsFilterButton: Bool
    let hasActiveFilters: Bool
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void
    let onNow: () -> Void
    let onTopics: () -> Void
    let onRefresh: () -> Void
    let onToggleFilters: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Guide")
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text(title)
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()

            // As the window narrows, shed the legend's label, the legend, then
            // the pill's "Now" label, before the title or day stepper give way.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { dayStepper; nowPill(showsLabel: true); topicsLegend(showsLabel: true) }
                HStack(spacing: 12) { dayStepper; nowPill(showsLabel: true); topicsLegend(showsLabel: false) }
                HStack(spacing: 12) { dayStepper; nowPill(showsLabel: true) }
                HStack(spacing: 12) { dayStepper; nowPill(showsLabel: false) }
                dayStepper
            }
            .layoutPriority(1)

            Spacer(minLength: Theme.spacingSM)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(MidnightOutlineButtonStyle())
            .disabled(isRefreshing)
            .help("Refresh guide")
            .accessibilityLabel("Refresh guide")
            .accessibilityIdentifier("guide-refresh-button")

            if showsFilterButton {
                Button(action: onToggleFilters) {
                    Image(systemName: hasActiveFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(hasActiveFilters ? MidnightPalette.accent : MidnightPalette.ink)
                }
                .buttonStyle(MidnightOutlineButtonStyle())
                .help("Filters")
                .accessibilityLabel("Filters")
            }

            // Slot for the global search field drawn by MacOSNavigation.
            Color.clear.frame(width: MacGuideHeaderMetrics.searchWidth, height: 1)
        }
        .padding(.horizontal, MacGuideHeaderMetrics.horizontalPadding)
        .frame(height: MacGuideHeaderMetrics.height)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }

    private var dayStepper: some View {
        HStack(spacing: 0) {
            stepperButton("chevron.left", label: "Previous day", isEnabled: canGoToPreviousDay, action: onPreviousDay)
            Rectangle().fill(MidnightPalette.line).frame(width: 1)
            Text(selectedDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.archivo(13, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.ink)
                .frame(minWidth: 108)
                .padding(.horizontal, 8)
            Rectangle().fill(MidnightPalette.line).frame(width: 1)
            stepperButton("chevron.right", label: "Next day", isEnabled: true, action: onNextDay)
        }
        .frame(height: MacGuideHeaderMetrics.searchHeight)
        .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
        .fixedSize()
    }

    private func stepperButton(_ systemImage: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(MidnightPalette.ink)
                .frame(width: 30, height: MacGuideHeaderMetrics.searchHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }

    private func nowPill(showsLabel: Bool) -> some View {
        Button(action: onNow) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 7) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .bold))
                    if showsLabel {
                        Text("Now")
                            .midnightKicker(10.5)
                    }
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.archivo(12.5, .extraBold))
                        .textCase(.uppercase)
                }
            }
            .foregroundStyle(MidnightPalette.fieldInk)
            .padding(.horizontal, 12)
            .frame(height: MacGuideHeaderMetrics.searchHeight)
            .background(MidnightGradients.field(colorScheme))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Jump to now")
        .accessibilityLabel("Jump to now")
        .accessibilityIdentifier("guide-now-button")
        .fixedSize()
    }

    private func topicsLegend(showsLabel: Bool) -> some View {
        Button(action: onTopics) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(MidnightPalette.topic)
                    .frame(width: 10, height: 10)
                if showsLabel {
                    Text("Your topics")
                        .midnightKicker(9.5)
                        .foregroundStyle(MidnightPalette.ink)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: MacGuideHeaderMetrics.searchHeight)
            .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Programs outlined in this color match your topics. Click to edit them.")
        .accessibilityLabel("Your topics")
        .fixedSize()
    }
}
#endif
