//
//  MPVPlayerGLView.swift
//  nextpvr-apple-client
//
//  iOS/tvOS OpenGL ES view implementation — extracted from PlayerView.swift
//

#if os(iOS) || os(tvOS)

import UIKit
import SwiftUI
import GLKit
import OpenGLES
import Libmpv

class MPVPlayerGLView: GLKView {
    private var player: MPVPlayerCore?
    private let networkEventLogger: any NetworkEventLogging
    private var defaultFBO: GLint = -1
    nonisolated(unsafe) private var displayLink: CADisplayLink?
    private var resizeDebouncer: DispatchWorkItem?
    private var isResizing = false
    var mpvGL: UnsafeMutableRawPointer?
    var needsDrawing = true
    let renderQueue = DispatchQueue(label: "nexuspvr.opengl", qos: .userInteractive)
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    var recordingMonitor: MPVRecordingMonitor? { player?.recordingMonitor }
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

    init(frame: CGRect, networkEventLogger: any NetworkEventLogging) {
        self.networkEventLogger = networkEventLogger
        guard let glContext = EAGLContext(api: .openGLES2) else {
            fatalError("Failed to initialize OpenGL ES 2.0 context")
        }
        super.init(frame: frame, context: glContext)
        commonInit()
    }

    override init(frame: CGRect, context: EAGLContext) {
        self.networkEventLogger = Dependencies.networkEventLogger
        super.init(frame: frame, context: context)
        commonInit()
    }

    required init?(coder: NSCoder) {
        self.networkEventLogger = Dependencies.networkEventLogger
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        bindDrawable()
        isOpaque = true
        enableSetNeedsDisplay = false
        backgroundColor = .black
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Fill black initially
        glClearColor(0, 0, 0, 1)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))

        // Display link for frame sync
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)

        #if os(tvOS)
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
        #endif
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func updateFrame() {
        guard !isResizing, mpvGL != nil else { return }
        display()
    }

    override func draw(_ rect: CGRect) {
        guard !isResizing, let mpvGL = mpvGL else { return }

        guard EAGLContext.setCurrent(context) else { return }

        glGetIntegerv(UInt32(GL_FRAMEBUFFER_BINDING), &defaultFBO)
        guard defaultFBO != 0 else { return }

        var dims: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &dims)

        var data = mpv_opengl_fbo(
            fbo: Int32(defaultFBO),
            w: Int32(dims[2]),
            h: Int32(dims[3]),
            internal_format: 0
        )

        var flip: CInt = 1

        withUnsafeMutablePointer(to: &flip) { flipPtr in
            withUnsafeMutablePointer(to: &data) { dataPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: dataPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param()
                ]
                mpv_render_context_render(OpaquePointer(mpvGL), &params)
            }
        }

    }


    override func layoutSubviews() {
        super.layoutSubviews()
        // During orientation animation, layoutSubviews fires on every frame.
        // Skip MPV renders during the resize — the last rendered frame scales
        // naturally via UIKit's animation. Re-render once the size settles.
        resizeDebouncer?.cancel()
        isResizing = true
        let work = DispatchWorkItem { [weak self] in
            self?.isResizing = false
            self?.needsDrawing = true
        }
        resizeDebouncer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false, recordingStartTime: Date? = nil) {
        player = MPVPlayerCore(networkEventLogger: networkEventLogger)
        guard let success = player?.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress, recordingStartTime: recordingStartTime), success else {
            return
        }
        player?.createRenderContext(view: self)
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
        // Stop new frames from being queued
        needsDrawing = false
        displayLink?.invalidate()
        displayLink = nil
        // Nil out render context pointer so any in-flight draw() exits early
        mpvGL = nil
        // Wait for any pending render to finish before destroying
        renderQueue.sync {}
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
