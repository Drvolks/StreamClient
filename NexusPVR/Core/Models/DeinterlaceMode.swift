//
//  DeinterlaceMode.swift
//  nextpvr-apple-client
//
//  Convenience typealias for the deinterlacing mode enum (#142). The
//  canonical definition lives inside `UserPreferences` so the tvOS Top
//  Shelf extension (which only shares `UserPreferences.swift` from the
//  Core/Models folder) keeps compiling without needing this sibling file
//  to also be in its membership list.
//

typealias DeinterlaceMode = UserPreferences.DeinterlaceMode

extension DeinterlaceMode {
    /// Value passed to mpv's `deinterlace` option.
    ///
    /// - `auto` lets mpv deinterlace only streams the demuxer/decoder flags as
    ///   interlaced, so progressive channels are passed through untouched.
    /// - `on` forces the filter on, for broadcasts that are interlaced but
    ///   carry no (or wrong) interlacing flags.
    nonisolated var mpvValue: String {
        switch self {
        case .off: return "no"
        case .auto: return "auto"
        case .on: return "yes"
        }
    }

    /// SF Symbol shown next to the option in Settings.
    nonisolated var icon: String {
        switch self {
        case .off: return "rectangle.slash"
        case .auto: return "wand.and.stars"
        case .on: return "rectangle.on.rectangle"
        }
    }

    /// Explanatory text shown under the picker in Settings.
    nonisolated var summary: String {
        switch self {
        case .off:
            return "Interlaced broadcasts (1080i50, 576i50) may show combing during motion."
        case .auto:
            return "Deinterlaces only streams flagged as interlaced; progressive channels are untouched."
        case .on:
            return "Always deinterlaces. Use only if interlaced channels are not detected automatically."
        }
    }
}
