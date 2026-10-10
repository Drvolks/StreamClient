//
//  MidnightSearchField.swift
//  nextpvr-apple-client
//
//  A square search field (Midnight, macOS and iOS): magnifying glass, text,
//  and a clear button once something is typed.
//

#if !os(tvOS)
import SwiftUI

struct MidnightSearchField: View {
    let prompt: String
    @Binding var text: String
    /// Nil stretches to the available width.
    var width: CGFloat?
    var height: CGFloat = 30
    let identifier: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MidnightPalette.inkFaint)
            TextField(prompt, text: $text)
                .font(.archivo(12.5))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MidnightPalette.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        // Closure form: a plain colour background would bleed up into the
        // title bar's safe area.
        .background { MidnightControlShape().fill(MidnightPalette.inputBg) }
        .overlay { MidnightControlShape().strokeBorder(MidnightPalette.line, lineWidth: 1) }
    }
}
#endif
