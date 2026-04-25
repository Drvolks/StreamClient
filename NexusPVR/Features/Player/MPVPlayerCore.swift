//
//  MPVPlayerCore.swift
//  nextpvr-apple-client
//
//  Core MPV player implementation — extracted from PlayerView.swift
//

import Foundation
import SwiftUI
import Libmpv
import QuartzCore
#if os(macOS)
import AppKit
import IOKit.pwr_mgt
import OpenGL.GL
import OpenGL.GL3
#else
import UIKit
import GLKit
import OpenGLES
#endif

nonisolated class MPVPlayerCore: NSObject, @unchecked Sendable {
    /// Helper to schedule work safely onto the main dispatch queue from any thread (including mpv render callbacks).
    /// Uses DispatchQueue.main.async to satisfy queue-assertion APIs (e.g. OpenGL) that crash on non-main-queue invocation.
    internal nonisolated static func scheduleOnMain(_ closure: @MainActor @escaping () -> Void) {
        DispatchQueue.main.async {
            closure()
        }
    }

    private var mpv: OpaquePointer?
    var mpvGL: OpaquePointer?
    private var errorBinding: Binding<String?>?
    private var isDestroyed = false
    private var positionTimer: Timer?
    private let eventLoopGroup = DispatchGroup()
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    let recordingMonitor = MPVRecordingMonitor()
    var isRecordingInProgress = false
    private var lastCodec: String?
    private var lastHeight: Int?
    private var lastHwdec: String?
    private var lastAudioChannels: String?
    private var hasTriedHwdecCopy = false
    private var currentURLPath: String?
    private var currentURL: URL?
    private var sourceURL: URL?
    private var lastPlaybackError: String?
    private var hasTriedMasterPlaylistFallback = false
    private var masterVariantCandidates: [URL] = []
    private var failedVariantURLs: Set<String> = []
    private var recoveryVariantCursor = 0
    private var lastLiveHLSReloadAt: Date = .distantPast
    private var hasDisabledHwdecForSession = false
    private var hasAppliedLiveHLSProfile = false
    private var lastPrintedMPVLog: String?
    private var lastPrintedMPVLogAt: Date = .distantPast
    private let networkEventLogger: any NetworkEventLogging

    // Performance stats accumulation
    private var fpsSamples: [Double] = []
    private var bitrateSamples: [Double] = []
    private var peakAvsync: Double = 0

    init(networkEventLogger: any NetworkEventLogging) {
        self.networkEventLogger = networkEventLogger
        super.init()
    }

    // Note: no deinit. Owners (ActivePlayerSession, PlayerView) are responsible
    // for calling `destroy()` explicitly before releasing the instance. Swift 6
    // makes deinit nonisolated, and `destroy()` touches main-actor state.

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true

        savePlayerStats()
        stopPositionPolling()

        // Nil out callbacks to break reference cycles with SwiftUI @State
        onPositionUpdate = nil
        onPlaybackEnded = nil
        onVideoInfoUpdate = nil
        recordingMonitor.stop()

        if let mpvGL = mpvGL {
            mpv_render_context_set_update_callback(mpvGL, nil, nil)
            mpv_render_context_free(mpvGL)
            self.mpvGL = nil
        }

        // Tell mpv to quit gracefully — this shuts down the VO thread, audio, etc.
        // Critical for vo=gpu+wid where mpv owns the render loop.
        if let mpv = mpv {
            mpv_command_string(mpv, "quit")
        }

        // Wait for the event loop thread to finish (it exits on MPV_EVENT_SHUTDOWN)
        eventLoopGroup.wait()

        if let mpv = mpv {
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }
    }

    func startPositionPolling() {
        stopPositionPolling()
        var statsCounter = 0
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Timers scheduled on the main RunLoop fire on the main thread —
            // safe to assume MainActor isolation here. Swift 6's Timer closure
            // is @Sendable, which is why we need this hop to access self's
            // MainActor-isolated members.
            MainActor.assumeIsolated {
                let position = self.getTimePosition()
                var duration = self.getDuration()

            // For recordings in progress: estimate growing duration via HEAD,
            // then subtract a 15s safety margin so the seek bar and playback
            // never reach the actual write edge (same approach as Kodi's
            // NextPVR addon). The demuxer still has real data beyond this
            // point, preventing EOF stalls during normal playback.
            if self.isRecordingInProgress {
                self.recordingMonitor.updateBaseline(duration: duration)
                self.recordingMonitor.refreshIfNeeded()
                let estimated = self.recordingMonitor.estimatedDuration
                if estimated > duration {
                    duration = estimated
                }
                duration = max(0, duration - 15)
                self.reportedDuration = duration
            }

            // Only query full video info every 2 seconds (4 ticks) to reduce mpv lock contention.
            // Position/duration are lightweight reads; getVideoInfo reads 6+ properties.
            statsCounter += 1
            let shouldQueryInfo = statsCounter % 4 == 0 || self.lastCodec == nil

            var info: (codec: String?, width: Int?, height: Int?, hwdec: String?, audioChannels: String?, droppedFrames: Int64, gamma: String?, fps: Double)?
            if shouldQueryInfo {
                let i = self.getVideoInfo()
                info = i
                let changed = i.codec != self.lastCodec || i.height != self.lastHeight || i.hwdec != self.lastHwdec || i.audioChannels != self.lastAudioChannels
                if changed {
                    self.lastCodec = i.codec
                    self.lastHeight = i.height
                    self.lastHwdec = i.hwdec
                    self.lastAudioChannels = i.audioChannels
                    if i.codec != nil {
                        self.logVideoInfo(i)
                    }
                }
            }

            // Log performance stats every 10 seconds (less frequent to reduce lock pressure)
            // Disabled by default — uncomment for diagnostics. Each call reads 7 mpv properties
            // which can cause frame drops on constrained hardware (4K HEVC on Apple TV).
            // if statsCounter % 20 == 0 {
            //     self.logPerformanceStats()
            // }

            self.onPositionUpdate?(position, duration)
                if let info {
                    self.onVideoInfoUpdate?(info.codec, info.height, info.hwdec, info.audioChannels, info.droppedFrames, info.gamma, info.fps)
                }
            }
        }
    }

    func stopPositionPolling() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func logPerformanceStats() {
        guard let mpv = mpv else { return }

        var droppedFrames: Int64 = 0
        mpv_get_property(mpv, "frame-drop-count", MPV_FORMAT_INT64, &droppedFrames)

        var decoderDroppedFrames: Int64 = 0
        mpv_get_property(mpv, "decoder-frame-drop-count", MPV_FORMAT_INT64, &decoderDroppedFrames)

        var fps: Double = 0
        mpv_get_property(mpv, "estimated-vf-fps", MPV_FORMAT_DOUBLE, &fps)

        var avsync: Double = 0
        mpv_get_property(mpv, "avsync", MPV_FORMAT_DOUBLE, &avsync)

        var voDelayed: Int64 = 0
        mpv_get_property(mpv, "vo-delayed-frame-count", MPV_FORMAT_INT64, &voDelayed)

        var videoBitrate: Double = 0
        mpv_get_property(mpv, "video-bitrate", MPV_FORMAT_DOUBLE, &videoBitrate)

        var cacheUsed: Int64 = 0
        mpv_get_property(mpv, "demuxer-cache-duration", MPV_FORMAT_INT64, &cacheUsed)

        // Accumulate samples for averages
        if fps > 0 { fpsSamples.append(fps) }
        if videoBitrate > 0 { bitrateSamples.append(videoBitrate / 1000) }
        peakAvsync = max(peakAvsync, abs(avsync))

        print("MPV [perf]: fps=\(String(format: "%.1f", fps)) avsync=\(String(format: "%.3f", avsync))s dropped=\(droppedFrames) decoder-dropped=\(decoderDroppedFrames) vo-delayed=\(voDelayed) bitrate=\(String(format: "%.0f", videoBitrate / 1000))kbps cache=\(cacheUsed)s")
    }

    func savePlayerStats() {
        guard let mpv = mpv else { return }

        var droppedFrames: Int64 = 0
        mpv_get_property(mpv, "frame-drop-count", MPV_FORMAT_INT64, &droppedFrames)

        var decoderDroppedFrames: Int64 = 0
        mpv_get_property(mpv, "decoder-frame-drop-count", MPV_FORMAT_INT64, &decoderDroppedFrames)

        var voDelayed: Int64 = 0
        mpv_get_property(mpv, "vo-delayed-frame-count", MPV_FORMAT_INT64, &voDelayed)

        let avgFps = fpsSamples.isEmpty ? 0 : fpsSamples.reduce(0, +) / Double(fpsSamples.count)
        let avgBitrate = bitrateSamples.isEmpty ? 0 : bitrateSamples.reduce(0, +) / Double(bitrateSamples.count)

        var stats = PlayerStats()
        stats.avgFps = avgFps
        stats.avgBitrateKbps = avgBitrate
        stats.totalDroppedFrames = droppedFrames
        stats.totalDecoderDroppedFrames = decoderDroppedFrames
        stats.totalVoDelayedFrames = voDelayed
        stats.maxAvsync = peakAvsync
        stats.save()
    }

    func getTimePosition() -> Double {
        guard let mpv = mpv else { return 0 }
        var position: Double = 0
        mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &position)
        return position
    }

    func getDuration() -> Double {
        guard let mpv = mpv else { return 0 }
        var duration: Double = 0
        mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &duration)
        return duration
    }

    /// The last duration reported to the UI (with 15s margin already applied).
    /// Set by PlayerView via the position timer callback.
    var reportedDuration: Double = 0

    func seek(seconds: Int) {
        guard let mpv = mpv else { return }
        var actualSeconds = seconds
        // Clamp forward seeks to the reported duration (which has 15s margin)
        if isRecordingInProgress && seconds > 0 && reportedDuration > 0 {
            let position = getTimePosition()
            let maxSeek = Int(reportedDuration - position)
            if maxSeek <= 0 { return }
            actualSeconds = min(seconds, maxSeek)
        }
        let command = "seek \(actualSeconds) relative"
        let result = mpv_command_string(mpv, command)
        if result < 0 {
            print("MPV: seek command failed: \(result)")
        }
    }

    func seekTo(position: Double) {
        guard let mpv = mpv else { return }
        var target = position
        // Clamp to the reported duration (which has 15s margin)
        if isRecordingInProgress && reportedDuration > 0 {
            target = min(target, reportedDuration)
        }
        let command = "seek \(target) absolute"
        let result = mpv_command_string(mpv, command)
        if result < 0 {
            print("MPV: seekTo command failed: \(result)")
        }
    }

    func startRecordingMonitor(url: URL) {
        guard let mpv = mpv else { return }
        recordingMonitor.start(mpv: mpv, url: url.absoluteString)
    }



    func getVideoInfo() -> (codec: String?, width: Int?, height: Int?, hwdec: String?, audioChannels: String?, droppedFrames: Int64, gamma: String?, fps: Double) {
        guard let mpv = mpv else { return (nil, nil, nil, nil, nil, 0, nil, 0) }

        var codec: String?
        var width: Int?
        var height: Int?
        var hwdec: String?
        var audioChannels: String?

        if let cString = mpv_get_property_string(mpv, "video-codec") {
            codec = String(cString: cString)
            mpv_free(cString)
        }

        var w: Int64 = 0
        if mpv_get_property(mpv, "width", MPV_FORMAT_INT64, &w) >= 0 {
            width = Int(w)
        }

        var h: Int64 = 0
        if mpv_get_property(mpv, "height", MPV_FORMAT_INT64, &h) >= 0 {
            height = Int(h)
        }

        if let cString = mpv_get_property_string(mpv, "hwdec-current") {
            hwdec = String(cString: cString)
            mpv_free(cString)
        }

        if let cString = mpv_get_property_string(mpv, "audio-params/channel-count") {
            let count = String(cString: cString)
            mpv_free(cString)
            if let n = Int(count) {
                switch n {
                case 1: audioChannels = "Mono"
                case 2: audioChannels = "Stereo"
                case 6: audioChannels = "5.1"
                case 8: audioChannels = "7.1"
                default: audioChannels = "\(n)ch"
                }
            }
        }

        var droppedFrames: Int64 = 0
        mpv_get_property(mpv, "frame-drop-count", MPV_FORMAT_INT64, &droppedFrames)

        // Color transfer function (e.g. "pq", "hlg", "bt.1886") for HDR display mode matching
        var gamma: String?
        if let cString = mpv_get_property_string(mpv, "video-params/gamma") {
            gamma = String(cString: cString)
            mpv_free(cString)
        }

        // Frame rate for display mode matching
        var fps: Double = 0
        mpv_get_property(mpv, "container-fps", MPV_FORMAT_DOUBLE, &fps)

        return (codec, width, height, hwdec, audioChannels, droppedFrames, gamma, fps)
    }

    func getTrackList() -> [MPVTrack] {
        guard let mpv = mpv else { return [] }

        var count: Int64 = 0
        mpv_get_property(mpv, "track-list/count", MPV_FORMAT_INT64, &count)

        var tracks: [MPVTrack] = []
        for i in 0..<Int(count) {
            var trackId: Int64 = 0
            mpv_get_property(mpv, "track-list/\(i)/id", MPV_FORMAT_INT64, &trackId)

            var type: String?
            if let cString = mpv_get_property_string(mpv, "track-list/\(i)/type") {
                type = String(cString: cString)
                mpv_free(cString)
            }
            guard let trackType = type else { continue }

            var title: String?
            if let cString = mpv_get_property_string(mpv, "track-list/\(i)/title") {
                title = String(cString: cString)
                mpv_free(cString)
            }

            var lang: String?
            if let cString = mpv_get_property_string(mpv, "track-list/\(i)/lang") {
                lang = String(cString: cString)
                mpv_free(cString)
            }

            var codec: String?
            if let cString = mpv_get_property_string(mpv, "track-list/\(i)/codec") {
                codec = String(cString: cString)
                mpv_free(cString)
            }

            var channels: String?
            if let cString = mpv_get_property_string(mpv, "track-list/\(i)/demux-channel-count") {
                channels = String(cString: cString)
                mpv_free(cString)
            }

            var bitrate: Int64 = 0
            mpv_get_property(mpv, "track-list/\(i)/demux-bitrate", MPV_FORMAT_INT64, &bitrate)

            var selected: Int32 = 0
            mpv_get_property(mpv, "track-list/\(i)/selected", MPV_FORMAT_FLAG, &selected)

            tracks.append(MPVTrack(
                id: Int(trackId),
                type: trackType,
                title: title,
                lang: lang,
                codec: codec,
                channels: channels,
                bitrate: bitrate > 0 ? Int(bitrate) : nil,
                isSelected: selected != 0
            ))
        }
        return tracks
    }

    private var isChangingTrack = false

    func setAudioTrack(_ trackId: Int) {
        guard let mpv = mpv else { return }
        isChangingTrack = true
        var value = Int64(trackId)
        mpv_set_property(mpv, "aid", MPV_FORMAT_INT64, &value)
        // Allow enough time for mpv to reconfigure audio on non-seekable streams
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.isChangingTrack = false
        }
    }

    func getSubtitleText() -> String? {
        guard let mpv = mpv else { return nil }
        guard let cString = mpv_get_property_string(mpv, "sub-text") else { return nil }
        let text = String(cString: cString)
        mpv_free(cString)
        return text.isEmpty ? nil : text
    }

    func setSubtitleTrack(_ trackId: Int?) {
        guard let mpv = mpv else { return }
        if let trackId = trackId {
            var value = Int64(trackId)
            mpv_set_property(mpv, "sid", MPV_FORMAT_INT64, &value)
        } else {
            mpv_set_property_string(mpv, "sid", "no")
        }
    }

    private var hasLoggedVideoInfo = false

    private func logVideoInfo(_ info: (codec: String?, width: Int?, height: Int?, hwdec: String?, audioChannels: String?, droppedFrames: Int64, gamma: String?, fps: Double)) {
        guard !hasLoggedVideoInfo, info.codec != nil else { return }
        hasLoggedVideoInfo = true

        var details: [String] = []
        if let w = info.width, let h = info.height {
            details.append("\(w)x\(h)")
        }
        if let codec = info.codec {
            details.append(codec)
        }
        if let hw = info.hwdec, !hw.isEmpty, hw != "no" {
            details.append("hwdec: \(hw)")
        } else {
            details.append("swdec")
        }
        if let audio = info.audioChannels {
            details.append(audio)
        }

        networkEventLogger.log(NetworkEvent(
            timestamp: Date(),
            method: "PLAY",
            path: details.joined(separator: " · "),
            statusCode: nil,
            isSuccess: true,
            durationMs: 0,
            responseSize: 0,
            errorDetail: nil
        ))
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false) -> Bool {
        self.errorBinding = errorBinding
        self.isRecordingInProgress = isRecordingInProgress

        // Create MPV
        mpv = mpv_create()
        guard let mpv = mpv else {
            print("MPV: Failed to create context")
            return false
        }

        // Video output
        #if os(macOS)
        let gpuAPI = UserPreferences.load().macosGPUAPI
        if gpuAPI == .pixelbuffer {
            mpv_set_option_string(mpv, "vo", "pixelbuffer")
            print("MPV: macOS VO = pixelbuffer (AVSampleBufferDisplayLayer)")
        } else if gpuAPI == .metal {
            mpv_set_option_string(mpv, "vo", "gpu")
            mpv_set_option_string(mpv, "gpu-api", "metal")
            mpv_set_option_string(mpv, "gpu-context", "metal")
            print("MPV: macOS GPU API = Metal")
        } else {
            mpv_set_option_string(mpv, "vo", "libmpv")
            mpv_set_option_string(mpv, "gpu-api", "opengl")
            print("MPV: macOS GPU API = OpenGL")
        }
        #elseif os(tvOS)
        let gpuAPI = UserPreferences.load().tvosGPUAPI
        if gpuAPI == .pixelbuffer {
            mpv_set_option_string(mpv, "vo", "pixelbuffer")
            print("MPV: tvOS VO = pixelbuffer (AVSampleBufferDisplayLayer)")
        } else if gpuAPI == .metal {
            mpv_set_option_string(mpv, "vo", "gpu")
            mpv_set_option_string(mpv, "gpu-api", "metal")
            mpv_set_option_string(mpv, "gpu-context", "metal")
            print("MPV: tvOS GPU API = Metal")
        } else {
            mpv_set_option_string(mpv, "vo", "libmpv")
            mpv_set_option_string(mpv, "gpu-api", "opengl")
            mpv_set_option_string(mpv, "opengl-es", "yes")
            print("MPV: tvOS GPU API = OpenGL")
        }
        #elseif os(iOS)
        let gpuAPI = UserPreferences.load().iosGPUAPI
        if gpuAPI == .pixelbuffer {
            mpv_set_option_string(mpv, "vo", "pixelbuffer")
            print("MPV: iOS VO = pixelbuffer (AVSampleBufferDisplayLayer)")
        } else if gpuAPI == .metal {
            mpv_set_option_string(mpv, "vo", "gpu")
            mpv_set_option_string(mpv, "gpu-api", "metal")
            mpv_set_option_string(mpv, "gpu-context", "metal")
            print("MPV: iOS GPU API = Metal")
        } else {
            mpv_set_option_string(mpv, "vo", "libmpv")
            mpv_set_option_string(mpv, "gpu-api", "opengl")
            mpv_set_option_string(mpv, "opengl-es", "yes")
            print("MPV: iOS GPU API = OpenGL")
        }
        #else
        mpv_set_option_string(mpv, "vo", "libmpv")
        mpv_set_option_string(mpv, "gpu-api", "opengl")
        mpv_set_option_string(mpv, "opengl-es", "yes")
        #endif

        // Keep video letterboxed to source aspect ratio across view size changes.
        mpv_set_option_string(mpv, "keepaspect", "yes")

        // Enable yt-dlp for direct YouTube URL support (optional)
        mpv_set_option_string(mpv, "ytdl", "no")

        // Disable ALL Lua scripts — LuaJIT's JIT compiler generates code at runtime
        // that violates macOS hardened runtime code signing (SIGKILL Code Signature Invalid).
        // Each built-in script must be disabled individually; load-scripts only affects external ones.
        mpv_set_option_string(mpv, "load-scripts", "no")
        mpv_set_option_string(mpv, "osc", "no")
        mpv_set_option_string(mpv, "load-stats-overlay", "no")
        mpv_set_option_string(mpv, "load-console", "no")
        mpv_set_option_string(mpv, "load-auto-profiles", "no")
        mpv_set_option_string(mpv, "load-select", "no")
        mpv_set_option_string(mpv, "load-commands", "no")
        mpv_set_option_string(mpv, "load-context-menu", "no")
        mpv_set_option_string(mpv, "load-positioning", "no")
        mpv_set_option_string(mpv, "input-default-bindings", "no")

        // Hardware decoding - only H.264/HEVC use hardware decode
        // AV1/VP9 forced to software (AV1 hwdec is broken on iOS, causes texture errors)
        mpv_set_option_string(mpv, "hwdec", "auto-safe")
        mpv_set_option_string(mpv, "hwdec-codecs", "h264,hevc,av1")
        // Allow more hw decode failures before permanent fallback to software.
        // Live MPEG-TS streams start mid-GOP without SPS/PPS, causing initial
        // VideoToolbox errors. Default threshold is too low — mpv falls back to
        // software permanently before the first IDR frame arrives.
        mpv_set_option_string(mpv, "vd-lavc-software-fallback", "600")

        // CPU threading for software decode (MPV recommends max 16)
        let threadCount = min(ProcessInfo.processInfo.processorCount * 2, 16)
        mpv_set_option_string(mpv, "vd-lavc-threads", "\(threadCount)")

        // Keep player open
        mpv_set_option_string(mpv, "keep-open", "yes")
        mpv_set_option_string(mpv, "idle", "yes")

        // Frame dropping — allow mpv to drop frames when video can't keep up with audio
        // Prevents progressive A/V desync on slower hardware (e.g. 4K HEVC on older Apple TV)
        mpv_set_option_string(mpv, "framedrop", "vo")

        // Buffering for streaming - wait for video to buffer before starting
        mpv_set_option_string(mpv, "cache", "yes")
        mpv_set_option_string(mpv, "cache-secs", "120")
        mpv_set_option_string(mpv, "cache-pause-initial", "yes")
        mpv_set_option_string(mpv, "demuxer-max-bytes", "150MiB")
        mpv_set_option_string(mpv, "demuxer-max-back-bytes", "150MiB")
        mpv_set_option_string(mpv, "demuxer-seekable-cache", "yes")
        mpv_set_option_string(mpv, "cache-pause-wait", "1")       // Shorter pause to avoid visible glitches
        mpv_set_option_string(mpv, "cache-pause", "yes")          // Pause and rebuffer on underrun (prevents choppy live streams)
        mpv_set_option_string(mpv, "demuxer-readahead-secs", "60")

        // Network
        mpv_set_option_string(mpv, "network-timeout", "30")
        mpv_set_option_string(mpv, "stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=3")
        if isRecordingInProgress {
            // Growing file: when the stream hits EOF, close and reopen the
            // HTTP connection to get a fresh Content-Length with new data.
            // Combined with demuxer-force-retry-eof, this lets mpv seamlessly
            // play a file that's still being written to.
            mpv_set_option_string(mpv, "stream-lavf-growing-file", "yes")
            mpv_set_option_string(mpv, "demuxer-force-retry-eof", "yes")
            mpv_set_option_string(mpv, "cache-pause-initial", "no")
        }

        // Audio
        #if os(macOS)
        mpv_set_option_string(mpv, "ao", "coreaudio")
        mpv_set_option_string(mpv, "audio-buffer", "0.5")  // Larger buffer on macOS to avoid coreaudio race with raw TS streams
        mpv_set_option_string(mpv, "audio-wait-open", "0.5")  // Delay opening audio device until data is ready (prevents NULL buffer crash with raw TS streams)
        #elseif os(tvOS)
        mpv_set_option_string(mpv, "ao", "audiounit")
        mpv_set_option_string(mpv, "audio-buffer", "0.5")
        mpv_set_option_string(mpv, "audio-wait-open", "0.5")
        #else
        mpv_set_option_string(mpv, "ao", "audiounit")
        mpv_set_option_string(mpv, "audio-buffer", "0.2")
        #endif
        let audioChannels = UserPreferences.load().audioChannels
        mpv_set_option_string(mpv, "audio-channels", audioChannels)
        mpv_set_option_string(mpv, "volume", "100")
        mpv_set_option_string(mpv, "audio-fallback-to-null", "yes")
        mpv_set_option_string(mpv, "audio-stream-silence", "no")

        // Seeking - precise seeks for better audio sync with external audio tracks
        mpv_set_option_string(mpv, "hr-seek", "yes")

        // Subtitles: start with no subtitle selected; user picks from settings panel.
        // Subtitles: use custom SwiftUI overlay across all renderers.
        // Keep mpv subtitle decoding enabled via sid, but disable native drawing.
        mpv_set_option_string(mpv, "sid", "no")
        mpv_set_option_string(mpv, "sub-visibility", "no")

        // Disable MPV's built-in OSD (seek bar, etc.) — we use our own SwiftUI overlay
        mpv_set_option_string(mpv, "osd-level", "0")

        // Dithering - disabled on GLES 2.0 (tvOS/iOS) to avoid INVALID_ENUM texture errors
        // in dumb mode. Content is 8-bit SDR to 8-bit display, so dithering has no effect.
        #if os(macOS)
        mpv_set_option_string(mpv, "dither", "ordered")
        #else
        mpv_set_option_string(mpv, "dither", "no")
        #endif

        // Demuxer
        mpv_set_option_string(mpv, "demuxer", "lavf")
        mpv_set_option_string(mpv, "demuxer-lavf-probe-info", "auto")
        mpv_set_option_string(mpv, "demuxer-lavf-analyzeduration", "3000000")

        // Initialize MPV
        let initResult = mpv_initialize(mpv)
        guard initResult >= 0 else {
            print("MPV: Failed to initialize, error: \(initResult)")
            return false
        }

        print("MPV: Initialized successfully")

        // Request error/fatal logs only to avoid MPV log buffer overflows
        // on noisy live HLS streams.
        mpv_request_log_messages(mpv, "error")

        // Observe eof-reached so we know when playback finishes
        // (keep-open=yes prevents MPV_EVENT_END_FILE from firing on EOF)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)

        // Start event loop
        startEventLoop()

        return true
    }

    func loadURL(_ url: URL) {
        loadURL(url, isFallbackAttempt: false)
    }

    private func loadURL(_ url: URL, isFallbackAttempt: Bool) {
        guard let mpv = mpv else {
            print("MPV: No context available")
            return
        }

        let urlString = url.absoluteString
        currentURL = url
        currentURLPath = url.path
        if !isFallbackAttempt {
            sourceURL = url
            hasTriedMasterPlaylistFallback = false
            masterVariantCandidates = []
            failedVariantURLs.removeAll()
            recoveryVariantCursor = 0
        }
        if isLikelyUnstableLiveHLS(url) {
            applyLiveHLSProfileIfNeeded(mpv: mpv)
        }
        print("MPV: Loading URL: \(urlString)")

        // Fix TS timing issues (genpts regenerates PTS, igndts ignores broken DTS)
        if url.pathExtension.lowercased() == "ts" {
            mpv_set_property_string(mpv, "demuxer-lavf-o", "fflags=+genpts+igndts")
        } else {
            mpv_set_property_string(mpv, "demuxer-lavf-o", "")
        }

        // Use mpv_command_string for simpler string-based command
        let command = "loadfile \"\(urlString)\" replace"
        let result = mpv_command_string(mpv, command)
        if result < 0 {
            let errorStr = String(cString: mpv_error_string(result))
            print("MPV: loadfile command failed: \(errorStr) (\(result))")
        } else {
            print("MPV: loadfile command sent successfully")
        }
    }

    func play() {
        guard let mpv = mpv else { return }
        var flag: Int32 = 0
        let result = mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        if result < 0 {
            print("MPV: Failed to unpause: \(result)")
        }
    }

    func pause() {
        guard let mpv = mpv else { return }
        var flag: Int32 = 1
        let result = mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        if result < 0 {
            print("MPV: Failed to pause: \(result)")
        }
    }

    var isPaused: Bool {
        guard let mpv = mpv else { return true }
        var flag: Int32 = 0
        mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        return flag != 0
    }

    #if os(macOS) || os(tvOS) || os(iOS)
    func setWindowID(_ layer: CAMetalLayer) {
        guard let mpv = mpv else { return }

        // Cast the layer pointer to Int64 for mpv's wid option
        let wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        var widValue = wid

        // wid can change at runtime on rotation/resize; use property update.
        let result = mpv_set_property(mpv, "wid", MPV_FORMAT_INT64, &widValue)
        if result < 0 {
            let errorStr = String(cString: mpv_error_string(result))
            print("MPV: Failed to set wid: \(errorStr)")
        } else {
            print("MPV: Successfully set window ID")
        }
    }
    #endif

    #if os(iOS) || os(tvOS)
    @MainActor
    func createRenderContext(view: MPVPlayerGLView) {
        guard let mpv = mpv else { return }

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: { (ctx, name) -> UnsafeMutableRawPointer? in
                let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
                let identifier = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString)
                return CFBundleGetFunctionPointerForName(identifier, symbolName)
            },
            get_proc_address_ctx: nil
        )

        withUnsafeMutablePointer(to: &initParams) { initParamsPtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initParamsPtr),
                mpv_render_param()
            ]

            let result = mpv_render_context_create(&mpvGL, mpv, &params)
            if result < 0 {
                let errorStr = String(cString: mpv_error_string(result))
                print("MPV: Failed to create render context: \(errorStr)")
                return
            }
            print("MPV: Render context created successfully")

            view.mpvGL = UnsafeMutableRawPointer(mpvGL)

            // iOS/tvOS OpenGL path: rely exclusively on CADisplayLink-driven rendering.
            // Avoid libmpv VO-thread callback interactions that can trigger queue assertions
            // in debug builds on Apple platforms.
            mpv_render_context_set_update_callback(mpvGL, nil, nil)
        }
    }
    #endif

    #if os(macOS)
    func createRenderContext(view: MPVPlayerMacOGLView) {
        guard let mpv = mpv else { return }

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: { (_, name) -> UnsafeMutableRawPointer? in
                let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
                let identifier = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
                return CFBundleGetFunctionPointerForName(identifier, symbolName)
            },
            get_proc_address_ctx: nil
        )

        withUnsafeMutablePointer(to: &initParams) { initParamsPtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initParamsPtr),
                mpv_render_param()
            ]

            let result = mpv_render_context_create(&mpvGL, mpv, &params)
            if result < 0 {
                let errorStr = String(cString: mpv_error_string(result))
                print("MPV: Failed to create macOS OpenGL render context: \(errorStr)")
                return
            }
            print("MPV: macOS OpenGL render context created successfully")

            view.mpvGL = UnsafeMutableRawPointer(mpvGL)

            mpv_render_context_set_update_callback(
                mpvGL,
                { ctx in
                    guard let ctx else { return }
                    let view = Unmanaged<MPVPlayerMacOGLView>.fromOpaque(ctx).takeUnretainedValue()
                    guard view.needsDrawing else { return }
                    view.renderQueue.async {
                        DispatchQueue.main.async {
                            view.display()
                        }
                    }
                },
                UnsafeMutableRawPointer(Unmanaged.passUnretained(view).toOpaque())
            )
        }
    }
    #endif

    private func startEventLoop() {
        eventLoopGroup.enter()
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            defer { self?.eventLoopGroup.leave() }
            while let strongSelf = self, !strongSelf.isDestroyed, let mpv = strongSelf.mpv {
                guard let event = mpv_wait_event(mpv, 0.5) else { continue }
                if strongSelf.isDestroyed { break }
                strongSelf.handleEvent(event.pointee)

                if event.pointee.event_id == MPV_EVENT_SHUTDOWN {
                    break
                }
            }
            print("MPV: Event loop ended")
        }
    }

    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_LOG_MESSAGE:
            if let msg = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee,
               let text = msg.text {
                let logText = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
                let level = msg.level.map { String(cString: $0) } ?? "info"
                if (level == "error" || level == "fatal"),
                   !logText.isEmpty,
                   !logText.hasPrefix("Set property:"),
                   shouldEmitMPVLog(level: level, text: logText) {
                    print("MPV [\(level)]: \(logText)")
                }

                // Log mpv errors and HTTP warnings to the event log
                // Skip transient errors during audio/subtitle track changes
                if (level == "error" || level == "fatal") && !isChangingTrack {
                    networkEventLogger.log(NetworkEvent(
                        timestamp: Date(),
                        method: "PLAY",
                        path: currentURLPath ?? "mpv",
                        statusCode: nil,
                        isSuccess: false,
                        durationMs: 0,
                        responseSize: 0,
                        errorDetail: logText
                    ))
                }

                // Capture HTTP errors for on-screen display.
                // Prefer HTTP errors (e.g. "503 Service Unavailable") over generic
                // "Failed to open" messages that follow.
                if !isChangingTrack {
                    if level == "warn" && logText.contains("HTTP error") {
                        lastPlaybackError = logText
                    } else if level == "error" && lastPlaybackError == nil {
                        if logText.contains("Failed to open") || logText.contains("Failed to recognize") {
                            lastPlaybackError = logText
                        }
                    }
                }

                if level == "error", !isChangingTrack, tryNextVariantAfterSegmentError(logText) {
                    return
                }

                // Detect hardware decoding texture failures on iOS/tvOS where
                // OpenGL ES can't handle certain VideoToolbox surface formats
                // (e.g. p010 for 10-bit HDR, or standard 4K HEVC textures).
                // Fall back to videotoolbox-copy which copies frames to CPU memory.
                #if !os(macOS)
                if !hasTriedHwdecCopy && level == "error" && (
                    logText.contains("texture") ||
                    logText.contains("hardware decod") ||
                    logText.contains("surface failed")
                ) {
                    hasTriedHwdecCopy = true
                    print("MPV: Hardware texture failure — falling back to videotoolbox-copy")
                    mpv_set_property_string(mpv, "hwdec", "videotoolbox-copy")
                    hasLoggedVideoInfo = false  // Re-log video info after hwdec change
                    networkEventLogger.log(NetworkEvent(
                        timestamp: Date(),
                        method: "PLAY",
                        path: "hwdec fallback → videotoolbox-copy",
                        statusCode: nil,
                        isSuccess: false,
                        durationMs: 0,
                        responseSize: 0,
                        errorDetail: logText
                    ))
                }

                // Some live HLS feeds repeatedly fail VT init (err=-12906) before
                // eventually falling back to software. Disable hwdec early for this
                // session to reduce startup stalls and repeated decoder churn.
                if !hasDisabledHwdecForSession && level == "error" &&
                    logText.contains("Failed setup for format videotoolbox_vld") {
                    hasDisabledHwdecForSession = true
                    mpv_set_property_string(mpv, "hwdec", "no")
                    print("MPV: Disabled hwdec for this session after repeated VT init failures")
                }
                #endif
            }

        case MPV_EVENT_START_FILE:
            print("MPV: Starting file")

        case MPV_EVENT_FILE_LOADED:
            print("MPV: File loaded successfully")

        case MPV_EVENT_PLAYBACK_RESTART:
            print("MPV: Playback started/restarted")
            let info = getVideoInfo()
            DispatchQueue.main.async { [weak self] in
                self?.onVideoInfoUpdate?(info.codec, info.height, info.hwdec, info.audioChannels, info.droppedFrames, info.gamma, info.fps)
                if let self = self, info.codec != nil {
                    self.logVideoInfo(info)
                }
            }

        case MPV_EVENT_AUDIO_RECONFIG:
            print("MPV: Audio reconfigured")

        case MPV_EVENT_VIDEO_RECONFIG:
            print("MPV: Video reconfigured")

        case MPV_EVENT_END_FILE:
            if let data = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee {
                let reason = data.reason
                print("MPV: Playback ended (reason: \(reason))")
                if reason == MPV_END_FILE_REASON_EOF {
                    if shouldIgnoreEOFAsTransientLiveHLS() {
                        print("MPV: Ignoring transient EOF for live HLS stream")
                        recoverLiveHLSAfterEOFIfNeeded()
                        return
                    }
                    // Normal end of file - video finished playing
                    print("MPV: Video playback completed naturally")
                    DispatchQueue.main.async { [weak self] in
                        self?.onPlaybackEnded?()
                    }
                } else if reason == MPV_END_FILE_REASON_ERROR {
                    let error = data.error
                    let errorStr = String(cString: mpv_error_string(error))
                    // Ignore transient errors during audio/subtitle track changes —
                    // mpv may internally seek to resync, which fails on non-seekable streams.
                    if isChangingTrack {
                        print("MPV: Ignoring error during track change: \(errorStr)")
                        return
                    }
                    if tryMasterPlaylistFallbackIfNeeded() {
                        return
                    }
                    if shouldAutoRecoverLiveHLSOnError(errorText: errorStr) {
                        print("MPV: Recovering live HLS stream after error: \(errorStr)")
                        recoverLiveHLSAfterFailureIfNeeded()
                        return
                    }
                    let path = currentURLPath ?? "unknown"
                    let detail = lastPlaybackError ?? errorStr
                    print("MPV: Playback error: \(errorStr)")

                    // Log to event log (no weak self — NetworkEventLog is a singleton)
                    networkEventLogger.log(NetworkEvent(
                        timestamp: Date(),
                        method: "PLAY",
                        path: path,
                        statusCode: nil,
                        isSuccess: false,
                        durationMs: 0,
                        responseSize: 0,
                        errorDetail: detail
                    ))

                    // Show error on screen
                    let errorBinding = self.errorBinding
                    DispatchQueue.main.async {
                        errorBinding?.wrappedValue = detail
                    }
                    lastPlaybackError = nil
                }
            }

        case MPV_EVENT_PROPERTY_CHANGE:
            if let prop = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee {
                let name = String(cString: prop.name)
                if name == "eof-reached",
                   prop.format == MPV_FORMAT_FLAG,
                   let flag = prop.data?.assumingMemoryBound(to: Int32.self).pointee,
                   flag != 0 {
                    if isChangingTrack {
                        print("MPV: Ignoring eof-reached during track change")
                        return
                    }
                    if shouldIgnoreEOFAsTransientLiveHLS() {
                        print("MPV: Ignoring eof-reached for live HLS stream")
                        recoverLiveHLSAfterEOFIfNeeded()
                        return
                    }
                    print("MPV: EOF reached (keep-open)")
                    DispatchQueue.main.async { [weak self] in
                        self?.onPlaybackEnded?()
                    }
                }
            }

        case MPV_EVENT_SHUTDOWN:
            print("MPV: Shutdown event received")

        case MPV_EVENT_NONE:
            break

        default:
            print("MPV: Event \(event.event_id.rawValue)")
        }
    }

    private func tryMasterPlaylistFallbackIfNeeded() -> Bool {
        guard !hasTriedMasterPlaylistFallback, let url = currentURL else { return false }
        guard url.pathExtension.lowercased() == "m3u8" else { return false }
        guard url.lastPathComponent.lowercased().contains("master") else { return false }
        hasTriedMasterPlaylistFallback = true

        Task { [weak self] in
            guard let self else { return }
            let variants = await self.resolvePreferredVariantURLs(from: url)
            let reachableVariants = await self.filterReachableVariantURLs(variants)
            let usableVariants = reachableVariants.isEmpty ? variants : reachableVariants
            guard let mediaURL = usableVariants.first, mediaURL != url else {
                return
            }
            self.masterVariantCandidates = usableVariants
            self.failedVariantURLs.removeAll()
            self.recoveryVariantCursor = 0

            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "PLAY",
                path: mediaURL.path,
                statusCode: nil,
                isSuccess: true,
                durationMs: 0,
                responseSize: 0,
                errorDetail: "Master playlist fallback applied"
            ))

            self.loadURL(mediaURL, isFallbackAttempt: true)
        }

        return true
    }

    private func resolvePreferredVariantURLs(from masterURL: URL) async -> [URL] {
        do {
            let (data, _) = try await URLSession.shared.data(from: masterURL)
            guard let content = String(data: data, encoding: .utf8) else { return [] }
            guard content.contains("#EXT-X-STREAM-INF") else { return [] }

            let lines = content
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            var candidates: [(url: URL, score: Int, bandwidth: Int)] = []
            var pendingInf: String?

            for line in lines {
                if line.hasPrefix("#EXT-X-STREAM-INF:") {
                    pendingInf = String(line.dropFirst("#EXT-X-STREAM-INF:".count))
                    continue
                }
                guard let inf = pendingInf else { continue }
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let variantURL = URL(string: line, relativeTo: masterURL)?.absoluteURL else {
                    pendingInf = nil
                    continue
                }

                let attrs = parseHLSAttributes(inf)
                let codecs = (attrs["CODECS"] ?? "").lowercased()
                let bandwidth = Int(attrs["BANDWIDTH"] ?? "") ?? 0
                var score = 0

                if codecs.contains("avc1") { score += 100 }
                if codecs.contains("hvc1") || codecs.contains("hev1") || codecs.contains("av01") { score -= 100 }
                if codecs.contains("mp4a") { score += 10 }

                candidates.append((variantURL, score, bandwidth))
                pendingInf = nil
            }

            let avcCandidates = candidates
                .filter { $0.score > 0 } // AVC + audio preferred

            // Prefer a conservative bitrate for unstable live HLS.
            // In practice this is often much more resilient than forcing the top variant.
            let conservativeCap = 2_500_000
            if let underCap = avcCandidates
                .filter({ $0.bandwidth > 0 && $0.bandwidth <= conservativeCap })
                .sorted(by: { $0.bandwidth > $1.bandwidth })
                .first {
                var ordered: [URL] = [underCap.url]
                ordered.append(contentsOf: avcCandidates
                    .filter { $0.url != underCap.url }
                    .sorted(by: { lhs, rhs in
                        if lhs.bandwidth == 0 { return false }
                        if rhs.bandwidth == 0 { return true }
                        return lhs.bandwidth < rhs.bandwidth
                    })
                    .map(\.url))
                return dedupeURLs(ordered)
            }

            if let lowestAVC = avcCandidates
                .sorted(by: { lhs, rhs in
                    if lhs.bandwidth == 0 { return false }
                    if rhs.bandwidth == 0 { return true }
                    return lhs.bandwidth < rhs.bandwidth
                })
                .first {
                var ordered: [URL] = [lowestAVC.url]
                ordered.append(contentsOf: avcCandidates
                    .filter { $0.url != lowestAVC.url }
                    .sorted(by: { $0.bandwidth < $1.bandwidth })
                    .map(\.url))
                return dedupeURLs(ordered)
            }

            return dedupeURLs(candidates
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    if lhs.bandwidth == 0 { return false }
                    if rhs.bandwidth == 0 { return true }
                    return lhs.bandwidth < rhs.bandwidth
                }
                .map(\.url))
        } catch {
            return []
        }
    }

    private func parseHLSAttributes(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let parts = splitCSVPreservingQuotedCommas(raw)
        for part in parts {
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard pieces.count == 2 else { continue }
            let key = String(pieces[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            result[key] = value
        }
        return result
    }

    private func splitCSVPreservingQuotedCommas(_ text: String) -> [Substring] {
        var result: [Substring] = []
        var start = text.startIndex
        var index = text.startIndex
        var inQuotes = false

        while index < text.endIndex {
            let char = text[index]
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ",", !inQuotes {
                result.append(text[start..<index])
                start = text.index(after: index)
            }
            index = text.index(after: index)
        }

        if start <= text.endIndex {
            result.append(text[start..<text.endIndex])
        }
        return result.filter { !$0.isEmpty }
    }

    private func shouldIgnoreEOFAsTransientLiveHLS() -> Bool {
        guard !isRecordingInProgress else { return false }
        guard let url = currentURL, url.pathExtension.lowercased() == "m3u8" else { return false }
        return !isCurrentStreamSeekable()
    }

    private func isCurrentStreamSeekable() -> Bool {
        guard let mpv else { return true }
        var flag: Int32 = 1
        if mpv_get_property(mpv, "seekable", MPV_FORMAT_FLAG, &flag) >= 0 {
            return flag != 0
        }
        return true
    }

    private func recoverLiveHLSAfterEOFIfNeeded() {
        print("MPV: Live HLS EOF detected, scheduling reload")
        recoverLiveHLSAfterFailureIfNeeded()
    }

    private func recoverLiveHLSAfterFailureIfNeeded() {
        guard let url = currentURL else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLiveHLSReloadAt) >= 1.5 else { return }
        lastLiveHLSReloadAt = now
        let targetURL = nextRecoveryURL(current: url)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            print("MPV: Reloading live HLS stream after EOF (\(targetURL.absoluteString))")
            self.loadURL(targetURL, isFallbackAttempt: true)
        }
    }

    private func shouldAutoRecoverLiveHLSOnError(errorText: String) -> Bool {
        guard let url = currentURL, isLikelyUnstableLiveHLS(url) else { return false }
        let text = errorText.lowercased()
        return text.contains("timed out") ||
            text.contains("tls") ||
            text.contains("avformat_open_input() failed") ||
            text.contains("failed to recognize file format")
    }

    private func isLikelyUnstableLiveHLS(_ url: URL) -> Bool {
        guard !isRecordingInProgress else { return false }
        return url.pathExtension.lowercased() == "m3u8"
    }

    private func applyLiveHLSProfileIfNeeded(mpv: OpaquePointer) {
        guard !hasAppliedLiveHLSProfile else { return }
        hasAppliedLiveHLSProfile = true

        // Tune buffering/reconnect behavior for flaky live HLS feeds.
        // Goal: start faster and recover quickly rather than waiting for deep cache.
        mpv_set_property_string(mpv, "cache-secs", "12")
        mpv_set_property_string(mpv, "demuxer-readahead-secs", "6")
        mpv_set_property_string(mpv, "cache-pause-initial", "no")
        mpv_set_property_string(mpv, "cache-pause-wait", "0.2")
        mpv_set_property_string(mpv, "network-timeout", "12")
        mpv_set_property_string(mpv, "stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=2")
        mpv_set_property_string(mpv, "hls-bitrate", "min")
        print("MPV: Applied live HLS low-latency recovery profile")
    }

    private func tryNextVariantAfterSegmentError(_ logText: String) -> Bool {
        guard logText.contains("hls: Error when loading first segment") else { return false }
        guard let current = currentURL else { return false }
        guard !masterVariantCandidates.isEmpty else { return false }

        failedVariantURLs.insert(current.absoluteString)
        guard let next = masterVariantCandidates.first(where: { !failedVariantURLs.contains($0.absoluteString) }) else {
            return false
        }

        print("MPV: Switching to next HLS variant after segment error: \(next.absoluteString)")
        loadURL(next, isFallbackAttempt: true)
        return true
    }

    private func dedupeURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    private func filterReachableVariantURLs(_ urls: [URL]) async -> [URL] {
        guard !urls.isEmpty else { return [] }
        var out: [URL] = []
        for url in urls {
            if await sanityCheckVariantPlaylist(url) {
                out.append(url)
            }
        }
        return out
    }

    private func sanityCheckVariantPlaylist(_ url: URL) async -> Bool {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return false
            }
            guard let body = String(data: data, encoding: .utf8) else { return false }
            return body.contains("#EXTINF")
        } catch {
            return false
        }
    }

    private func nextRecoveryURL(current: URL) -> URL {
        let currentKey = current.absoluteString
        if !masterVariantCandidates.isEmpty {
            failedVariantURLs.insert(currentKey)
            let candidates = masterVariantCandidates.filter { !failedVariantURLs.contains($0.absoluteString) }
            if !candidates.isEmpty {
                let index = recoveryVariantCursor % candidates.count
                recoveryVariantCursor += 1
                return candidates[index]
            }
            // All variants failed once: reset and keep cycling.
            failedVariantURLs.removeAll()
            let index = recoveryVariantCursor % masterVariantCandidates.count
            recoveryVariantCursor += 1
            return masterVariantCandidates[index]
        }
        return preferredRecoveryURL(from: current)
    }

    private func shouldEmitMPVLog(level: String, text: String) -> Bool {
        let now = Date()
        let key = "\(level):\(text)"
        if lastPrintedMPVLog == key, now.timeIntervalSince(lastPrintedMPVLogAt) < 1 {
            return false
        }
        lastPrintedMPVLog = key
        lastPrintedMPVLogAt = now
        return true
    }

    private func preferredRecoveryURL(from current: URL) -> URL {
        if let primary = normalizedPrimaryMirrorURL(current), primary != current {
            return primary
        }
        if let sourceURL, sourceURL != current {
            return sourceURL
        }
        return current
    }

    private func normalizedPrimaryMirrorURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let rewritten = components.path
            .split(separator: "/")
            .map { segment -> String in
                let value = String(segment)
                if value.hasSuffix("-b"), value.count > 2 {
                    return String(value.dropLast(2))
                }
                return value
            }
            .joined(separator: "/")
        components.path = "/" + rewritten
        return components.url
    }
}