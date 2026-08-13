//
//  Theme.swift
//  nextpvr-apple-client
//
//  UHF-inspired design system
//

import SwiftUI

// MARK: - Colors

extension Color {
    nonisolated init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark) : UIColor(light)
        })
        #endif
    }

    nonisolated init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum Theme {
    #if os(tvOS)
    // MARK: - UI Font Size (#107)

    /// The active tvOS UI font size. Every scaled font and metric below
    /// reads this, so the whole app follows the Settings picker without
    /// each call site having to thread the value through.
    ///
    /// Written once at launch and again whenever preferences change (see
    /// `AppEntry` / `applyUIFontSize`). It is a plain global rather than
    /// an environment value because `Font` extensions are static — the
    /// same reason `UserPreferences.demoStore` is one. Reads and writes
    /// both happen on the main actor in practice; SwiftUI never renders
    /// off it.
    nonisolated(unsafe) static var uiFontSize: UIFontSize = .medium

    /// Scales a baseline font size by the active preference.
    static func scaledFont(_ size: CGFloat) -> CGFloat {
        size * CGFloat(uiFontSize.scale)
    }

    /// Scales a baseline font size by the sidebar's own, steeper curve —
    /// see `UIFontSize.sidebarScale`.
    static func scaledSidebarFont(_ size: CGFloat) -> CGFloat {
        size * CGFloat(uiFontSize.sidebarScale)
    }

    /// Scales a baseline layout metric (row height, icon size) so it can
    /// still hold the scaled text it wraps.
    static func scaledMetric(_ value: CGFloat) -> CGFloat {
        value * CGFloat(uiFontSize.layoutScale)
    }

    /// Sidebar variant of `scaledMetric`, for the menu's own columns and
    /// indents so they track the sidebar's steeper font curve.
    static func scaledSidebarMetric(_ value: CGFloat) -> CGFloat {
        value * CGFloat(uiFontSize.sidebarScale)
    }
    #endif

    // MARK: - Primary Colors

    static let accent = Brand.accent
    static let accentSecondary = Brand.accentSecondary

    // MARK: - Background Colors

    static let background = Brand.background
    static let surface = Brand.surface
    static let surfaceElevated = Brand.surfaceElevated
    static let surfaceHighlight = Brand.surfaceHighlight
    static let channelColumnBackground = Brand.channelColumnBackground

    // MARK: - Text Colors

    static let textPrimary = Brand.textPrimary
    static let textSecondary = Brand.textSecondary
    static let textTertiary = Brand.textTertiary

    // MARK: - Status Colors

    static let success = Brand.success
    static let warning = Brand.warning
    static let error = Brand.error
    static let recording = Brand.recording

    // MARK: - Guide Colors

    static let guideNowPlaying = Brand.guideNowPlaying

    // MARK: - Focus Colors (tvOS)

    static let focusBorder = Color(light: Color(hex: "#1c1c1e"), dark: .white)
    static let focusShadow = Color(light: Color(hex: "#1c1c1e").opacity(0.4), dark: Color.white.opacity(0.5))
    static let guidePast = Brand.surface.opacity(0.5)
    static let guideScheduled = Brand.accent.opacity(0.3)

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: - Corner Radius

    static let cornerRadiusSM: CGFloat = 8
    static let cornerRadiusMD: CGFloat = 12
    static let cornerRadiusLG: CGFloat = 20

    // MARK: - Animation

    static let animationDuration: Double = 0.25
    static let springAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)

    // MARK: - Platform-specific sizing

    #if os(tvOS)
    // Scale with the user's font size so bigger text doesn't clip inside
    // rows and cells (#107). `hourColumnWidth` is intentionally fixed: it
    // maps screen width to a time span, so scaling it would just show less
    // of the schedule.
    static var cellHeight: CGFloat { scaledMetric(100) }
    static var channelColumnWidth: CGFloat { scaledMetric(200) }
    static let hourColumnWidth: CGFloat = 600
    static var iconSize: CGFloat { scaledMetric(80) }
    #else
    static let cellHeight: CGFloat = 60
    static let channelColumnWidth: CGFloat = 72
    static let hourColumnWidth: CGFloat = 300
    static let iconSize: CGFloat = 48
    #endif
}

// MARK: - New Badge

struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.success)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(isSelected ? Theme.surfaceHighlight : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
    }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingMD)
            .background(isEnabled ? Theme.accent : Theme.textTertiary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
            .scaleEffect(configuration.isPressed ? 0.95 : isFocused ? 1.05 : 1)
            .shadow(color: isFocused ? Theme.accent.opacity(0.6) : .clear, radius: isFocused ? 12 : 0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingMD)
            .background(Theme.surfaceElevated)
            .foregroundStyle(Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#if os(tvOS)
struct TVNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVNavigationFocusWrapper {
            configuration.label
        }
    }
}

