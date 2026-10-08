//
//  ArchivoWeight.swift
//  nextpvr-apple-client
//
//  The Archivo weights the Midnight design uses, as values on the variable
//  font's `wght` axis.
//

import SwiftUI

enum ArchivoWeight: CGFloat, Sendable {
    case regular = 400
    case semibold = 600
    case extraBold = 800

    /// The closest system weight, used when the bundled font is missing.
    var systemWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .semibold: .semibold
        case .extraBold: .heavy
        }
    }
}
