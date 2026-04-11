//
//  RecordingProgressBar.swift
//  nextpvr-apple-client
//
//  Horizontal capsule progress bar for in-progress recordings.
//

import SwiftUI

struct RecordingProgressBar: View {
    let progress: Double // 0.0 to 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textTertiary.opacity(0.2))

                Capsule()
                    .fill(Theme.recording)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 4)
    }
}