private struct TVNavigationFocusWrapper<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .foregroundStyle(isFocused ? Color(white: 0.1) : Theme.textSecondary)
            .background(isFocused ? Color.white : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

/// Button style for guide grid cells with prominent focus indication
struct TVGuideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVGuideFocusWrapper {
            configuration.label
        }
    }
}

/// Wrapper view to properly detect focus state on tvOS
private struct TVGuideFocusWrapper<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                        .strokeBorder(Theme.focusBorder, lineWidth: 4)
                }
            }
            .shadow(color: isFocused ? Theme.focusShadow : .clear, radius: 15)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

/// Button style for channel icons in the guide with prominent focus indication
struct TVChannelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVChannelFocusWrapper {
            configuration.label
        }
    }
}

/// Wrapper view to properly detect focus state on tvOS for channel buttons
private struct TVChannelFocusWrapper<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                        .strokeBorder(Theme.focusBorder, lineWidth: 4)
                }
            }
            .shadow(color: isFocused ? Theme.focusShadow : .clear, radius: 15)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

struct TVTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    @State private var isEditing = false
    @State private var editingText = ""

    var body: some View {
        Button {
            editingText = text
            isEditing = true
        } label: {
            HStack {
                Text(text.isEmpty ? placeholder : text)
                    .foregroundStyle(text.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                Spacer()
                Image(systemName: "pencil")
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        }
        .buttonStyle(.card)
        .alert(placeholder, isPresented: $isEditing) {
            TextField(placeholder, text: $editingText)
            Button("OK") {
                text = editingText
                onSubmit?()
            }
            Button("Cancel", role: .cancel, action: {})
        }
    }
}

struct TVNumberField: View {
    let placeholder: String
    @Binding var value: Int
    @State private var isEditing = false
    @State private var textValue: String = ""

    var body: some View {
        Button {
            textValue = value == 0 ? "" : String(value)
            isEditing = true
        } label: {
            HStack {
                Text(value == 0 ? placeholder : String(value))
                    .foregroundStyle(value == 0 ? Theme.textTertiary : Theme.textPrimary)
                Spacer()
                Image(systemName: "pencil")
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        }
        .buttonStyle(.card)
        .alert(placeholder, isPresented: $isEditing) {
            TextField(placeholder, text: $textValue)
                .keyboardType(.numberPad)
            Button("OK") {
                if let intValue = Int(textValue) {
                    value = intValue
                }
            }
            Button("Cancel", role: .cancel, action: {})
        }
    }
}

struct TVSettingsSection<Content: View, StatusView: View>: View {
    let title: String
    let icon: String
    var footer: String? = nil
    var statusView: StatusView?
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String,
        footer: String? = nil,
        @ViewBuilder statusView: () -> StatusView,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.footer = footer
        self.statusView = statusView()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let statusView {
                    statusView
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.top, Theme.spacingMD)

            // Content
            content
                .padding(.horizontal, Theme.spacingMD)
                .padding(.bottom, Theme.spacingMD)

            // Footer
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.bottom, Theme.spacingSM)
            }
        }
    }
}

extension TVSettingsSection where StatusView == EmptyView {
    init(
        title: String,
        icon: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.footer = footer
        self.statusView = nil
        self.content = content()
    }
}
#endif

extension View {
    func cardStyle(isSelected: Bool = false) -> some View {
        modifier(CardStyle(isSelected: isSelected))
    }

    @ViewBuilder
    func tvOSFocusableEmptyState() -> some View {
        #if os(tvOS)
        modifier(TVOSFocusableEmptyStateModifier())
        #else
        self
        #endif
    }
}

#if os(tvOS)
private struct TVOSFocusableEmptyStateModifier: ViewModifier {
    func body(content: Content) -> some View {
        Button(action: {}) {
            content
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .focusable(true)
    }
}
#endif

// MARK: - Typography

extension Font {
    static let displayLarge = Font.system(size: 34, weight: .bold)
    static let displayMedium = Font.system(size: 28, weight: .bold)
    static let headline = Font.system(size: 20, weight: .semibold)
    static let subheadline = Font.system(size: 16, weight: .medium)
    static let body = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 14, weight: .regular)
    static let footnote = Font.system(size: 12, weight: .regular)

    #if os(tvOS)
    // Computed rather than stored so they follow the user's UI font size
    // (#107) without every call site having to pass it. The baseline
    // numbers are unchanged, and `.medium` scales by 1.0, so the default
    // build renders exactly as it did before the setting existed.
    static var tvTitle: Font { .system(size: Theme.scaledFont(48), weight: .bold) }
    static var tvHeadline: Font { .system(size: Theme.scaledFont(32), weight: .semibold) }
    static var tvBody: Font { .system(size: Theme.scaledFont(28), weight: .regular) }
    static var tvCaption: Font { .system(size: Theme.scaledFont(24), weight: .regular) }

