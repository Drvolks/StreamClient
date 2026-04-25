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
import OpenGL.GL
import OpenGL.GL3

// MARK: - MPVContainerView (macOS)

struct MPVContainerView: NSViewControllerRepresentable {
    typealias NSViewControllerType = NSViewController

    let url: URL
    @Binding var isPlaying: Bool
    @Binding var errorMessage: String?
    @Binding var currentPosition: Double
    @Binding var duration: Double
    @Binding var seekForward: (() -> Void)?
    @Binding var seekBackward: (() -> Void)?
    @Binding var seekToPosition: ((Double) -> Void)?
    let seekBackwardTime: Int
    let seekForwardTime: Int
    let isRecordingInProgress: Bool
    let networkEventLogger: any NetworkEventLogging

    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    @Binding var getTrackListFunc: (() -> [MPVTrack])?
    @Binding var setAudioTrackFunc: ((Int) -> Void)?
    @Binding var setSubtitleTrackFunc: ((Int?) -> Void)?
    @Binding var getSubtitleTextFunc: (() -> String?)?

    func makeNSViewController(context: Context) -> NSViewController {
        let controller: NSViewController & MPVPlayerMacOSController
        let gpuAPI = UserPreferences.load().macosGPUAPI
        if gpuAPI == .pixelbuffer {
            controller = MPVPlayerPixelBufferNSViewController()
        } else if gpuAPI == .metal {
            controller = MPVPlayerNSViewController()
        } else {
            controller = MPVPlayerNSOpenGLViewController()
        }
        controller.networkEventLogger = networkEventLogger
        _ = controller.view
        controller.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress)
        controller.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        controller.onPlaybackEnded = onPlaybackEnded
        controller.onVideoInfoUpdate = onVideoInfoUpdate
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
            self.getTrackListFunc = { controller.getTrackList() }
            self.setAudioTrackFunc = { controller.setAudioTrack($0) }
            self.setSubtitleTrackFunc = { controller.setSubtitleTrack($0) }
            self.getSubtitleTextFunc = { controller.getSubtitleText() }
        }

        return controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        guard let controller = nsViewController as? MPVPlayerMacOSController else { return }
        if isPlaying {
            controller.play()
        } else {
            controller.pause()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSViewController(_ nsViewController: NSViewController, coordinator: Coordinator) {
        (nsViewController as? MPVPlayerMacOSController)?.cleanup()
    }

    class Coordinator {
        weak var playerController: MPVPlayerMacOSController?
    }
}

// MARK: - MPVPlayerMacOSController Protocol

protocol MPVPlayerMacOSController: AnyObject {
    var networkEventLogger: any NetworkEventLogging { get set }
    var onPositionUpdate: ((Double, Double) -> Void)? { get set }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)? { get set }
    var recordingMonitor: MPVRecordingMonitor? { get }
    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool)
    func loadURL(_ url: URL)
    func play()
    func pause()
    func seek(seconds: Int)
    func seekTo(position: Double)
    func startRecordingMonitor(url: URL)
    func startPositionPolling()
    func cleanup()
    func getTrackList() -> [MPVTrack]
    func setAudioTrack(_ trackId: Int)
    func setSubtitleTrack(_ trackId: Int?)
    func getSubtitleText() -> String?
}

// MARK: - MPVPlayerNSViewController (Metal)

final class MPVPlayerNSViewController: NSViewController, MPVPlayerMacOSController {
    private var player: MPVPlayerCore?
    private let metalLayer = StableMetalLayer()
    var networkEventLogger: any NetworkEventLogging = Dependencies.networkEventLogger
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    var recordingMonitor: MPVRecordingMonitor? { player?.recordingMonitor }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        metalLayer.backgroundColor = NSColor.black.cgColor
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        // Set layer before wantsLayer for layer-hosting mode
        v.layer = metalLayer
        v.wantsLayer = true
        view = v
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateRenderSurface()
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false) {
        player = MPVPlayerCore(networkEventLogger: networkEventLogger)
        guard let success = player?.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress), success else {
            return
        }
        player?.setWindowID(metalLayer)
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

    private func updateRenderSurface() {
        let layerSize = view.bounds.size
        guard layerSize.width > 1, layerSize.height > 1 else { return }
        let scale = view.window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.frame = CGRect(origin: .zero, size: layerSize)
        let drawableSize = CGSize(
            width: max(layerSize.width * scale, 1),
            height: max(layerSize.height * scale, 1)
        )
        if metalLayer.drawableSize != drawableSize {
            metalLayer.drawableSize = drawableSize
        }
    }
}

// MARK: - MPVPlayerPixelBufferNSViewController (PixelBuffer)

final class MPVPlayerPixelBufferNSViewController: NSViewController, MPVPlayerMacOSController {
    private var player: MPVPlayerCore?
    var networkEventLogger: any NetworkEventLogging = Dependencies.networkEventLogger
    private var bridge: MPVPixelBufferBridge?
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
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
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        bridge?.displayLayer.frame = view.bounds
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false) {
        guard let bridge else { return }
        bridge.attach()

        player = MPVPlayerCore(networkEventLogger: networkEventLogger)
        guard player?.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress) == true else { return }
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

    func loadURL(_ url: URL) { player?.loadURL(url) }
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

    func cleanup() {
        player?.destroy()
        player = nil
        onPositionUpdate = nil
        onPlaybackEnded = nil
        onVideoInfoUpdate = nil
    }
}

// MARK: - MPVPlayerNSOpenGLViewController (OpenGL)

