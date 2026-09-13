//
//  CustomHostSettingsRows.swift
//  PVR Client
//
//  Custom host field and mode picker for the Settings server section (#165).
//

#if !os(tvOS)
import SwiftUI

/// Edits the optional custom host in place, without unlinking the server.
///
/// Changes are applied when the field loses focus or Return is pressed, and
/// immediately for the mode picker. Both addresses reach the same server, so the
/// session is kept (`updateCustomHost(_:mode:)`).
struct CustomHostSettingsRows: View {
    @EnvironmentObject private var client: PVRClient

    @State private var hostText = ""
    @State private var mode: CustomHostMode = .cellularOnly
    @State private var validationError: String?
    @State private var hasLoaded = false
    @FocusState private var isHostFocused: Bool

    var body: some View {
        HStack {
            Text("Custom Host")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            TextField("https://pvr.example.com", text: $hostText)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                #endif
                .autocorrectionDisabled()
                .focused($isHostFocused)
                .onSubmit { apply() }
                .accessibilityIdentifier("custom-host-field")
        }

        if let validationError {
            Text(validationError)
                .font(.caption)
                .foregroundStyle(Theme.error)
        }

        Picker("Use Custom Host", selection: $mode) {
            ForEach(CustomHostMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .disabled(!hasHostText)
        .accessibilityIdentifier("custom-host-mode-picker")

        Text(description)
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .onAppear(perform: load)
            .onChange(of: isHostFocused) { focused in
                if !focused { apply() }
            }
            .onChange(of: mode) { _ in
                apply()
            }
    }

    private var hasHostText: Bool {
        !hostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var description: String {
        guard hasHostText else {
            return "Optional second address for this server, such as its public URL. "
                + "Edit it at any time without unlinking."
        }
        switch mode {
        case .cellularOnly:
            #if os(macOS)
            return "Used while this Mac is on an iPhone hotspot; the address above is used on "
                + "other networks. Applies to the next request or stream."
            #else
            return "Used on cellular or a personal hotspot; the address above is used on Wi-Fi "
                + "and wired networks. Applies to the next request or stream."
            #endif
        case .always:
            return "Every request and stream goes through the custom host."
        }
    }

    private func load() {
        guard !hasLoaded else { return }
        hostText = client.config.customHost
        mode = client.config.customHostMode
        hasLoaded = true
    }

    private func apply() {
        guard hasLoaded else { return }
        let trimmed = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = ServerConfig.customHostValidationError(trimmed) {
            // Keep the last working address: a broken one would silently break
            // every request on the route it covers.
            validationError = error
            return
        }
        validationError = nil
        hostText = trimmed

        let current = client.config
        guard trimmed != current.customHost || mode != current.customHostMode else { return }
        client.updateCustomHost(trimmed, mode: mode)
        client.config.save()
    }
}
#endif
