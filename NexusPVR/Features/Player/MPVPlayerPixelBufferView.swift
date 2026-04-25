//
//  MPVPlayerPixelBufferView.swift
//  nextpvr-apple-client
//
//  iOS/tvOS PixelBuffer view implementation — extracted from PlayerView.swift
//

#if os(iOS) || os(tvOS)

import UIKit
import SwiftUI
import AVFoundation
import MPVPixelBufferBridge

class MPVPlayerPixelBufferView: UIView {
    private let session: any ActivePlayerSessionManaging
    private let networkEventLogger: any NetworkEventLogging
    var isPaused: Bool { session.player?.isPaused ?? true }
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    var recordingMonitor: MPVRecordingMonitor? { session.player?.recordingMonitor }
    private(set) var isReconnected = false

    #if os(tvOS)
    var onPlayPause: (() -> Void)?
    var onSeekForward: (() -> Void)?
    var onSeekBackward: (() -> Void)?
    var onSelect: (() -> Void)?
    var onMenu: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onLeftArrow: (() -> Bool)?
    var onRightArrow: (() -> Bool)?
    var onDownArrow: (() -> Bool)?
    var onSelectOverride: (() -> Bool)?
    var onMenuOverride: (() -> Bool)?
    override var canBecomeFocused: Bool { true }
    #endif

    init(frame: CGRect, session: any ActivePlayerSessionManaging, networkEventLogger: any NetworkEventLogging) {
        self.session = session
        self.networkEventLogger = networkEventLogger
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        self.session = Dependencies.playerSession
        self.networkEventLogger = Dependencies.networkEventLogger
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let displayLayer = session.displayLayer
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.frame = bounds
        layer.addSublayer(displayLayer)

        #if os(tvOS)
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if session.displayLayer.superlayer !== layer {
            layer.addSublayer(session.displayLayer)
        }
        session.displayLayer.frame = bounds
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false) {
        if session.hasActiveSession {
            isReconnected = true
            wireCallbacks()
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackEnded = nil // Don't re-trigger ended on reconnect
            }
            return
        }

        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let bridge = MPVPixelBufferBridge(displayLayer: session.displayLayer)
        bridge.attach()

        let player = MPVPlayerCore(networkEventLogger: networkEventLogger)
        guard player.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress) else {
            return
        }

        session.createSession(player: player, bridge: bridge)
        wireCallbacks()
    }

    private func wireCallbacks() {
        session.player?.onPositionUpdate = { [weak self] position, duration in
            self?.onPositionUpdate?(position, duration)
        }
        session.player?.onPlaybackEnded = { [weak self] in
            self?.onPlaybackEnded?()
        }
        session.player?.onVideoInfoUpdate = { [weak self] codec, width, hwdec, audioChannels, dropped, gamma, fps in
            self?.onVideoInfoUpdate?(codec, width, hwdec, audioChannels, dropped, gamma, fps)
        }
    }

    func loadURL(_ url: URL) {
        guard !isReconnected else { return }
        session.player?.loadURL(url)
    }

    func play() { session.player?.play() }
    func pause() { session.player?.pause() }

    func seek(seconds: Int) {
        session.player?.seek(seconds: seconds)
        Task { @MainActor in session.bridge?.flush() }
    }

    func seekTo(position: Double) {
        session.player?.seekTo(position: position)
        Task { @MainActor in session.bridge?.flush() }
    }

    func startRecordingMonitor(url: URL) {
        session.player?.startRecordingMonitor(url: url)
    }

    func startPositionPolling() {
        session.player?.startPositionPolling()
    }

    func getTrackList() -> [MPVTrack] { session.player?.getTrackList() ?? [] }
    func setAudioTrack(_ trackId: Int) { session.player?.setAudioTrack(trackId) }
    func setSubtitleTrack(_ trackId: Int?) { session.player?.setSubtitleTrack(trackId) }
    func getSubtitleText() -> String? { session.player?.getSubtitleText() }

    func cleanup() {
        if session.isPiPActive {
            session.detachFromView()
            onPositionUpdate = nil
            onPlaybackEnded = nil
            onVideoInfoUpdate = nil
            return
        }
        session.teardown()
        onPositionUpdate = nil
        onPlaybackEnded = nil
        onVideoInfoUpdate = nil
    }

    #if os(tvOS)
    private var seekTimer: Timer?
    private var seekDirection: Int = 0

    private func startSeeking(direction: Int) {
        stopSeeking()
        seekDirection = direction
        if direction < 0 {
            onSeekBackward?()
        } else {
            onSeekForward?()
        }
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.seekDirection < 0 {
                self.onSeekBackward?()
            } else {
                self.onSeekForward?()
            }
        }
    }

    private func stopSeeking() {
        seekTimer?.invalidate()
        seekTimer = nil
        seekDirection = 0
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async {
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .left:
            if onLeftArrow?() != true {
                onSeekBackward?()
            }
        case .right:
            if onRightArrow?() != true {
                onSeekForward?()
            }
        case .up:
            onUpArrow?()
        case .down:
            _ = onDownArrow?()
        default:
            break
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .playPause:
                onPlayPause?()
                return
            case .leftArrow:
                if onLeftArrow?() != true {
                    startSeeking(direction: -1)
                }
                return
            case .rightArrow:
                if onRightArrow?() != true {
                    startSeeking(direction: 1)
                }
                return
            case .upArrow:
                onUpArrow?()
                return
            case .downArrow:
                onDownArrow?()
                return
            case .select:
                if onSelectOverride?() != true {
                    onSelect?()
                }
                return
            case .menu:
                print("[tvOS] menu pressed, hasOverride=\(onMenuOverride != nil)")
                if onMenuOverride?() != true {
                    onMenu?()
                }
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .leftArrow || press.type == .rightArrow {
                return
            }
        }
        super.pressesChanged(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .leftArrow || press.type == .rightArrow {
                stopSeeking()
                return
            }
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopSeeking()
        super.pressesCancelled(presses, with: event)
    }
    #endif
}

#endif // os(iOS) || os(tvOS)
