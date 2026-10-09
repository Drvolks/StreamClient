//
//  VODSeasonPicker.swift
//  DispatcherPVR
//
//  The row of seasons on a series page; one is listed at a time (#17)
//

#if DISPATCHERPVR
import SwiftUI

struct VODSeasonPicker: View {
    let seasons: [VODSeason]
    @Binding var selection: Int?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(seasons) { season in
                    chip(season)
                }
            }
            .padding(.vertical, verticalPadding)
        }
        #if os(tvOS)
        .focusSection()
        #endif
        .accessibilityIdentifier("vod-season-picker")
    }

    #if os(tvOS)
    private let spacing: CGFloat = 16
    private let verticalPadding: CGFloat = 12

    private func chip(_ season: VODSeason) -> some View {
        Button {
            selection = season.number
        } label: {
            TVSeasonChipLabel(title: season.title, isSelected: season.number == selection)
        }
        .buttonStyle(TVMidnightButtonStyle(focusScale: 1.04))
        .accessibilityIdentifier("vod-season-\(season.number)")
    }
    #else
    private let spacing: CGFloat = 8
    private let verticalPadding: CGFloat = 2

    private func chip(_ season: VODSeason) -> some View {
        let isSelected = season.number == selection
        return Button {
            selection = season.number
        } label: {
            Text(season.title)
                .font(.archivo(12.5, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(isSelected ? MidnightPalette.fieldInk : MidnightPalette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Rectangle().fill(MidnightGradients.field(colorScheme))
                    }
                }
                .overlay {
                    if !isSelected {
                        Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("vod-season-\(season.number)")
    }
    #endif
}
#endif
