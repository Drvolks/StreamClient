//
//  MPVPlayerMetalView.swift
//  nextpvr-apple-client
//
//  iOS/tvOS Metal view implementation — extracted from PlayerView.swift
//

#if os(iOS) || os(tvOS)

import UIKit
import SwiftUI
import AVFoundation

class MPVPlayerMetalView: UIView {
    private var player: MPVPlayerCore?
    private var metalLayer: CAMetalLayer?
    private let networkEventLogger: any NetworkEventLogging
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    var recordingMonitor: MPVRecordingMonitor? { player?.recordingMonitor }

    #if os(tvOS)
    // tvOS remote control callbacks
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
    #endif

    override class var layerClass: AnyClass { CAMetalLayer.self }

    #if os(tvOS)
    override var canBecomeFocused: Bool { true }
    #endif

    init(frame: CGRect, networkEventLogger: any NetworkEventLogging) {
        self.networkEventLogger = networkEventLogger
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        self.networkEventLogger = Dependencies.networkEventLogger
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        metalLayer = layer as? CAMetalLayer
        metalLayer?.backgroundColor = UIColor.black.cgColor
        metalLayer?.pixelFormat = .bgra8Unorm
        isOpaque = true
        clipsToBounds = true
        backgroundColor = .black
        isUserInteractionEnabled = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        updateDrawableSize()

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
        metalLayer?.frame = bounds
        updateDrawableSize()
        #if os(iOS)
        if let metalLayer = metalLayer {
            player?.setWindowID(metalLayer)
        }
        #endif
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let metalLayer else { return }
        #if os(iOS)
        let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        #else
        let scale = UIScreen.main.scale
        #endif
        metalLayer.contentsScale = scale

        let drawableWidth = max(bounds.width * scale, 1)
        let drawableHeight = max(bounds.height * scale, 1)
        let drawableSize = CGSize(width: drawableWidth, height: drawableHeight)
        if metalLayer.drawableSize != drawableSize {
            metalLayer.drawableSize = drawableSize
        }
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false, recordingStartTime: Date? = nil) {
        player = MPVPlayerCore(networkEventLogger: networkEventLogger)
        guard let success = player?.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress, recordingStartTime: recordingStartTime), success else {
            return
        }
        if let metalLayer = metalLayer {
            player?.setWindowID(metalLayer)
        }
        player?.onPositionUpdate = { [weak self] position, duration in
            self?.onPositionUpdate?(position, duration)
        }
        player?.onPlaybackEnded = { [weak self] in
            self?.onPlaybackEnded?()
        }
        player?.onVideoInfoUpdate = { [weak self] codec, height, hwdec, audioChannels, dropped, gamma, fps in
            self?.onVideoInfoUpdate?(codec, height, hwdec, audioChannels, dropped, gamma, fps)
        }
    }

    func loadURL(_ url: URL) {
        player?.loadURL(url)
    }

    func setStreamHeaders(_ headers: [String: String]) {
        player?.setStreamHeaders(headers)
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func seek(seconds: Int) {
        player?.seek(seconds: seconds)
    }

    func seekTo(position: Double) {
        player?.seekTo(position: position)
    }

    func startRecordingMonitor(url: URL) {
        player?.startRecordingMonitor(url: url)
    }

    func startPositionPolling() {
        player?.startPositionPolling()
    }

    func getTrackList() -> [MPVTrack] { player?.getTrackList() ?? [] }
    func setAudioTrack(_ trackId: Int) { player?.setAudioTrack(trackId) }
    func setSubtitleTrack(_ trackId: Int?) { player?.setSubtitleTrack(trackId) }
    func getSubtitleText() -> String? { player?.getSubtitleText() }

    func cleanup() {
        player?.destroy()
        player = nil
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
