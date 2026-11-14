//
//  PlayerDiagnostics.swift
//  PVR Client
//
//  Readable descriptions of system events for the playback session log.
//

#if !os(macOS)
import AVFoundation

/// Turns audio session notifications into one-line descriptions for the
/// playback session log: an interruption or a route change (HDMI/eARC
/// renegotiation, AirPlay) can stop playback without mpv reporting anything.
nonisolated enum PlayerDiagnostics {
    static func describeInterruption(_ note: Notification) -> String {
        let info = note.userInfo ?? [:]
        let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt
        switch rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
        case .began:
            return "Audio session interrupted"
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            return options.contains(.shouldResume)
                ? "Audio session interruption ended (should resume)"
                : "Audio session interruption ended"
        default:
            return "Audio session interruption (unknown type)"
        }
    }

    static func describeRouteChange(_ note: Notification) -> String {
        let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portType.rawValue) \($0.portName)" }
            .joined(separator: ", ")
        return "Audio route changed (\(reasonName(reason))) → \(outputs.isEmpty ? "no output" : outputs)"
    }

    static func reasonName(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: return "new device"
        case .oldDeviceUnavailable: return "device removed"
        case .categoryChange: return "category change"
        case .override: return "override"
        case .wakeFromSleep: return "wake from sleep"
        case .noSuitableRouteForCategory: return "no suitable route"
        case .routeConfigurationChange: return "configuration change"
        case .unknown, .none: return "unknown"
        @unknown default: return "reason \(reason?.rawValue ?? 0)"
        }
    }
}
#endif
