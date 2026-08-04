//
//  StreamPreparingOverlay.swift
//  PVR Client
//
//  Feedback shown while a stream URL is being resolved, before the player opens.
//

import SwiftUI

/// Covers the gap between tapping a channel and the player appearing. On NextPVR
/// live TV that gap includes starting the server-side timeshift buffer and waiting
/// for it to fill, so it can run to several seconds.
struct StreamPreparingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: Theme.spacingMD) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)

                Text("Starting stream…")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(Theme.spacingLG)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
        }
        // Purely informational — must not swallow taps meant for the UI beneath.
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityIdentifier("stream-preparing-overlay")
    }
}

private struct StreamPreparingOverlayModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .overlay {
                if appState.isPreparingStream {
                    StreamPreparingOverlay()
                }
            }
            .animation(Theme.springAnimation, value: appState.isPreparingStream)
    }
}

extension View {
    /// Shows the "starting stream" indicator over this view while a stream URL is
    /// being resolved.
    ///
    /// Needed on presented views (sheets, popovers, tvOS detail screens) as well as
    /// on the app root: a sheet renders in its own presentation layer, so the root's
    /// overlay is behind it and the spinner would be invisible to someone who
    /// started playback from the sheet.
    func streamPreparingOverlay() -> some View {
        modifier(StreamPreparingOverlayModifier())
    }
}
