//
//  StreamSelectorView.swift
//  DispatcherPVR
//
//  Picker that switches which source an active channel streams from (#116)
//

#if DISPATCHERPVR
import SwiftUI

struct StreamSelectorView: View {
    let streams: [ChannelStream]
    let activeStreamId: Int?
    let isSwitching: Bool
    var accountNameLookup: ((Int) -> String?)? = nil
    let onSelect: (ChannelStream) -> Void

    #if os(tvOS)
    @State private var isExpanded = false
    #else
    @State private var isPickerPresented = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            Text("Active Stream")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            #if os(tvOS)
            tvOSPicker
            #else
            popoverPicker
            #endif
        }
    }

    private var activeStream: ChannelStream? {
        guard let activeStreamId else { return nil }
        return streams.first { $0.id == activeStreamId }
    }

    private var activeLabel: String {
        activeStream?.label(accountNameLookup: accountNameLookup) ?? "Unknown Stream"
    }

    private func label(for stream: ChannelStream) -> String {
        stream.label(accountNameLookup: accountNameLookup)
    }

    // MARK: - iOS / macOS

    #if !os(tvOS)
    /// A `Menu` would be laid out by the system at a fixed, narrow width, which
    /// truncates the long provider-qualified stream names. A popover sizes to
    /// its content, and adapts to a sheet on iPhone.
    private var popoverPicker: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Text(activeLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.tvScaled(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, Theme.spacingSM)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceHighlight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSwitching || streams.isEmpty)
        .accessibilityIdentifier("stats-stream-picker")
        .popover(isPresented: $isPickerPresented) {
            streamList
                .modifier(StreamPickerPresentation())
        }
    }

    private var streamList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(streams) { stream in
                    Button {
                        isPickerPresented = false
                        onSelect(stream)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .opacity(stream.id == activeStreamId ? 1 : 0)
                            Text(label(for: stream))
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.vertical, Theme.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if stream.id != streams.last?.id {
                        Divider()
                            .padding(.leading, Theme.spacingMD)
                    }
                }
            }
            .padding(.vertical, Theme.spacingSM)
        }
        // Popovers size to their content: give the list a comfortable width so
        // long "Stream name [Provider]" labels stay on one or two lines.
        .frame(idealWidth: 520, maxHeight: 460)
    }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
    private var tvOSPicker: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Text(activeLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if isSwitching {
                        ProgressView()
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                }
            }
            .buttonStyle(TVStreamOptionButtonStyle(isCurrent: false))
            .disabled(isSwitching || streams.isEmpty)

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    ForEach(streams) { stream in
                        Button {
                            isExpanded = false
                            onSelect(stream)
                        } label: {
                            HStack(spacing: Theme.spacingSM) {
                                Image(systemName: stream.id == activeStreamId ? "checkmark.circle.fill" : "circle")
                                Text(label(for: stream))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(TVStreamOptionButtonStyle(isCurrent: stream.id == activeStreamId))
                    }
                }
            }
        }
        .onExitCommand {
            if isExpanded { isExpanded = false }
        }
    }
    #endif
}

#if !os(tvOS)
/// Keeps the picker a popover where there's room (iPad, Mac) and turns it into
/// a detented sheet in compact widths (iPhone).
private struct StreamPickerPresentation: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) {
            content
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
        } else {
            content
        }
        #else
        content
        #endif
    }
}
#endif

#if os(tvOS)
struct TVStreamOptionButtonStyle: ButtonStyle {
    let isCurrent: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tvCaption)
            .foregroundStyle(isCurrent ? Theme.accent : Theme.textPrimary)
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isFocused ? Theme.surfaceHighlight : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                    .stroke(isFocused ? Theme.accent : Color.clear, lineWidth: isFocused ? 3 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
    }
}
#endif
#endif
