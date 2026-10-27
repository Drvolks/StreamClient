//
//  MPVContainerView+macOS.swift
//  nextpvr-apple-client
//
//  macOS MPVContainerView and controller implementations — extracted from PlayerView.swift
//

#if os(macOS)

import AppKit
import SwiftUI
import AVFoundation
import QuartzCore
import Libmpv
import MPVPixelBufferBridge

// MARK: - MPVContainerView (macOS)

struct MPVContainerView: NSViewControllerRepresentable {
    typealias NSViewControllerType = MPVPlayerPixelBufferNSViewController

    let url: URL
    @Binding var isPlaying: Bool
    @Binding var errorMessage: String?
    @Binding var currentPosition: Double
    @Binding var duration: Double
    @Binding var seekForward: (() -> Void)?
    @Binding var seekBackward: (() -> Void)?
    @Binding var seekToPosition: ((Double) -> Void)?
    @Binding var reloadURL: ((URL) -> Void)?
    let seekBackwardTime: Int
    let seekForwardTime: Int
    let isRecordingInProgress: Bool
    let recordingStartTime: Date?
    let preferKeyframeSeek: Bool
    let streamHeaders: [String: String]
    let networkEventLogger: any NetworkEventLogging

    var onPlaybackEnded: (() -> Void)?
    var onPlaybackRestarted: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    @Binding var getTrackListFunc: (() -> [MPVTrack])?
    @Binding var setAudioTrackFunc: ((Int) -> Void)?
    @Binding var setSubtitleTrackFunc: ((Int?) -> Void)?
    @Binding var getSubtitleTextFunc: (() -> String?)?
    @Binding var setMutedFunc: ((Bool) -> Void)?
    @Binding var isMuted: Bool

    func makeNSViewController(context: Context) -> MPVPlayerPixelBufferNSViewController {
        let controller = MPVPlayerPixelBufferNSViewController()
        controller.networkEventLogger = networkEventLogger
        _ = controller.view
        controller.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress, recordingStartTime: recordingStartTime, preferKeyframeSeek: preferKeyframeSeek)
        controller.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        controller.onPlaybackEnded = onPlaybackEnded
        controller.onPlaybackRestarted = onPlaybackRestarted
        controller.onVideoInfoUpdate = onVideoInfoUpdate
        controller.setStreamHeaders(streamHeaders)
        controller.loadURL(url)
        controller.startPositionPolling()
        if isRecordingInProgress {
            controller.startRecordingMonitor(url: url)
            controller.recordingMonitor?.onRecordingFinished = {
                print("Recording completed, normal playback mode")
            }
        }
        context.coordinator.playerController = controller

        // Set up seek and playlist closures
        DispatchQueue.main.async {
            self.seekForward = {
                controller.seek(seconds: self.seekForwardTime)
            }
            self.seekBackward = {
                controller.seek(seconds: -self.seekBackwardTime)
            }
            self.seekToPosition = { position in
                controller.seekTo(position: position)
            }
            self.reloadURL = { newURL in
                controller.loadURL(newURL)
            }
            self.getTrackListFunc = { controller.getTrackList() }
            self.setAudioTrackFunc = { controller.setAudioTrack($0) }
            self.setSubtitleTrackFunc = { controller.setSubtitleTrack($0) }
            self.getSubtitleTextFunc = { controller.getSubtitleText() }
            self.setMutedFunc = { controller.setMuted($0) }
            self.isMuted = controller.isMuted
        }

