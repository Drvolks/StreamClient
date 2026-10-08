//
//  MacGuideHeaderMetrics.swift
//  nextpvr-apple-client
//
//  Shared geometry for the macOS guide header. The global search field is
//  drawn by `MacOSNavigation` (it owns the search state and its dropdown) in a
//  slot the header leaves free at its trailing edge, so both read these.
//

#if os(macOS)
import CoreGraphics

enum MacGuideHeaderMetrics {
    static let height: CGFloat = 68
    static let horizontalPadding: CGFloat = 20
    static let searchWidth: CGFloat = 210
    static let searchHeight: CGFloat = 32
}
#endif
