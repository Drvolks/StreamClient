//
//  TVLogShareView.swift
//  PVR Client
//
//  Shares a log from Apple TV through a QR code and a temporary page.
//

#if os(tvOS)
import SwiftUI

/// Shows a QR code for the log's temporary page on the local network. The
/// page is served only while this screen is open.
struct TVLogShareView: View {
    let request: LogShareRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var server = LogShareServer()

    var body: some View {
        HStack(alignment: .center, spacing: 80) {
            qrPanel
                .frame(width: 460, height: 460)

            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                Text("Share \(request.title)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)

                switch server.status {
                case .starting:
                    Text("Preparing the page…")
                        .foregroundStyle(Theme.textSecondary)
                case .ready(let url):
                    Text("Scan the code with your iPhone or iPad camera, or open this address in a browser on a device connected to the same network:")
                        .foregroundStyle(Theme.textSecondary)
                    Text(url.absoluteString)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text("The page is available while this screen stays open. Credentials are removed from the log.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                case .failed(let reason):
                    Text("The log can't be shared right now: \(reason)")
                        .foregroundStyle(Theme.error)
                }

                Button("Done") { dismiss() }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MidnightGradients.ground(colorScheme).ignoresSafeArea())
        .onAppear { server.start(text: request.text, fileName: request.fileName) }
        .onDisappear { server.stop() }
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private var qrPanel: some View {
        switch server.status {
        case .ready(let url):
            QRCodeImage(text: url.absoluteString)
                .padding(24)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                .accessibilityLabel("QR code for \(url.absoluteString)")
        case .starting:
            ProgressView()
        case .failed:
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 120))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
#endif