        return controller
    }

    func updateNSViewController(_ controller: MPVPlayerPixelBufferNSViewController, context: Context) {
        if isPlaying {
            controller.play()
        } else {
            controller.pause()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSViewController(_ controller: MPVPlayerPixelBufferNSViewController, coordinator: Coordinator) {
        controller.cleanup()
    }

    class Coordinator {
        weak var playerController: MPVPlayerPixelBufferNSViewController?
    }
}

// MARK: - MPVPlayerPixelBufferNSViewController

final class MPVPlayerPixelBufferNSViewController: NSViewController {
    private var player: MPVPlayerCore?
    var networkEventLogger: any NetworkEventLogging = Dependencies.networkEventLogger
    private var bridge: MPVPixelBufferBridge?
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onPlaybackRestarted: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    var recordingMonitor: MPVRecordingMonitor? { player?.recordingMonitor }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        // Set layer before wantsLayer for layer-hosting mode
        v.layer = CALayer()
        v.wantsLayer = true
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let displayLayer = AVSampleBufferDisplayLayer()
        bridge = MPVPixelBufferBridge(displayLayer: displayLayer)
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(displayLayer)
        // Fired on mpv's VO thread when the video format changes; the new
        // aspect ratio only becomes readable at that point.
        bridge?.onReconfig = { [weak self] _, _, _ in
            self?.updateDisplayLayerGeometryOnMain()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateDisplayLayerGeometry()
    }

    /// Callable from mpv's threads — the geometry update itself is main-thread only.
    private nonisolated func updateDisplayLayerGeometryOnMain() {
        MPVPlayerCore.scheduleOnMain { [weak self] in
            self?.updateDisplayLayerGeometry()
        }
    }

    /// The pixelbuffer VO delivers frames at the coded resolution with no
    /// sample-aspect metadata, so anamorphic streams would render squeezed if
    /// the layer simply fit the pixel grid. Size the layer to mpv's display
    /// aspect and let the frames fill it instead (#152). Falls back to plain
    /// aspect-fit while the aspect is still unknown.
    private func updateDisplayLayerGeometry() {
        guard let displayLayer = bridge?.displayLayer else { return }
        if let aspect = player?.videoDisplayAspect {
            displayLayer.videoGravity = .resize
            displayLayer.frame = VideoAspectCorrection.fittedRect(displayAspect: aspect, in: view.bounds)
        } else {
            displayLayer.videoGravity = .resizeAspect
            displayLayer.frame = view.bounds
        }
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false, recordingStartTime: Date? = nil, preferKeyframeSeek: Bool = false) {
        guard let bridge else { return }
        bridge.attach()

        player = MPVPlayerCore(networkEventLogger: networkEventLogger)
        guard player?.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress, recordingStartTime: recordingStartTime, preferKeyframeSeek: preferKeyframeSeek) == true else { return }
        player?.onPositionUpdate = { [weak self] position, duration in
            self?.onPositionUpdate?(position, duration)
        }
        player?.onPlaybackEnded = { [weak self] in
            self?.onPlaybackEnded?()
        }
        player?.onPlaybackRestarted = { [weak self] in
            self?.onPlaybackRestarted?()
        }
        player?.onVideoInfoUpdate = { [weak self] codec, height, hwdec, audioChannels, dropped, gamma, fps in
            // Safety net in case the aspect wasn't readable yet at reconfig
            // time; this callback can arrive off the main thread.
            self?.updateDisplayLayerGeometryOnMain()
            self?.onVideoInfoUpdate?(codec, height, hwdec, audioChannels, dropped, gamma, fps)
        }
    }

    func loadURL(_ url: URL) { player?.loadURL(url) }
    func setStreamHeaders(_ headers: [String: String]) { player?.setStreamHeaders(headers) }
    func play() { player?.play() }
    func pause() { player?.pause() }

    func seek(seconds: Int) {
        player?.seek(seconds: seconds)
        Task { @MainActor in bridge?.flush() }
    }

    func seekTo(position: Double) {
        player?.seekTo(position: position)
        Task { @MainActor in bridge?.flush() }
    }

    func startRecordingMonitor(url: URL) {
        player?.startRecordingMonitor(url: url)
    }

    func startPositionPolling() { player?.startPositionPolling() }

    func getTrackList() -> [MPVTrack] { player?.getTrackList() ?? [] }
    func setAudioTrack(_ trackId: Int) { player?.setAudioTrack(trackId) }
    func setSubtitleTrack(_ trackId: Int?) { player?.setSubtitleTrack(trackId) }
    func getSubtitleText() -> String? { player?.getSubtitleText() }
    func setMuted(_ muted: Bool) { player?.setMuted(muted) }
    var isMuted: Bool { player?.isMuted ?? false }

    func cleanup() {
        player?.destroy()
        player = nil
        onPositionUpdate = nil
        onPlaybackEnded = nil
        onPlaybackRestarted = nil
        onVideoInfoUpdate = nil
    }
}

#endif // os(macOS)
