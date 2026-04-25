import AVFoundation
import MPVPixelBufferBridge

/// Protocol for active player session management — allows test doubles and alternative implementations.
@MainActor
protocol ActivePlayerSessionManaging: AnyObject {
    var player: MPVPlayerCore? { get }
    var bridge: MPVPixelBufferBridge? { get }
    var pipController: PiPController? { get }
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var isPiPActive: Bool { get set }
    var dismissingForPiP: Bool { get set }
    var hasActiveSession: Bool { get }

    func createSession(player: MPVPlayerCore, bridge: MPVPixelBufferBridge)
    func setupPiP(playPauseHandler: @escaping (Bool) -> Void, isPausedQuery: @escaping () -> Bool)
    func detachFromView()
    func teardown()
}

/// Singleton that holds the mpv player, bridge, and PiP controller so they
/// survive SwiftUI view lifecycle (fullScreenCover dismiss/dismantle).
/// Only used for the pixelbuffer renderer path.
@MainActor
final class ActivePlayerSession: ActivePlayerSessionManaging {
    private(set) var player: MPVPlayerCore?
    private(set) var bridge: MPVPixelBufferBridge?
    private(set) var pipController: PiPController?
    let displayLayer = AVSampleBufferDisplayLayer()

    var isPiPActive: Bool = false
    var dismissingForPiP: Bool = false
    private var restoringFromPiP: Bool = false

    init() {}

    func createSession(player: MPVPlayerCore, bridge: MPVPixelBufferBridge) {
        if self.player != nil {
            teardown()
        }
        self.player = player
        self.bridge = bridge
    }

    func setupPiP(playPauseHandler: @escaping (Bool) -> Void,
                  isPausedQuery: @escaping () -> Bool) {
        guard pipController == nil, let bridge else { return }

        let delegate = PiPPlaybackDelegate()
        delegate.onSetPlaying = playPauseHandler
        delegate.isPaused = isPausedQuery
        let controller = PiPController(bridge: bridge, playbackDelegate: delegate)
        controller.onStopped = { [weak self] _ in
            guard let self else { return }
            self.isPiPActive = false
            self.dismissingForPiP = false
            if self.restoringFromPiP {
                self.restoringFromPiP = false
            } else {
                self.teardown()
            }
        }
        controller.onRestoreUserInterface = { [weak self] completion in
            guard let self else { completion(true); return }
            self.restoringFromPiP = true
            self.isPiPActive = false
            self.dismissingForPiP = false
            NotificationCenter.default.post(name: .restoreFromPiP, object: nil)
            completion(true)
        }
        pipController = controller
    }

    func detachFromView() {
        player?.onPositionUpdate = nil
        player?.onPlaybackEnded = nil
        player?.onVideoInfoUpdate = nil
    }

    func teardown() {
        pipController?.invalidate()
        pipController = nil
        isPiPActive = false
        dismissingForPiP = false
        restoringFromPiP = false
        player?.destroy()
        player = nil
        bridge = nil
    }

    var hasActiveSession: Bool {
        player != nil && bridge != nil
    }
}

extension Notification.Name {
    static let restoreFromPiP = Notification.Name("restoreFromPiP")
}
