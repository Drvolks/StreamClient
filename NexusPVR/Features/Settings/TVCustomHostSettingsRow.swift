//
//  TVCustomHostSettingsRow.swift
//  nextpvr-apple-client
//
//  Settings › Server on Apple TV: the optional custom host (#165).
//

#if os(tvOS)
import SwiftUI

/// Edits the custom host on Apple TV, without unlinking the server.
///
/// There is no mode picker: Apple TV has no cellular, so a custom host entered
/// here is used for every request ("Always"). The host and its mode sync with
/// the other devices through iCloud; when one of them chose another mode, the
/// TV keeps the server address and the row is disabled.
struct TVCustomHostSettingsRow: View {
    @EnvironmentObject private var client: PVRClient

    @State private var hostText = ""
    @State private var requestKeyboard = false
    @State private var validationError: String?
    /// The client's config isn't published, so the row keeps its own copy,
    /// refreshed on appear and after each change.
    @State private var customHost = ""
    @State private var customHostMode: CustomHostMode = .cellularOnly

    var body: some View {
        Button {
            hostText = customHost
            validationError = nil
            requestKeyboard = true
        } label: {
            TVSettingsRowLabel(title: "Custom Host", subtitle: subtitle, value: value)
        }
        .buttonStyle(TVMidnightButtonStyle())
        .disabled(usesOtherMode)
        .opacity(usesOtherMode ? 0.45 : 1)
        .accessibilityIdentifier("custom-host-field")
        .onAppear(perform: load)
        .background(
            TVKeyboardField(
                text: $hostText,
                placeholder: "https://pvr.example.com",
                requestFocus: $requestKeyboard,
                returnKeyType: .done,
                isURL: true,
                onFocusChange: { editing in
                    // Done (or leaving the keyboard) applies what was typed.
                    guard !editing else { return }
                    requestKeyboard = false
                    apply()
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private var hasCustomHost: Bool { !customHost.isEmpty }

    /// A host set on another device for a mode Apple TV doesn't use.
    private var usesOtherMode: Bool {
        hasCustomHost && customHostMode != .always
    }

    private var value: String {
        hasCustomHost ? customHost : "None"
    }

    private var subtitle: String {
        if let validationError { return validationError }
        if usesOtherMode {
            return "Set to “\(customHostMode.label)” on another device, so Apple TV uses the "
                + "server address. Choose Always there to use it here."
        }
        if hasCustomHost {
            return "Every request and stream goes through this address."
        }
        return "Optional second address for this server, such as its public URL."
    }

    private func apply() {
        let trimmed = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = ServerConfig.customHostValidationError(trimmed) {
            // Keep the last working address: a broken one would break every request.
            validationError = error
            return
        }
        validationError = nil

        let current = client.config
        guard trimmed != current.customHost else { return }
        // A host entered here is always used; clearing it leaves the mode alone.
        let mode: CustomHostMode = trimmed.isEmpty ? current.customHostMode : .always
        client.updateCustomHost(trimmed, mode: mode, wiFiSSID: nil)
        client.config.save()
        load()
    }

    private func load() {
        customHost = client.config.customHost.trimmingCharacters(in: .whitespacesAndNewlines)
        customHostMode = client.config.customHostMode
    }
}
#endif