    // Sidebar fonts use their own steeper scale — see `UIFontSize.sidebarScale`.
    //
    // The baselines are deliberately much smaller than the pre-#107
    // build's 30/32pt: with a Text Size setting in place the menu no
    // longer has to be sized for the worst-case viewing distance, and the
    // roomier default crowded out long labels. Users who want a bigger
    // menu pick Large or X-Large, which the sidebar caps at 1.15x.
    static var tvSidebar: Font { .system(size: Theme.scaledSidebarFont(23), weight: .regular) }
    static var tvSidebarCompact: Font { .system(size: Theme.scaledSidebarFont(24), weight: .regular) }
    static var tvSidebarRecordingIcon: Font { .system(size: Theme.scaledSidebarFont(24), weight: .bold) }
    static var tvSidebarSection: Font { .system(size: Theme.scaledSidebarFont(24), weight: .regular) }

    /// SF Symbol size for sidebar rows and section headers. Sized just
    /// under the label baseline because symbols read optically larger than
    /// text at the same point size. Previously `.title3`, which is a
    /// semantic style and so ignored the sidebar sizing entirely — the
    /// icons stayed put while the labels shrank.
    static var tvSidebarIcon: Font { .system(size: Theme.scaledSidebarFont(22), weight: .regular) }

    /// Scaled replacement for `Font.system(size:weight:)` at tvOS-only call
    /// sites that don't map onto one of the named tv* fonts above. Keeping
    /// the baseline number at the call site means the diff stays readable
    /// and the design intent (this label is 17pt, that one is 24pt) is
    /// preserved. (#107)
    static func tvScaled(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: Theme.scaledFont(size), weight: weight)
    }

    /// Sidebar-scaled variant of `tvScaled(size:weight:)` for badges and
    /// counters that live inside the menu column.
    static func tvSidebarScaled(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: Theme.scaledSidebarFont(size), weight: weight)
    }
    #else
    // The UI font size preference is tvOS-only (#107), but a few shared
    // views call these helpers from code paths that also build for iOS and
    // macOS. Passing the baseline size straight through keeps those views
    // rendering exactly as they did while letting them scale on tvOS.
    static func tvScaled(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func tvSidebarScaled(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    #endif
}

#if os(tvOS)
extension UIFontSize {
    /// Dynamic Type step applied at the root of the tvOS scene (#107).
    ///
    /// The scaled fonts above only cover text with an explicit point size.
    /// A lot of the app — the player overlay, program detail, most list
    /// rows — uses the semantic styles (`.title2`, `.headline`, `.caption`),
    /// which ignore a point-size multiplier but *do* follow Dynamic Type.
    /// Setting this at the root is what makes those scale too.
    ///
    /// The mapping is centered on `.large`, the platform default, so
    /// `.medium` reproduces today's rendering exactly.
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .xLarge
        case .xLarge: return .xxLarge
        }
    }
}
#endif

// MARK: - Preview Helpers

#Preview("Theme Colors") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Group {
                Text("Theme Colors")
                    .font(.displayMedium)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.spacingSM) {
                    colorSwatch(Theme.accent, "Accent")
                    colorSwatch(Theme.accentSecondary, "Secondary")
                    colorSwatch(Theme.recording, "Recording")
                }

                HStack(spacing: Theme.spacingSM) {
                    colorSwatch(Theme.background, "Background")
                    colorSwatch(Theme.surface, "Surface")
                    colorSwatch(Theme.surfaceElevated, "Elevated")
                }

                HStack(spacing: Theme.spacingSM) {
                    colorSwatch(Theme.success, "Success")
                    colorSwatch(Theme.warning, "Warning")
                    colorSwatch(Theme.error, "Error")
                }
            }

            Divider()

            Group {
                Text("Buttons")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.spacingMD) {
                    Button("Primary") {}
                        .buttonStyle(AccentButtonStyle())

                    Button("Secondary") {}
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

            Divider()

            Group {
                Text("Cards")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.spacingMD) {
                    Text("Normal Card")
                        .padding()
                        .cardStyle()

                    Text("Selected Card")
                        .padding()
                        .cardStyle(isSelected: true)
                }
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding()
    }
    .background(Theme.background)
}

@ViewBuilder
private func colorSwatch(_ color: Color, _ name: String) -> some View {
    VStack {
        RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
            .fill(color)
            .frame(width: 60, height: 60)
        Text(name)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }
}
