//
//  PlayerPowerAssertion.swift
//  nextpvr-apple-client
//
//  What the player has to keep awake while it's on screen (issue #125).
//

import Foundation
#if os(macOS)
import IOKit.pwr_mgt
#endif

/// Which IOKit power assertion the player needs for what it is currently showing.
///
/// Playing video keeps the display awake, which is what a viewer expects. Pausing
/// used to drop every assertion — correct for a recording, wrong for live TV: the
/// NextPVR handle has to be renewed every few seconds or the server reclaims the
/// tuner and deletes the timeshift buffer (#120), and that renewal loop stops
/// running once the Mac idle-sleeps. So a paused live stream still holds the
/// system awake while letting the display go dark.
nonisolated enum PlayerPowerAssertion: Equatable {
    /// Display stays lit (and, implicitly, the system stays awake).
    case noDisplaySleep
    /// Display may sleep; the system may not.
    case noIdleSleep
    case none

    static func required(isLiveStream: Bool, isPlaying: Bool) -> PlayerPowerAssertion {
        if isPlaying { return .noDisplaySleep }
        return isLiveStream ? .noIdleSleep : .none
    }

    #if os(macOS)
    var ioKitType: String? {
        switch self {
        case .noDisplaySleep: return kIOPMAssertionTypeNoDisplaySleep
        case .noIdleSleep: return kIOPMAssertionTypeNoIdleSleep
        case .none: return nil
        }
    }
    #endif
}
