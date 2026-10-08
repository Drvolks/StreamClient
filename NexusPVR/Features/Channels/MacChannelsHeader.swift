//
//  MacChannelsHeader.swift
//  nextpvr-apple-client
//
//  The macOS Channels header: page title, channel count, search, refresh
//  and filters.
//

#if os(macOS)
import SwiftUI

struct MacChannelsHeader: View {
    let title: String
    let channelCount: Int
    @Binding var searchText: String
    let isRefreshing: Bool
    let showsFilterButton: Bool
    let hasActiveFilters: Bool
    let onRefresh: () -> Void
    let onToggleFilters: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Channels")
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text(title)
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()

            Text("\(channelCount) channel\(channelCount == 1 ? "" : "s")")
                .midnightMeta(11.5)
                .foregroundStyle(MidnightPalette.inkSoft)
                .fixedSize()

            Spacer(minLength: Theme.spacingSM)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(MidnightOutlineButtonStyle())
            .disabled(isRefreshing)
            .help("Refresh channels")
            .accessibilityLabel("Refresh channels")
            .accessibilityIdentifier("channels-refresh-button")

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

            searchField
        }
        .padding(.horizontal, MacGuideHeaderMetrics.horizontalPadding)
        .frame(height: MacGuideHeaderMetrics.height)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MidnightPalette.inkFaint)
            TextField("Search channels", text: $searchText)
                .font(.archivo(12.5))
                .textFieldStyle(.plain)
                .accessibilityIdentifier("channels-view-field")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MidnightPalette.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: MacGuideHeaderMetrics.searchWidth, height: MacGuideHeaderMetrics.searchHeight)
        // Closure form: a plain colour background would bleed up into the
        // title bar's safe area.
        .background { Rectangle().fill(MidnightPalette.inputBg) }
        .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
    }
}
#endif
