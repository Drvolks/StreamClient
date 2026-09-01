//
//  VideoAspectCorrection.swift
//  nextpvr-apple-client
//
//  Display geometry for the PixelBuffer renderer (issue #152).
//

import CoreGraphics

/// Geometry helper for the PixelBuffer renderer.
///
/// `vo=pixelbuffer` hands `AVSampleBufferDisplayLayer` a `CVPixelBuffer` sized
/// to the *coded* resolution with no sample-aspect metadata attached, so the
/// layer treats every frame as square-pixel. Anamorphic broadcast SD — e.g. a
/// 720x576 DVB-T feed with a 64:45 sample aspect and a 16:9 display aspect —
/// therefore renders horizontally squeezed. The Metal/OpenGL renderers are
/// unaffected because mpv applies the aspect itself.
///
/// The fix is to size the display layer to the stream's display aspect ratio
/// and let it fill that rect, instead of letting it fit the raw pixel grid.
enum VideoAspectCorrection {
    /// The largest rect with the given display aspect (width / height),
    /// centered inside `bounds`. Falls back to `bounds` when the aspect or the
    /// bounds are unusable.
    nonisolated static func fittedRect(displayAspect: Double, in bounds: CGRect) -> CGRect {
        guard displayAspect.isFinite, displayAspect > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }

        let boundsAspect = Double(bounds.width / bounds.height)
        var size = bounds.size
        if displayAspect > boundsAspect {
            size.height = bounds.width / CGFloat(displayAspect)
        } else if displayAspect < boundsAspect {
            size.width = bounds.height * CGFloat(displayAspect)
        }

        return CGRect(
            x: bounds.minX + (bounds.width - size.width) / 2,
            y: bounds.minY + (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
