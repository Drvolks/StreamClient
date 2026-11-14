//
//  QRCodeImage.swift
//  PVR Client
//
//  A QR code for a string, drawn with Core Image.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.makeImage(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.textTertiary)
        }
    }

    static func makeImage(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
