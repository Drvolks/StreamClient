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
        MidnightSectionHeader(title: section.title, meta: meta)
    }

    private var meta: String {
        let count = section.recordings.count
        let recordings = "\(count) recording\(count == 1 ? "" : "s")"
        guard section.totalBytes > 0 else { return recordings }
        return "\(recordings) · \(ByteCountFormatter.string(fromByteCount: section.totalBytes, countStyle: .file))"
    }
}
#endif