final class MPVPlayerNSOpenGLViewController: NSViewController, MPVPlayerMacOSController {
    private var glView: MPVPlayerMacOGLView!
    var networkEventLogger: any NetworkEventLogging = Dependencies.networkEventLogger {
        didSet { glView?.networkEventLogger = networkEventLogger }
    }
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    var recordingMonitor: MPVRecordingMonitor? { glView?.recordingMonitor }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        glView = MPVPlayerMacOGLView(frame: view.bounds)
        glView.networkEventLogger = networkEventLogger
        glView.autoresizingMask = [.width, .height]
        view.addSubview(glView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        glView.frame = view.bounds
        glView.handleContainerLayout()
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false) {
        glView.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress)
        glView.onPositionUpdate = { [weak self] position, duration in
            self?.onPositionUpdate?(position, duration)
        }
        glView.onPlaybackEnded = { [weak self] in
            self?.onPlaybackEnded?()
        }
        glView.onVideoInfoUpdate = { [weak self] codec, height, hwdec, audioChannels, dropped, gamma, fps in
            self?.onVideoInfoUpdate?(codec, height, hwdec, audioChannels, dropped, gamma, fps)
        }
    }

    func loadURL(_ url: URL) {
        glView.loadURL(url)
    }

    func play() {
        glView.play()
    }

    func pause() {
        glView.pause()
    }

    func seek(seconds: Int) {
        glView.seek(seconds: seconds)
    }

    func seekTo(position: Double) {
        glView.seekTo(position: position)
    }

    func startRecordingMonitor(url: URL) {
        glView.startRecordingMonitor(url: url)
    }

    func startPositionPolling() {
        glView.startPositionPolling()
    }

    func getTrackList() -> [MPVTrack] { glView.getTrackList() }
    func setAudioTrack(_ trackId: Int) { glView.setAudioTrack(trackId) }
    func setSubtitleTrack(_ trackId: Int?) { glView.setSubtitleTrack(trackId) }
    func getSubtitleText() -> String? { glView.getSubtitleText() }

    func cleanup() {
        glView.cleanup()
        onPositionUpdate = nil
        onPlaybackEnded = nil
        onVideoInfoUpdate = nil
    }
}

// MARK: - MPVPlayerMacOGLView (NSOpenGLView)

final class MPVPlayerMacOGLView: NSOpenGLView {
    private var player: MPVPlayerCore?
    var networkEventLogger: any NetworkEventLogging = Dependencies.networkEventLogger
    private var defaultFBO: GLint = -1
    let renderQueue = DispatchQueue(label: "nexuspvr.macos.opengl", qos: .userInteractive)
    var mpvGL: UnsafeMutableRawPointer?
    var needsDrawing = true
    var onPositionUpdate: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    var recordingMonitor: MPVRecordingMonitor? { player?.recordingMonitor }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, pixelFormat: Self.defaultPixelFormat())!
        autoresizingMask = [.width, .height]
        wantsBestResolutionOpenGLSurface = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class func defaultPixelFormat() -> NSOpenGLPixelFormat {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), NSOpenGLPixelFormatAttribute(32),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADepthSize), NSOpenGLPixelFormatAttribute(24),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAStencilSize), NSOpenGLPixelFormatAttribute(8),
            NSOpenGLPixelFormatAttribute(0)
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attributes) else {
            fatalError("Failed to create NSOpenGLPixelFormat")
        }
        return format
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        openGLContext?.makeCurrentContext()
        var swapInterval: GLint = 1
        openGLContext?.setValues(&swapInterval, for: .swapInterval)
        refreshViewport()
    }

    override func reshape() {
        super.reshape()
        handleContainerLayout()
    }

    override func update() {
        super.update()
        handleContainerLayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        handleContainerLayout()
    }

    func setup(errorBinding: Binding<String?>?, isRecordingInProgress: Bool = false) {
        openGLContext?.makeCurrentContext()
        refreshViewport()
        player = MPVPlayerCore(networkEventLogger: networkEventLogger)
        guard let success = player?.setup(errorBinding: errorBinding, isRecordingInProgress: isRecordingInProgress), success else {
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

    override func draw(_ dirtyRect: NSRect) {
        guard needsDrawing, let mpvGL else { return }
        openGLContext?.makeCurrentContext()

        glClearColor(0, 0, 0, 1)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))
        glGetIntegerv(UInt32(GL_FRAMEBUFFER_BINDING), &defaultFBO)

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
        openGLContext?.flushBuffer()
    }

    func loadURL(_ url: URL) {
        player?.loadURL(url)
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
        needsDrawing = false
        mpvGL = nil
        renderQueue.sync {}
        player?.destroy()
        player = nil
        onPositionUpdate = nil
        onPlaybackEnded = nil
        onVideoInfoUpdate = nil
    }

    func handleContainerLayout() {
        openGLContext?.makeCurrentContext()
        openGLContext?.update()
        refreshViewport()
        if mpvGL != nil {
            needsDisplay = true
            displayIfNeeded()
        }
    }

    private func refreshViewport() {
        let backingBounds = convertToBacking(bounds)
        let width = GLsizei(max(backingBounds.width.rounded(.down), 1))
        let height = GLsizei(max(backingBounds.height.rounded(.down), 1))
        guard width > 1, height > 1 else { return }
        glViewport(0, 0, width, height)
    }
}

// MARK: - StableMetalLayer

private nonisolated(unsafe) final class StableMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1, Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}

#endif // os(macOS)
