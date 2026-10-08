//
//  MacRecordingSectionHeader.swift
//  nextpvr-apple-client
//
//  Heads a series (or the one-off recordings) in the macOS list.
//

#if os(macOS)
import SwiftUI

struct MacRecordingSectionHeader: View {
    let section: RecordingSection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(section.title)
                .font(.archivo(17, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(1)
            Text(meta)
                .midnightMeta(11)
                .foregroundStyle(MidnightPalette.inkSoft)
            Spacer()
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 2)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var meta: String {
        let count = section.recordings.count
        let recordings = "\(count) recording\(count == 1 ? "" : "s")"
        guard section.totalBytes > 0 else { return recordings }
        return "\(recordings) · \(ByteCountFormatter.string(fromByteCount: section.totalBytes, countStyle: .file))"
    }
}
#endif
