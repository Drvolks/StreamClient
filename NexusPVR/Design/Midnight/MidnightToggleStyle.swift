//
//  MidnightToggleStyle.swift
//  nextpvr-apple-client
//
//  A square ON/OFF switch: a 66×26 track holding a labelled 32pt knob.
//  It draws only the switch — Midnight toggles sit in a row that carries the
//  title — and keeps the toggle's label for VoiceOver.
//

#if !os(tvOS)
import SwiftUI

struct MidnightToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        MidnightSwitch(isOn: configuration.isOn, scheme: colorScheme)
            .onTapGesture {
                withAnimation(.easeInOut(duration: Theme.animationDuration)) {
                    configuration.isOn.toggle()
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}
#endif
