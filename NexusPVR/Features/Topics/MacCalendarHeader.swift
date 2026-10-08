//
//  MacCalendarHeader.swift
//  nextpvr-apple-client
//
//  The macOS Calendar header (Midnight): the visible range, a day / week
//  stepper, a "Today" pill, the topic filter and the Day / Week switch.
//

#if os(macOS)
import SwiftUI

struct MacCalendarHeader: View {
    let title: String
    let canGoBack: Bool
    @Binding var viewMode: CalendarView.ViewMode
    @Binding var selectedKeyword: String
    let keywordOptions: [(label: String, value: String)]
    let onBack: () -> Void
    let onForward: () -> Void
    let onToday: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Calendar")
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text(title)
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()

            stepper

            Button(action: onToday) {
                Text("Today")
                    .midnightKicker(10.5)
                    .foregroundStyle(MidnightPalette.fieldInk)
                    .padding(.horizontal, 12)
                    .frame(height: MacGuideHeaderMetrics.searchHeight)
                    // Closure form: a gradient background would bleed up into
                    // the title bar's safe area.
                    .background { Rectangle().fill(MidnightGradients.field(colorScheme)) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityIdentifier("calendar-today-button")

            Spacer(minLength: Theme.spacingSM)

            MidnightPicker(title: "Topic", selection: $selectedKeyword, options: keywordOptions)

            modeSwitch
        }
        .padding(.horizontal, MacGuideHeaderMetrics.horizontalPadding)
        .frame(height: MacGuideHeaderMetrics.height)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepperButton("chevron.left", label: viewMode == .day ? "Previous day" : "Previous week", isEnabled: canGoBack, action: onBack)
            Rectangle().fill(MidnightPalette.line).frame(width: 1)
            stepperButton("chevron.right", label: viewMode == .day ? "Next day" : "Next week", isEnabled: true, action: onForward)
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

    /// Square two-way switch; the current mode sits on the accent field.
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(CalendarView.ViewMode.allCases, id: \.self) { mode in
                let isSelected = viewMode == mode
                Button {
                    viewMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.archivo(12.5, .extraBold))
                        .textCase(.uppercase)
                        .foregroundStyle(isSelected ? MidnightPalette.fieldInk : MidnightPalette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: MacGuideHeaderMetrics.searchHeight)
                        .background {
                            if isSelected {
                                Rectangle().fill(MidnightGradients.field(colorScheme))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
        .fixedSize()
    }
}
#endif
