//
//  WatchProgressCircle.swift
//  nextpvr-apple-client
//
//  Circular watch-progress indicator with optional sport icon.
//

import SwiftUI

struct WatchProgressCircle: View {
    let progress: Double // 0.0 to 1.0
    let size: CGFloat
    var sport: Sport? = nil

    private var isFullyWatched: Bool {
        progress >= 0.9
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Theme.textTertiary.opacity(0.3), lineWidth: size * 0.12)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isFullyWatched ? Theme.success : Theme.accent,
                    style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center icon: sport icon if available, otherwise play/checkmark
            if let sport {
                Image(systemName: sport.sfSymbol)
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(isFullyWatched ? Theme.success : Theme.accent)
            } else if isFullyWatched {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(Theme.success)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(Theme.accent)
                    .offset(x: size * 0.04) // Slight offset to center play icon visually
            }
        }
        .frame(width: size, height: size)
    }
}
