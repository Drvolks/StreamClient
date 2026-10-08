//
//  ArchivoFont.swift
//  nextpvr-apple-client
//
//  Archivo (SIL OFL 1.1, see Resources/Fonts/Archivo-OFL.txt), the Midnight
//  typeface. The bundled file is the variable font; each weight is an
//  instance on its `wght` axis. The descriptor is read straight from the
//  file, so no Info.plist font registration is needed on any platform.
//

import CoreText
import SwiftUI

enum ArchivoFont {
    /// Four-char code of the variable font's weight axis.
    private static let weightAxis = 0x77676874 // 'wght'

    private static let baseDescriptor: CTFontDescriptor? = {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "Archivo-VF", withExtension: "ttf")
                ?? bundle.url(forResource: "Archivo-VF", withExtension: "ttf", subdirectory: "Fonts"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        else { return nil }
        return descriptors.first
    }()

    /// Archivo at `size` and `weight`, or the system font at the matching
    /// weight if the bundled file is missing.
    static func font(size: CGFloat, weight: ArchivoWeight) -> Font {
        guard let baseDescriptor else {
            return .system(size: size, weight: weight.systemWeight)
        }
        let attributes = [kCTFontVariationAttribute: [weightAxis: weight.rawValue]] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(baseDescriptor, attributes)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

extension Font {
    static func archivo(_ size: CGFloat, _ weight: ArchivoWeight = .regular) -> Font {
        ArchivoFont.font(size: size, weight: weight)
    }
}
