//
//  PlaybackLogLineView.swift
//  PVR Client
//
//  One line of a playback session log.
//

import SwiftUI

struct PlaybackLogLineView: View {
    let line: PlaybackLogLine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(line.timestamp, format: .dateTime.hour().minute().second())
                    .foregroundStyle(Theme.textTertiary)
                Text(line.level.tag)
                    .foregroundStyle(levelColor)
                    .fontWeight(.semibold)
                if line.repeatCount > 1 {
                    Text("×\(line.repeatCount)")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .font(.caption2)
            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(line.level.isProblem ? Theme.error : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var levelColor: Color {
        switch line.level {
        case .fatal, .error: return Theme.error
        case .warn: return Theme.warning
        case .event: return Theme.accent
        default: return Theme.textTertiary
        }
    }
}
