//
//  BrandConfig.swift
//  PVR Client
//
//  Brand configuration protocol and typealias resolution
//

import SwiftUI

nonisolated protocol BrandConfig {
    // App identity
    static var appName: String { get }
    static var serverName: String { get }
    static var deviceName: String { get }

    // Network defaults
    static var defaultPort: Int { get }
    static var defaultPIN: String { get }
    static var authType: AuthType { get }

    // User-facing strings
    static var setupPrompt: String { get }
    static var serverFooter: String { get }
    static var authFooter: String { get }
    static var connectionSuccessMessage: String { get }
    static var configureServerMessage: String { get }

    // Discovery
    static var discoveryProbePath: String { get }

    // Colors
    static var accent: Color { get }
    static var accentSecondary: Color { get }
    static var background: Color { get }
    static var surface: Color { get }
    static var surfaceElevated: Color { get }
    static var surfaceHighlight: Color { get }
    static var textPrimary: Color { get }
    static var textSecondary: Color { get }
    static var textTertiary: Color { get }
    static var success: Color { get }
    static var warning: Color { get }
    static var error: Color { get }
    static var recording: Color { get }
    static var guideNowPlaying: Color { get }
}

// Exactly one brand flag must be defined by the target's
// SWIFT_ACTIVE_COMPILATION_CONDITIONS. Without this guard a missing flag
// silently compiles the *other* brand into the app (see build 366/367).
#if DISPATCHERPVR && NEXTPVR
#error("Both DISPATCHERPVR and NEXTPVR are defined. Exactly one brand flag must be set in SWIFT_ACTIVE_COMPILATION_CONDITIONS.")
#elseif !DISPATCHERPVR && !NEXTPVR
#error("No brand flag defined. Set DISPATCHERPVR or NEXTPVR in this target's SWIFT_ACTIVE_COMPILATION_CONDITIONS for every build configuration.")
#endif

#if DISPATCHERPVR
typealias Brand = DispatcherPVRBrand
#if !TOPSHELF_EXTENSION
typealias PVRClient = DispatcherClient
#endif
#else
typealias Brand = NexusPVRBrand
#if !TOPSHELF_EXTENSION
typealias PVRClient = NextPVRClient
#endif
#endif
