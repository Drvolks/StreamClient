//
//  TVMidnightButtonStyle.swift
//  nextpvr-apple-client
//
//  tvOS button style for Midnight rows, cards and header buttons. It
//  replaces the system focus platter with a slight lift; the label draws
//  its own focused look by reading `\.isFocused` (inverted plate, accent
//  bar or frame), so each kind of control keeps its Midnight treatment.
//

#if os(tvOS)
import SwiftUI

struct TVMidnightButtonStyle: ButtonStyle {
    var focusScale: CGFloat = 1.01

    func makeBody(configuration: Configuration) -> some View {
        TVMidnightButtonBody(focusScale: focusScale, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}
#endif
