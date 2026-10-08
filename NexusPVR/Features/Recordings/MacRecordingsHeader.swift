//
//  MacRecordingsHeader.swift
//  nextpvr-apple-client
//
//  The macOS recordings header: page title, how many recordings and how
//  much space they take, the topics legend and search.
//

#if os(macOS)
import SwiftUI

struct MacRecordingsHeader: View {
    let title: String
    let recordingCount: Int
    let totalBytes: Int64
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Recordings")
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text(title)
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()

            Text(readout)
                .midnightKicker(9.5)
                .foregroundStyle(MidnightPalette.inkSoft)
                .lineLimit(1)
                .fixedSize()

            HStack(spacing: 7) {
                Rectangle()
                    .fill(MidnightPalette.topic)
                    .frame(width: 10, height: 10)
                Text("Your topics")
                    .midnightKicker(9.5)
                    .foregroundStyle(MidnightPalette.ink)
            }
            .padding(.horizontal, 10)
            .frame(height: MacGuideHeaderMetrics.searchHeight)
            .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
            .fixedSize()
            .help("Recordings outlined in this color match your topics.")

            Spacer(minLength: Theme.spacingSM)

            searchField
        }
        .padding(.horizontal, MacGuideHeaderMetrics.horizontalPadding)
        .frame(height: MacGuideHeaderMetrics.height)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }

    private var readout: String {
        let count = "\(recordingCount) recording\(recordingCount == 1 ? "" : "s")"
        guard totalBytes > 0 else { return count }
        return "\(count) · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MidnightPalette.inkFaint)
            TextField("Search recordings", text: $searchText)
                .font(.archivo(12.5))
                .textFieldStyle(.plain)
                .accessibilityIdentifier("recordings-search-field")
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
