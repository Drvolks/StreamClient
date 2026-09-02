//  PlayerView.swift
//  nextpvr-apple-client
//
//  Video player view using MPV for MPEG-TS support
//

import SwiftUI
import Libmpv
import MPVPixelBufferBridge
import AVFoundation
import AVKit
#if !os(macOS)
import GLKit
import OpenGLES
#endif
#if os(macOS)
import AppKit
import IOKit.pwr_mgt
import OpenGL.GL
import OpenGL.GL3
#else
import UIKit
#endif

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var client: PVRClient

    let url: URL
    let title: String
    let recordingId: Int?
    let resumePosition: Int?
    let isRecordingInProgress: Bool
    let recordingStartTime: Date?
    /// Dispatcharr catch-up session id (#119), when this stream is archived
    /// playback rather than live TV. Drives `isLiveStream` (catch-up gets
    /// the recording-style seek bar, not the live-edge one) and is revoked
    /// server-side on teardown — see `endCatchupSessionIfNeeded()`.
    let catchupSessionId: String?
    /// The programme `catchupSessionId` was minted for (#150). Present for
    /// Dispatcharr catch-up playback; lets the player mint the next session in
    /// the chain when the archive ends while the programme is still airing.
    let catchupProgram: CatchupProgramContext?

    // Injected dependencies (default to app singletons via Dependencies)
    private let activePlayerSession: any ActivePlayerSessionManaging
    private let networkEventLogger: any NetworkEventLogging
    private let liveKeepalive: LiveStreamKeepalive

    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isPlaying = true
    @State private var errorMessage: String?
    @State private var currentPosition: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0
    @State private var seekBackwardTime: Int = UserPreferences.load().seekBackwardSeconds
    @State private var seekForwardTime: Int = UserPreferences.load().seekForwardSeconds
    @State private var seekForward: (() -> Void)?
    @State private var seekBackward: (() -> Void)?
    @State private var seekToPositionFunc: ((Double) -> Void)?
    @State private var cleanupAction: (() -> Void)?
    @State private var hasResumed = false
    @State private var isPlayerReady = false
    @State private var startTimeOffset: Double = 0
    @State private var videoCodec: String?
    @State private var videoHeight: Int?
    @State private var hwDecoder: String?
    @State private var audioChannelLayout: String?
    @State private var droppedFrames: Int64 = 0
    @State private var videoGamma: String?
    @State private var showSettingsPanel = false
    @State private var settingsTab: StreamSettingsTab = .video
    @State private var trackList: [MPVTrack] = []
    @State private var getTrackListFunc: (() -> [MPVTrack])?
    @State private var setAudioTrackFunc: ((Int) -> Void)?
    @State private var setSubtitleTrackFunc: ((Int?) -> Void)?
    @State private var getSubtitleTextFunc: (() -> String?)?
    @State private var currentSubtitleText: String?
    #if os(iOS) || os(macOS)
    @State private var setMutedFunc: ((Bool) -> Void)?
    @State private var isMuted = false
    #endif
    #if os(tvOS)
    @State private var tvFocusedTrackIndex: Int = -1  // -1 = tabs focused, 0+ = track list index
    #endif
    @State private var reloadURLFunc: ((URL) -> Void)?
    /// Latest server-side buffer state, plus when it arrived so the live edge can be
    /// extrapolated between polls (the buffer grows in real time).
    @State private var liveStreamInfo: LiveStreamInfo?
    @State private var liveStreamInfoAt: Date = .distantPast
    /// Where playback sits inside the server-side buffer. Integrated from mpv's
    /// position rather than read off it, since mpv's origin shifts under us —
    /// see `LivePositionTracker` (#148).
    @State private var liveTracker = LivePositionTracker()
    @State private var isLiveSeeking = false
    /// Target of skip presses not yet committed to a reload — see `seekLiveBy`.
    @State private var pendingLiveSeekTarget: Double?
    @State private var liveSeekCommitTask: Task<Void, Never>?
    /// When the last live reload was issued, and how many times we've retried it
    /// after an immediate EOF — see `recoverFromLiveEdgeEOF()`.
    @State private var lastLiveSeekAt: Date = .distantPast
    @State private var liveEdgeRetryCount = 0
    @State private var isBuffering = false
    @State private var lastBufferingCheckPosition: Double = -1
    /// True from the moment a catch-up (#119) seek is triggered until mpv
    /// reports playback restarted. Catch-up seeks land on an unindexed,
    /// variable-bitrate remote stream — mpv has to do dozens of real
    /// network round-trips to locate the byte position, so this can take
    /// tens of seconds (confirmed via mpv's own verbose log, independent of
    /// the app). This just makes that wait read as "seeking" instead of a
    /// frozen player. Unrelated to `isBuffering`, which is
    /// isRecordingInProgress-only and never applies to catch-up.
    @State private var isCatchupSeeking = false
    @State private var catchupSeekSafetyTask: Task<Void, Never>?
    /// Seconds of the programme played by *earlier* catch-up sessions in this
    /// continuation chain (#150). Stays 0 until the first remint, so every
    /// display and seek expression below is unchanged for a single-session
    /// playback.
    @State private var catchupPlayedOffset: Double = 0
    /// The session currently feeding the player. Diverges from
    /// `catchupSessionId` after the first continuation remint.
    @State private var activeCatchupSessionId: String?
    @State private var catchupContinuationTask: Task<Void, Never>?
    @State private var isContinuingCatchup = false
    @State private var catchupShortSessionCount = 0
    /// Set across a continuation reload: the replacement stream has its own PTS
    /// base, so `startTimeOffset` has to be recaptured from it.
    @State private var pendingCatchupRebase = false
    @State private var bufferingStallCount = 0
    #if DISPATCHERPVR
    @State private var dispatchProfileBadge: String?
    @State private var dispatchProfileRefreshTask: Task<Void, Never>?
    #endif
    #if os(tvOS)
    @State private var hasSetDisplayCriteria = false
    #endif
    #if os(iOS)
    @State private var pipIsSupported = AVPictureInPictureController.isPictureInPictureSupported()
    @State private var pipIsActive = false
    #endif
    #if !os(macOS)
    @State private var pixelBufferView: MPVPlayerPixelBufferView? = nil
    #endif
    #if os(macOS)
    @State private var sleepAssertionID: IOPMAssertionID = 0
    @State private var heldAssertion: PlayerPowerAssertion = .none
    #endif

    init(
        url: URL,
        title: String,
        recordingId: Int? = nil,
        resumePosition: Int? = nil,
        isRecordingInProgress: Bool = false,
        recordingStartTime: Date? = nil,
        catchupSessionId: String? = nil,
        catchupProgram: CatchupProgramContext? = nil,
        activePlayerSession: any ActivePlayerSessionManaging = Dependencies.activePlayerSession,
        networkEventLogger: any NetworkEventLogging = Dependencies.networkEventLogger,
        liveKeepalive: LiveStreamKeepalive = Dependencies.liveStreamKeepalive
    ) {
        self.url = url
        self.title = title
        self.recordingId = recordingId
        self.resumePosition = resumePosition
        self.isRecordingInProgress = isRecordingInProgress
        self.recordingStartTime = recordingStartTime
        self.catchupSessionId = catchupSessionId
        self.catchupProgram = catchupProgram
        self.activePlayerSession = activePlayerSession
        self.networkEventLogger = networkEventLogger
        self.liveKeepalive = liveKeepalive
    }

    var body: some View {
        ZStack {
            // MPV Video player
            #if os(tvOS)
            MPVContainerView(
                url: url,
                isPlaying: $isPlaying,
                errorMessage: $errorMessage,
                currentPosition: $currentPosition,
                duration: $duration,
                seekForward: $seekForward,
                seekBackward: $seekBackward,
                seekToPosition: $seekToPositionFunc,
                reloadURL: $reloadURLFunc,
                seekBackwardTime: seekBackwardTime,
                seekForwardTime: seekForwardTime,
                isRecordingInProgress: isRecordingInProgress,
                recordingStartTime: recordingStartTime,
                preferKeyframeSeek: catchupSessionId != nil,
                streamHeaders: client.streamAuthHeaders(),
                activePlayerSession: activePlayerSession,
                networkEventLogger: networkEventLogger,
                onPlaybackEnded: {
                    handlePlaybackEnded()
                },
                onPlaybackRestarted: {
                    endCatchupSeekIndicator()
                },
                onLiveSeek: isLiveStream ? { delta in
                    guard canSeekLive else { return false }
                    seekLiveBy(delta)
                    return true
                } : nil,
                onCatchupSeekStarted: {
                    startCatchupSeekIndicatorIfNeeded()
                },
                onTogglePlayPause: {
                    isPlaying.toggle()
                    showControls = true
                    scheduleHideControls()
                },
                onToggleControls: {
                    toggleControls()
                },
                onShowControls: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = true
                    }
                    scheduleHideControls()
                },
                onDismiss: {
                    savePlaybackPosition()
                    appState.stopPlayback()
                },
                onOpenSettings: {
                    if showSettingsPanel {
                        // Already open: navigate up in track list or close
                        if tvFocusedTrackIndex >= 0 {
                            tvFocusedTrackIndex -= 1
                        } else {
                            dismissSettingsPanel()
                            tvFocusedTrackIndex = -1
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSettingsPanel = true
                        }
                        trackList = getTrackListFunc?() ?? []
                        showControls = true
                        hideControlsTask?.cancel()
                        tvFocusedTrackIndex = -1
                    }
                },
                onVideoInfoUpdate: { codec, height, hwdec, audioChannels, dropped, gamma, fps in
                    videoCodec = codec
                    videoHeight = height
                    hwDecoder = hwdec
                    audioChannelLayout = audioChannels
                    droppedFrames = dropped
                    videoGamma = gamma
                    #if os(tvOS)
                    updateDisplayCriteriaIfNeeded(gamma: gamma, fps: fps)
                    #endif
                },
                cleanupAction: $cleanupAction,
                getTrackListFunc: $getTrackListFunc,
                setAudioTrackFunc: $setAudioTrackFunc,
                setSubtitleTrackFunc: $setSubtitleTrackFunc,
                getSubtitleTextFunc: $getSubtitleTextFunc,
                showSettingsPanel: $showSettingsPanel,
                settingsTab: $settingsTab,
                tvFocusedTrackIndex: $tvFocusedTrackIndex,
                tvTrackCountProvider: { tvTrackCount },
                tvSelectTrack: { tvSelectFocusedTrack() },
                onDismissSettingsPanel: {
                    dismissSettingsPanel()  // sets showSettingsPanel = false AND re-schedules hide
                    tvFocusedTrackIndex = -1
                }
            )
                .ignoresSafeArea()
            #elseif os(iOS)
            MPVContainerView(
                url: url,
                isPlaying: $isPlaying,
                errorMessage: $errorMessage,
                currentPosition: $currentPosition,
                duration: $duration,
                seekForward: $seekForward,
                seekBackward: $seekBackward,
                seekToPosition: $seekToPositionFunc,
                reloadURL: $reloadURLFunc,
                seekBackwardTime: seekBackwardTime,
                seekForwardTime: seekForwardTime,
                isRecordingInProgress: isRecordingInProgress,
                recordingStartTime: recordingStartTime,
                preferKeyframeSeek: catchupSessionId != nil,
                streamHeaders: client.streamAuthHeaders(),
                activePlayerSession: activePlayerSession,
                networkEventLogger: networkEventLogger,
                onPlaybackEnded: {
                    handlePlaybackEnded()
                },
                onPlaybackRestarted: {
                    endCatchupSeekIndicator()
                },
                onVideoInfoUpdate: { codec, height, hwdec, audioChannels, dropped, gamma, fps in
                    videoCodec = codec
                    videoHeight = height
                    hwDecoder = hwdec
                    audioChannelLayout = audioChannels
                    droppedFrames = dropped
                    videoGamma = gamma
                    #if os(tvOS)
                    updateDisplayCriteriaIfNeeded(gamma: gamma, fps: fps)
                    #endif
                },
                cleanupAction: $cleanupAction,
                pixelBufferViewRef: $pixelBufferView,
                getTrackListFunc: $getTrackListFunc,
                setAudioTrackFunc: $setAudioTrackFunc,
                setSubtitleTrackFunc: $setSubtitleTrackFunc,
                getSubtitleTextFunc: $getSubtitleTextFunc,
                setMutedFunc: $setMutedFunc,
                isMuted: $isMuted
            )
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }
                .onChange(of: pixelBufferView != nil) { hasView in
                    if hasView { setupNativePiPIfNeeded() }
                }
                .onChange(of: isPlayerReady) { ready in
                    if ready { setupNativePiPIfNeeded() }
                }
            #else
            MPVContainerView(
                url: url,
                isPlaying: $isPlaying,
                errorMessage: $errorMessage,
                currentPosition: $currentPosition,
                duration: $duration,
                seekForward: $seekForward,
                seekBackward: $seekBackward,
                seekToPosition: $seekToPositionFunc,
                reloadURL: $reloadURLFunc,
                seekBackwardTime: seekBackwardTime,
                seekForwardTime: seekForwardTime,
                isRecordingInProgress: isRecordingInProgress,
                recordingStartTime: recordingStartTime,
                preferKeyframeSeek: catchupSessionId != nil,
                streamHeaders: client.streamAuthHeaders(),
                networkEventLogger: networkEventLogger,
                onPlaybackEnded: {
                    handlePlaybackEnded()
                },
                onPlaybackRestarted: {
                    endCatchupSeekIndicator()
                },
                onVideoInfoUpdate: { codec, height, hwdec, audioChannels, dropped, gamma, fps in
                    videoCodec = codec
                    videoHeight = height
                    hwDecoder = hwdec
                    audioChannelLayout = audioChannels
                    droppedFrames = dropped
                    videoGamma = gamma
                    #if os(tvOS)
                    updateDisplayCriteriaIfNeeded(gamma: gamma, fps: fps)
                    #endif
                },
                getTrackListFunc: $getTrackListFunc,
                setAudioTrackFunc: $setAudioTrackFunc,
                setSubtitleTrackFunc: $setSubtitleTrackFunc,
                getSubtitleTextFunc: $getSubtitleTextFunc,
                setMutedFunc: $setMutedFunc,
                isMuted: $isMuted
            )
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }
                #if os(macOS)
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        if !showControls {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls = true
                            }
                        }
                        NSCursor.setHiddenUntilMouseMoves(false)
                        scheduleHideControls()
                    case .ended:
                        break
                    }
                }
                #endif
            #endif

            // Loading overlay - hide video until ready (prevents seeing start before resume)
            if !isPlayerReady {
                ZStack {
                    Color.black
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    #if !os(tvOS)
                    // Close button always available, even while loading
                    VStack {
                        HStack {
                            Button {
                                savePlaybackPosition()
                                appState.stopPlayback()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .padding()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("player-close-button")
                            Spacer()
                        }
                        .padding(.top, 8)
                        .padding(.leading, 8)
                        Spacer()
                    }
                    #endif
                }
                .ignoresSafeArea()
            }

            // Buffering overlay for in-progress recordings
            if isBuffering && isRecordingInProgress && isPlayerReady {
                VStack(spacing: Theme.spacingSM) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text("Buffering...")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(Theme.spacingLG)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
            }

            // Seeking overlay for catch-up (#119) — a catch-up seek lands on an
            // unindexed, variable-bitrate remote stream, so mpv can take tens of
            // seconds to locate the byte position (confirmed via mpv's own verbose
            // log; not fixable client-side). This just keeps that wait from
            // reading as a frozen player.
            if isCatchupSeeking && isPlayerReady {
                VStack(spacing: Theme.spacingSM) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text("Seeking…")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(Theme.spacingLG)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                // Declared above controlsOverlay in the ZStack, so without an
                // explicit zIndex it rendered behind the center pause button
                // (equal default zIndex falls back to declaration order).
                .zIndex(1)
            }

            // Subtitle text overlay — positioned at the bottom of the video content
            // (not the screen) so subtitles stay inside the video in portrait mode
            if let subtitleText = currentSubtitleText, isPlayerReady {
                let subPrefs = UserPreferences.load()
                GeometryReader { geo in
                    let videoAspect: CGFloat = 16.0 / 9.0
                    let screenAspect = geo.size.width / geo.size.height
                    let videoHeight = screenAspect < videoAspect
                        ? geo.size.width / videoAspect
                        : geo.size.height
                    let blackBarHeight = (geo.size.height - videoHeight) / 2
                    let hasBottomControls = (!isLiveStream && duration > 0) || canSeekLive
                    let controlsOffset: CGFloat = showControls && hasBottomControls ? 80 : 20
                    let bottomY = geo.size.height - blackBarHeight - controlsOffset

                    subtitleLabel(subtitleText, size: subPrefs.subtitleSize, showBackground: subPrefs.subtitleBackground)
                        .position(x: geo.size.width / 2, y: bottomY)
                }
                .allowsHitTesting(false)
            }

            // Custom controls overlay
            if showControls && isPlayerReady {
                controlsOverlay
            }

            // Stream settings panel overlay
            if showSettingsPanel && isPlayerReady {
                streamSettingsPanel
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }

            // Error message
            if let error = errorMessage {
                VStack {
                    // Show close button over the error when controls are not accessible
                    if !isPlayerReady {
                        HStack {
                            #if !os(tvOS)
                            Button {
                                savePlaybackPosition()
                                appState.stopPlayback()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .padding()
                            }
                            .buttonStyle(.plain)
                            #endif
                            Spacer()
                        }
                        .padding(.top, Theme.spacingSM)
                    }
                    Spacer()
                    VStack(spacing: Theme.spacingSM) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                        Text(error)
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(Theme.cornerRadiusSM)
                    .padding()
                }
            }

            #if os(macOS)
            // Hidden buttons for keyboard shortcuts
            // Hidden buttons for keyboard shortcuts — must have non-zero frame to receive events
            VStack {
                Button("") {
                    savePlaybackPosition()
                    appState.stopPlayback()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("") {
                    isPlaying.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])

                if !isLiveStream {
                    Button("") {
                        triggerSeekBackward()
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button("") {
                        triggerSeekForward()
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            #endif
        }
        .background(Color.black)
        .accessibilityIdentifier("player-view")
        #if os(tvOS)
        .onExitCommand {
            if showSettingsPanel {
                dismissSettingsPanel()
                tvFocusedTrackIndex = -1
            } else {
                savePlaybackPosition()
                appState.stopPlayback()
            }
        }
        #endif
        .onAppear {
            scheduleHideControls()
            #if os(macOS)
            updatePowerAssertion()
            #else
            // Prevent screen from sleeping during video playback
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            startLiveKeepalive()
            #if DISPATCHERPVR
            startDispatchProfileRefreshLoop()
            #endif
        }
        .onDisappear {
            #if os(tvOS)
            clearDisplayCriteria()
            #endif
            // Save position BEFORE cleanup — cleanup destroys the MPV player
            // which can interfere with reading currentPosition.
            // Always save unconditionally — on tvOS the Menu button may be
            // intercepted by SwiftUI's fullScreenCover dismiss before reaching
            // the MPV view, so the onDismiss callback never fires.
            savePlaybackPosition()
            #if os(iOS)
            let session = activePlayerSession
            let nativePiPActive = isUsingPixelBufferRenderer && (session.isPiPActive || session.dismissingForPiP)
            if nativePiPActive {
                // Don't stop player — mpv continues feeding PiP, so the server-side
                // stream and its keepalive have to stay up too. The keepalive is
                // owned by LiveStreamKeepalive precisely so it survives this view;
                // just stop routing buffer state into state that's about to die.
                liveKeepalive.detach()
            } else {
                cleanupAction?()
                cleanupAction = nil
                if appState.isShowingPlayer {
                    appState.stopPlayback()
                }
                endLiveStream()
                endCatchupSessionIfNeeded()
            }
            #else
            cleanupAction?()
            cleanupAction = nil
            if appState.isShowingPlayer {
                appState.stopPlayback()
            }
            endLiveStream()
            endCatchupSessionIfNeeded()
            #endif
            // Notify recordings list to refresh with updated progress.
            // Delay slightly so the async position save completes first.
            if recordingId != nil {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    NotificationCenter.default.post(name: .recordingsDidChange, object: nil)
                }
            }
            #if os(macOS)
            // Ensure cursor is visible when leaving the player
            NSCursor.setHiddenUntilMouseMoves(false)
            releasePowerAssertion()
            #else
            // Re-enable screen sleeping
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
            #if DISPATCHERPVR
            dispatchProfileRefreshTask?.cancel()
            dispatchProfileRefreshTask = nil
            #endif
            catchupSeekSafetyTask?.cancel()
            catchupSeekSafetyTask = nil
            catchupContinuationTask?.cancel()
            catchupContinuationTask = nil
        }
        #if DISPATCHERPVR
        .onChange(of: appState.currentlyPlayingChannelName) { _ in
            startDispatchProfileRefreshLoop()
        }
        #endif
        .onChange(of: duration) { _ in
            // A continuation stream (#150) carries its own PTS base, so the
            // display offset has to be recaptured the way the first load does.
            if pendingCatchupRebase && duration > 0 {
                pendingCatchupRebase = false
                startTimeOffset = currentPosition > 1 ? currentPosition : 0
            }
            // Resume playback position once duration is known (playback has started)
            if !hasResumed && duration > 0 {
                hasResumed = true
                // Capture initial position as display offset for streams with non-zero
                // start times (e.g., in-progress recordings with PTS offset)
                if currentPosition > 1 {
                    startTimeOffset = currentPosition
                }
                if let resumePos = resumePosition, resumePos > 0 {
                    // Has resume position - seek then show player
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        seekToPositionFunc?(Double(resumePos))
                        // Show player after seek completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isPlayerReady = true
                        }
                    }
                } else {
                    // No resume position - show player immediately
                    isPlayerReady = true
                }
            }
        }
        .onChange(of: isPlaying) { newValue in
            if !isPlaying {
                savePlaybackPosition()
            }
            #if os(macOS)
            // Pausing live TV still has to hold the system awake — see
            // PlayerPowerAssertion.
            updatePowerAssertion()
            #endif
        }
        .task(id: isPlayerReady) {
            guard isPlayerReady else { return }
            // Wait for tracks to be populated after demuxing starts
            try? await Task.sleep(for: .seconds(2))
            autoSelectSubtitleIfNeeded()

            // Poll subtitle text while playing
            while !Task.isCancelled {
                let text = getSubtitleTextFunc?()
                if text != currentSubtitleText {
                    currentSubtitleText = text
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onChange(of: currentPosition) { position in
            // Playback got going again, so the previous live reload landed on
            // readable data — start the retry budget over for the next seek.
            if liveEdgeRetryCount > 0 && position > 2 {
                liveEdgeRetryCount = 0
            }
            if isLiveStream {
                liveTracker.update(playerPosition: position)
            }
            detectBuffering()
        }
        #if os(tvOS)
        .onChange(of: showSettingsPanel) { _ in
            appState.tvosPlayerSettingsPanelOpen = showSettingsPanel
            if !showSettingsPanel {
                scheduleHideControls()  // always re-arm auto-hide when the panel closes
            }
        }
        #endif
        .onChange(of: duration) { _ in
            // duration keeps growing for in-progress recordings even when
            // position is frozen by cache-pause, so this fires the detection
            // when onChange(of: currentPosition) can't.
            detectBuffering()
        }
    }

    /// Attaches this view to the server-side live stream renewal loop.
    ///
    /// NextPVR reclaims the tuner and deletes the timeshift buffer after 15
    /// seconds without a renewal. While playing, mpv's socket reads mask this;
    /// once paused, mpv fills its demuxer cache and stops reading, so without
    /// renewals the stream is torn down mid-pause and resume plays only the
    /// local cache before dying (issue #120).
    ///
    /// The loop itself lives in `LiveStreamKeepalive`, not in this view's state:
    /// entering native PiP destroys `PlayerView` while playback continues, so a
    /// view-owned task would leak and the view rebuilt on restore would start a
    /// second one (issue #133). Starting for a URL that's already being renewed
    /// adopts the running loop instead.
    private func startLiveKeepalive() {
        guard isLiveStream else {
            liveKeepalive.stop()
            resetLiveTimeshiftState()
            return
        }
        // Only a genuinely new stream resets the timeshift view state — adopting the
        // loop after a PiP restore has to keep what it already knows about the buffer.
        if !liveKeepalive.isRunning(for: url) {
            resetLiveTimeshiftState()
        }
        liveKeepalive.start(
            streamKey: url,
            renew: { [client] in try? await client.renewLiveStream() },
            onInfo: { info, at in
                liveStreamInfo = info
                liveStreamInfoAt = at
            }
        )
    }

    private func resetLiveTimeshiftState() {
        liveStreamInfo = nil
        liveStreamInfoAt = .distantPast
        liveTracker = LivePositionTracker()
    }

    // MARK: - Live timeshift buffer

    /// Length of the server-side buffer, extrapolated from the last poll — it grows
    /// in real time, so waiting for the next 10s `stream.info` would make the live
    /// edge visibly stutter.
    private var liveBufferDuration: Double {
        guard let liveStreamInfo, liveStreamInfoAt > .distantPast else { return 0 }
        return liveStreamInfo.streamDuration + Date().timeIntervalSince(liveStreamInfoAt)
    }

    /// Play position measured from the start of the buffer, not from the start of
    /// the current stream — those differ once a seek has reopened at an offset,
    /// and mpv's own origin can move mid-stream (#148).
    private var livePlayPosition: Double {
        liveTracker.position
    }

    private var secondsBehindLive: Double {
        max(0, liveBufferDuration - displayLivePosition)
    }

    /// Live seeking needs a buffer with a usable byte-rate ratio, a way to reload,
    /// and enough content to be worth offering.
    private var canSeekLive: Bool {
        isLiveStream
            && liveStreamInfo?.bytesPerSecond != nil
            && reloadURLFunc != nil
            && liveBufferDuration > Self.minimumLiveBuffer
    }

    private static let liveEdgeMargin = LiveTimeshift.edgeMargin
    private static let minimumLiveBuffer = LiveTimeshift.minimumBuffer

    /// Reopens the stream at `position` (seconds from buffer start). NextPVR can't
    /// seek an open `/live` response, so this is a reload rather than an mpv seek.
    private func seekLive(to position: Double) {
        guard canSeekLive, let info = liveStreamInfo, let reload = reloadURLFunc else { return }

        liveSeekCommitTask?.cancel()
        liveSeekCommitTask = nil
        pendingLiveSeekTarget = nil

        let target = LiveTimeshift.clampedTarget(position, bufferDuration: liveBufferDuration)
        guard let offset = info.byteOffset(forPosition: target),
              let url = client.liveStreamSeekURL(byteOffset: offset) else { return }

        // mpv restarts at 0 in the reopened stream, so the buffer position it maps
        // to has to be carried separately.
        liveTracker.anchor(at: target)
        currentPosition = 0
        isLiveSeeking = true
        lastLiveSeekAt = Date()
        reload(url)
        isPlaying = true
        scheduleHideControls()

        Task {
            try? await Task.sleep(for: .seconds(1))
            isLiveSeeking = false
        }
    }

    /// Coalesces rapid skip presses into a single reload. Every live seek reopens
    /// the stream server-side, and tvOS hold-to-scrub fires every 250ms, so applying
    /// them one for one would thrash the tuner. The pending target drives the
    /// timeshift bar in the meantime, so each press still shows up immediately.
    private func seekLiveBy(_ delta: Double) {
        guard canSeekLive else { return }
        let base = pendingLiveSeekTarget ?? livePlayPosition
        let target = LiveTimeshift.clampedTarget(base + delta, bufferDuration: liveBufferDuration)
        // Already there — skip-forward at the live edge shouldn't churn the tuner.
        // (tvOS drives this from remote presses, which have no disabled state.)
        guard abs(target - base) >= 1 else { return }
        pendingLiveSeekTarget = target
        liveSeekCommitTask?.cancel()
        liveSeekCommitTask = Task {
            try? await Task.sleep(for: LiveTimeshift.seekCommitDelay)
            guard !Task.isCancelled, let target = pendingLiveSeekTarget else { return }
            seekLive(to: target)
        }
    }

    /// Play position as the controls should show it: the pending skip target while
    /// presses are still being coalesced, otherwise where playback actually is.
    private var displayLivePosition: Double {
        pendingLiveSeekTarget ?? livePlayPosition
    }

    /// Handles the EOF that a live reload can hit when it reopens at a byte offset
    /// the server hasn't flushed yet: mpv reads zero bytes and reports end-of-file,
    /// which would otherwise tear the player down and drop the user back to the
    /// guide. NextPVR's `/live` is raw MPEG-TS, so the HLS recovery path in
    /// `MPVPlayerCore` doesn't cover it.
    ///
    /// Retries a little further back each time — the previous offset already proved
    /// it wasn't readable — and gives up after a few attempts so a genuinely dead
    /// stream still ends.
    ///
    /// Returns true when the EOF was absorbed and the caller should not tear down.
    private func recoverFromLiveEdgeEOF() -> Bool {
        guard isLiveStream, canSeekLive else { return false }
        guard LiveTimeshift.shouldRetryAfterEOF(
            secondsSinceLastSeek: Date().timeIntervalSince(lastLiveSeekAt),
            retryCount: liveEdgeRetryCount
        ) else { return false }

        liveEdgeRetryCount += 1
        let target = LiveTimeshift.retryTarget(from: livePlayPosition, attempt: liveEdgeRetryCount)
        print("[Player] Live-edge EOF, retrying at \(Int(target))s (attempt \(liveEdgeRetryCount))")
        seekLive(to: target)
        return true
    }

    /// Stops renewing and releases the server-side stream so the tuner is freed
    /// right away instead of after the renewal timeout. Not called while PiP is
    /// still playing.
    private func endLiveStream() {
        liveKeepalive.stop()
        liveSeekCommitTask?.cancel()
        liveSeekCommitTask = nil
        pendingLiveSeekTarget = nil
        guard isLiveStream else { return }
        Task { await client.stopLiveStream() }
    }

    /// Best-effort revoke of the catch-up session (#119) minted for this
    /// playback, freeing the server-side slot immediately instead of
    /// waiting out the 10-minute idle TTL. Reads the view's own
    /// `catchupSessionId` rather than `appState`'s, since `appState.stopPlayback()`
    /// (called just before this in `.onDisappear`) already clears the
    /// published copy.
    private func endCatchupSessionIfNeeded() {
        // After a continuation remint (#150) the session feeding the player is
        // no longer the one this view was created with.
        guard let sessionId = activeCatchupSessionId ?? catchupSessionId else { return }
        #if DISPATCHERPVR
        Task { [client] in await client.endCatchupSession(sessionId) }
        #endif
    }

    /// Playback reached the end of the file mpv is reading. That means the
    /// stream ended for a recording, but for live TV and for catch-up on a
    /// programme that is still airing it only means the readable edge moved
    /// ahead of us — both get a chance to recover before playback ends.
    private func handlePlaybackEnded() {
        if recoverFromLiveEdgeEOF() { return }
        if continueCatchupIfNeeded() { return }
        savePlaybackPosition()
        markAsWatched()
        if !isRecordingInProgress {
            appState.stopPlayback()
        }
    }

    /// Whether this EOF is the archive edge of a catch-up session for a
    /// programme that is still airing — in which case a fresh session picks up
    /// where this one stopped instead of playback ending (#150).
    private func continueCatchupIfNeeded() -> Bool {
        #if DISPATCHERPVR
        guard let catchupProgram, catchupSessionId != nil else { return false }
        // A single EOF surfaces twice (END_FILE plus the eof-reached property);
        // the second one must not mint a second session.
        guard !isContinuingCatchup else { return true }

        let playedThisSession = max(0, currentPosition - startTimeOffset)
        if CatchupContinuation.isShortSession(playedSeconds: playedThisSession) {
            catchupShortSessionCount += 1
        } else {
            catchupShortSessionCount = 0
        }
        guard !CatchupContinuation.shouldGiveUp(consecutiveShortSessions: catchupShortSessionCount) else {
            print("[Catchup] Ending playback: \(catchupShortSessionCount) continuations made no progress")
            return false
        }

        let played = catchupPlayedOffset + playedThisSession
        let decision = CatchupContinuation.decide(
            programStart: catchupProgram.programStart,
            programEnd: catchupProgram.programEnd,
            playedSeconds: played,
            now: Date()
        )
        guard decision != .finished else { return false }

        isContinuingCatchup = true
        startCatchupSeekIndicatorIfNeeded()
        catchupContinuationTask?.cancel()
        catchupContinuationTask = Task {
            await continueCatchup(playedSeconds: played, context: catchupProgram)
        }
        return true
        #else
        return false
        #endif
    }

    #if DISPATCHERPVR
    /// Mints the next session in the chain and reloads the player into it.
    /// `playedSeconds` is where playback got to, measured from the programme's
    /// scheduled start, which is exactly the `start` the new session needs.
    private func continueCatchup(playedSeconds: Double, context: CatchupProgramContext) async {
        defer { isContinuingCatchup = false }

        while !Task.isCancelled {
            switch CatchupContinuation.decide(
                programStart: context.programStart,
                programEnd: context.programEnd,
                playedSeconds: playedSeconds,
                now: Date()
            ) {
            case .finished:
                endCatchupPlayback()
                return

            case .wait(let seconds):
                // Playback has drawn level with the broadcast; let a little more
                // of the programme air rather than mint a near-empty archive.
                try? await Task.sleep(for: .seconds(seconds))

            case .resume(let start):
                do {
                    let service = CatchupService(client: client, baseURL: client.baseURL)
                    let session = try await service.startSession(
                        channelUuid: context.channelUuid,
                        startISO8601: ISO8601DateFormatter().string(from: start)
                    )
                    let url = try service.playbackURL(for: session)
                    guard !Task.isCancelled, let reload = reloadURLFunc else { return }

                    let previousSessionId = activeCatchupSessionId ?? catchupSessionId
                    activeCatchupSessionId = session.sessionId
                    // mpv restarts the new file at its own origin, so the part of
                    // the programme already played has to be carried separately —
                    // same shape as the live seek path's LivePositionTracker.
                    catchupPlayedOffset = playedSeconds
                    pendingCatchupRebase = true
                    startTimeOffset = 0
                    currentPosition = 0
                    duration = 0
                    reload(url)
                    isPlaying = true
                    print("[Catchup] Continuing at \(Int(playedSeconds))s into the programme")

                    if let previousSessionId {
                        Task { [client] in await client.endCatchupSession(previousSessionId) }
                    }
                } catch {
                    print("[Catchup] Continuation failed: \(error.localizedDescription)")
                    endCatchupPlayback()
                }
                return
            }
        }
    }
    #endif

    /// Ends playback the way `handlePlaybackEnded` would have, once the
    /// continuation chain decides there is nothing left to play.
    private func endCatchupPlayback() {
        endCatchupSeekIndicator()
        savePlaybackPosition()
        markAsWatched()
        appState.stopPlayback()
    }

    /// Detects when playback has stalled (position not advancing while
    /// playing) and triggers a stream reload to recover.
    private func detectBuffering() {
        guard isRecordingInProgress, isPlayerReady, isPlaying else {
            bufferingStallCount = 0
            isBuffering = false
            return
        }
        // Detect position jumps (e.g. after reload with backoff) — reset tracking
        if currentPosition < lastBufferingCheckPosition - 1 {
            lastBufferingCheckPosition = currentPosition
            bufferingStallCount = 0
            isBuffering = false
            return
        }
        if currentPosition > lastBufferingCheckPosition + 0.1 {
            // Position advancing — not buffering
            lastBufferingCheckPosition = currentPosition
            bufferingStallCount = 0
            if isBuffering {
                isBuffering = false
            }
        } else {
            // Position stalled — count consecutive stalls (each ~0.5s from duration changes)
            bufferingStallCount += 1
            if bufferingStallCount >= 3 && !isBuffering {
                isBuffering = true
            }
            // No app-level reload needed — stream-lavf-growing-file
            // handles the close/reopen at the stream layer.
        }
    }

    private func savePlaybackPosition() {
        guard let recordingId = recordingId else {
            print("[Player] savePlaybackPosition: no recordingId")
            return
        }
        let position = Int(currentPosition)
        let dur = duration
        print("[Player] savePlaybackPosition: id=\(recordingId) pos=\(position) dur=\(Int(dur))")
        // Don't save if we're at the very beginning
        guard position > 10 else { return }
        // If near the end, mark as fully watched instead (but not for in-progress recordings)
        if !isRecordingInProgress && dur > 0 && Double(position) > dur - 30 {
            markAsWatched()
            return
        }

        Task.detached { [client] in
            try? await client.setRecordingPosition(recordingId: recordingId, positionSeconds: position)
        }
    }

    private func markAsWatched() {
        guard let recordingId = recordingId else { return }
        // Set position to full duration to mark as watched
        let watchedPosition = Int(duration > 0 ? duration : currentPosition)
        Task.detached { [client] in
            try? await client.setRecordingPosition(recordingId: recordingId, positionSeconds: watchedPosition)
            print("[Player] Marked recording \(recordingId) as watched")
            // Notify recordings list to refresh
            NotificationCenter.default.post(name: .recordingsDidChange, object: nil)
        }
    }

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            topBar

            Spacer()

            // Center controls: seek backward, play/pause, seek forward
            centerControls

            Spacer()

            // Bottom controls: progress bar and time
            if !isLiveStream && duration > 0 {
                bottomControls
            } else if canSeekLive {
                liveBottomControls
            }
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// Catch-up playback (#119) is a discrete, fully-buffered show, not a
    /// live tuner feed — excluding it here routes it to the same
    /// duration/scrubber controls as a recording (`!isLiveStream && duration
    /// > 0`) instead of the live-edge timeshift bar, and skips the live
    /// keepalive/EOF-recovery machinery that's meaningless for it.
    ///
    /// A local file is never live either. An offline download carries neither a
    /// recording id nor a catch-up session, so without this it would land on
    /// the live-edge bar and refuse to seek.
    private var isLiveStream: Bool {
        recordingId == nil && catchupSessionId == nil && !url.isFileURL
    }

    private var centerControls: some View {
        HStack(spacing: 48) {
            if !isLiveStream || canSeekLive {
                // Seek backward button
                Button {
                    if isLiveStream {
                        seekLiveBy(-Double(seekBackwardTime))
                    } else {
                        triggerSeekBackward()
                    }
                } label: {
                    playerControlIcon(systemName: "gobackward.\(seekBackwardTime)", size: 40)
                }
                .buttonStyle(.plain)
                .disabled(isLiveStream && displayLivePosition <= 0)
            }

            // Play/pause button
            Button {
                isPlaying.toggle()
            } label: {
                playerControlIcon(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill", size: 64)
            }
            .buttonStyle(.plain)

            if !isLiveStream || canSeekLive {
                // Seek forward button
                Button {
                    if isLiveStream {
                        seekLiveBy(Double(seekForwardTime))
                    } else {
                        triggerSeekForward()
                    }
                } label: {
                    playerControlIcon(systemName: "goforward.\(seekForwardTime)", size: 40)
                }
                .buttonStyle(.plain)
                // Nothing to skip into once we're at the live edge.
                .disabled(isLiveStream && secondsBehindLive <= Self.liveEdgeMargin)
            }

            #if !os(tvOS)
            // Jump to the live edge. Not offered on tvOS: the controls overlay is
            // display-only there (the mpv view keeps focus and drives everything
            // from remote presses), so the button can never be reached — up on the
            // remote opens the settings panel. The Siri Remote's skip-forward is
            // the live-edge path on tvOS instead; it clamps to the head.
            if isLiveStream && canSeekLive {
                Button {
                    seekLive(to: liveBufferDuration)
                } label: {
                    playerControlIcon(systemName: "forward.end.alt.fill", size: 28)
                }
                .buttonStyle(.plain)
                .disabled(secondsBehindLive <= Self.liveEdgeMargin)
            }
            #endif
        }
    }

    private func playerControlIcon(systemName: String, size: CGFloat, padding: CGFloat = 10) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(.white)
            .padding(padding)
            .background(.black.opacity(0.35), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.85), radius: 4, x: 0, y: 1)
            .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 2)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Progress fill
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: progressWidth(for: geometry.size.width), height: 4)

                    // Scrubber handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: progressWidth(for: geometry.size.width) - 7)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                #if !os(tvOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            seekPosition = playerPosition(forDisplayed: progress * displayedDuration)
                            scheduleHideControls()
                        }
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let targetPosition = playerPosition(forDisplayed: progress * displayedDuration)
                            seekToPosition(targetPosition)
                            isSeeking = false
                        }
                )
                #endif
            }
            .frame(height: 14)

            // Time labels
            HStack {
                Text(formatTime(displayedPosition))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(displayedDuration))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    /// Timeshift bar: spans the whole server-side buffer, from where it started
    /// recording to the live edge, with the play position on it.
    private var liveBottomControls: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    Rectangle()
                        .fill(Theme.recording)
                        .frame(width: liveProgressWidth(for: geometry.size.width), height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: liveProgressWidth(for: geometry.size.width) - 7)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                #if !os(tvOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            seekLive(to: progress * liveBufferDuration)
                        }
                )
                #endif
            }
            .frame(height: 14)

            HStack {
                Text(formatTime(displayLivePosition))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Spacer()

                if secondsBehindLive > Self.liveEdgeMargin {
                    Text("-\(formatTime(secondsBehindLive)) behind live")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                } else {
                    Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(Theme.recording)
                }

                Spacer()

                Text(formatTime(liveBufferDuration))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func liveProgressWidth(for totalWidth: CGFloat) -> CGFloat {
        let buffer = liveBufferDuration
        guard buffer > 0 else { return 0 }
        let progress = displayLivePosition / buffer
        return max(0, min(totalWidth, CGFloat(progress) * totalWidth))
    }

    private func progressWidth(for totalWidth: CGFloat) -> CGFloat {
        guard displayedDuration > 0 else { return 0 }
        let progress = displayedPosition / displayedDuration
        return max(0, min(totalWidth, CGFloat(progress) * totalWidth))
    }

    /// How far into the *programme* playback is, which after a catch-up
    /// continuation (#150) is ahead of the current stream's own timeline.
    /// Identical to the raw position while `catchupPlayedOffset` is 0.
    private var displayedPosition: Double {
        (isSeeking ? seekPosition : currentPosition) - startTimeOffset + catchupPlayedOffset
    }

    /// Length of the programme as far as it has been fetched: what the current
    /// session holds, plus everything earlier sessions already played.
    private var displayedDuration: Double {
        duration + catchupPlayedOffset
    }

    /// Maps a point on the scrubber back onto the current stream's timeline.
    private func playerPosition(forDisplayed displayed: Double) -> Double {
        max(0, displayed - catchupPlayedOffset) + startTimeOffset
    }

    #if os(tvOS)
    private func updateDisplayCriteriaIfNeeded(gamma: String?, fps: Double) {
        guard !hasSetDisplayCriteria else { return }
        guard let gamma, !gamma.isEmpty else { return }

        // Map mpv's gamma/transfer to CoreMedia transfer function
        let transferFunction: CFString
        switch gamma.lowercased() {
        case "pq", "smpte-st2084", "smpte2084":
            transferFunction = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        case "hlg", "arib-std-b67":
            transferFunction = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        case "bt.1886", "gamma2.2", "srgb":
            return // SDR — no need to change display mode
        default:
            return
        }

        // Create a format description that fully describes the HDR video.
        // The system needs codec type, resolution, transfer function, color primaries,
        // YCbCr matrix, AND bit depth to properly trigger HDR display mode.
        let width = videoHeight.map { Int($0) * 16 / 9 } ?? 3840
        let height = videoHeight ?? 2160
        let bitsPerComponent: Int = 10
        var formatDescription: CMFormatDescription?
        let extensions: [String: Any] = [
            kCMFormatDescriptionExtension_TransferFunction as String: transferFunction,
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCMFormatDescriptionColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
            kCMFormatDescriptionExtension_BitsPerComponent as String: bitsPerComponent,
            kCMFormatDescriptionExtension_FullRangeVideo as String: false,
            "CVPixelFormatType" as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        ]
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_HEVC,
            width: Int32(width),
            height: Int32(height),
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &formatDescription
        )

        guard let formatDescription else {
            print("DisplayManager: failed to create format description")
            return
        }

        let refreshRate = fps > 0 ? Float(fps) : 0
        let criteria = AVDisplayCriteria(refreshRate: refreshRate, formatDescription: formatDescription)

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }

        window.avDisplayManager.preferredDisplayCriteria = criteria
        hasSetDisplayCriteria = true
        print("DisplayManager: set HDR criteria transfer=\(gamma) fps=\(refreshRate)")
    }

    private func clearDisplayCriteria() {
        guard hasSetDisplayCriteria else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }

        window.avDisplayManager.preferredDisplayCriteria = nil
        hasSetDisplayCriteria = false
        print("DisplayManager: cleared criteria")
    }
    #endif

    private var isUsingPixelBufferRenderer: Bool {
        #if os(tvOS)
        return UserPreferences.load().tvosGPUAPI == .pixelbuffer
        #elseif os(iOS)
        return UserPreferences.load().iosGPUAPI == .pixelbuffer
        #elseif os(macOS)
        return UserPreferences.load().macosGPUAPI == .pixelbuffer
        #else
        return false
        #endif
    }

    #if os(iOS)
    private func setupNativePiPIfNeeded() {
        let session = activePlayerSession
        guard isUsingPixelBufferRenderer,
              session.pipController == nil,
              session.hasActiveSession else { return }

        session.setupPiP(
            playPauseHandler: { playing in
                if playing { session.player?.play() } else { session.player?.pause() }
            },
            isPausedQuery: {
                session.player?.isPaused ?? true
            },
            onSessionEnded: { [client, liveKeepalive, appState] in
                // The PiP window was closed outright, so no PlayerView will run
                // onDisappear — release the server-side stream here instead of
                // leaving the tuner held until the renewal loop's next failure.
                liveKeepalive.stop()
                Task { await client.stopLiveStream() }
                appState.stopPlayback()
            }
        )
    }

    private func toggleNativePiP() {
        let session = activePlayerSession
        guard let controller = session.pipController else { return }

        if controller.isPictureInPictureActive {
            controller.stop()
            pipIsActive = false
            session.isPiPActive = false
        } else {
            session.isPiPActive = true
            session.dismissingForPiP = true
            controller.start()
            pipIsActive = true
            appState.dismissPlayer()
        }
    }
    #endif

    private func seekToPosition(_ position: Double) {
        startCatchupSeekIndicatorIfNeeded()
        seekToPositionFunc?(position)
        currentPosition = position
    }

    private func triggerSeekForward() {
        startCatchupSeekIndicatorIfNeeded()
        seekForward?()
    }

    private func triggerSeekBackward() {
        startCatchupSeekIndicatorIfNeeded()
        seekBackward?()
    }

    /// Shows the "Seeking…" overlay for catch-up (#119) and arms a generous
    /// safety-net timeout that clears it even if mpv never reports
    /// restarted (e.g. the seek genuinely fails) — the overlay should never
    /// get permanently stuck up.
    private func startCatchupSeekIndicatorIfNeeded() {
        guard catchupSessionId != nil else { return }
        isCatchupSeeking = true
        catchupSeekSafetyTask?.cancel()
        catchupSeekSafetyTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            isCatchupSeeking = false
        }
    }

    private func endCatchupSeekIndicator() {
        catchupSeekSafetyTask?.cancel()
        catchupSeekSafetyTask = nil
        isCatchupSeeking = false
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private var topBar: some View {
        HStack {
            #if !os(tvOS)
            Button {
                savePlaybackPosition()
                appState.stopPlayback()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player-close-button")
            #endif

            Text(headerTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Spacer()

            #if os(iOS) || os(macOS)
            Button {
                isMuted.toggle()
                setMutedFunc?(isMuted)
                scheduleHideControls()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player-mute-button")
            #endif

            #if os(iOS)
            if isUsingPixelBufferRenderer && pipIsSupported {
                Button {
                    toggleNativePiP()
                } label: {
                    Image(systemName: pipIsActive ? "pip.exit" : "pip.enter")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            #endif

            #if !os(tvOS)
            if videoHeight != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSettingsPanel.toggle()
                    }
                    if showSettingsPanel {
                        trackList = getTrackListFunc?() ?? []
                        hideControlsTask?.cancel()
                    } else {
                        scheduleHideControls()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            #endif
        }
        .padding(.horizontal)
        .padding(.top, Theme.spacingMD)
    }

    // MARK: - Stream Settings Panel

    private var panelWidth: CGFloat {
        #if os(tvOS)
        return 400
        #elseif os(macOS)
        return 340
        #else
        return 320
        #endif
    }

    #if os(tvOS)
    private var hasChapters: Bool {
        !isLiveStream && !isRecordingInProgress && duration > 0
    }

    private var tvTrackCount: Int {
        switch settingsTab {
        case .video: return hasChapters ? 10 : 0
        case .audio: return trackList.filter { $0.type == "audio" }.count
        case .subtitles: return trackList.filter { $0.type == "sub" }.count + 1 // +1 for "None"
        }
    }

    private func tvSelectFocusedTrack() {
        guard tvFocusedTrackIndex >= 0 else { return }
        switch settingsTab {
        case .video:
            if hasChapters && tvFocusedTrackIndex < 10 {
                let chapterPosition = duration / 10.0 * Double(tvFocusedTrackIndex)
                seekToPosition(chapterPosition)
            }
        case .audio:
            let audioTracks = trackList.filter { $0.type == "audio" }
            if tvFocusedTrackIndex < audioTracks.count {
                setAudioTrackFunc?(audioTracks[tvFocusedTrackIndex].id)
                trackList = getTrackListFunc?() ?? []
            }
        case .subtitles:
            if tvFocusedTrackIndex == 0 {
                // "None" option
                setSubtitleTrackFunc?(nil)
                trackList = getTrackListFunc?() ?? []
                let prefs = UserPreferences.load()
                if prefs.subtitleMode == .auto {
                    var updated = prefs
                    updated.preferredSubtitleLanguage = nil
                    updated.save()
                }
            } else {
                let subtitleTracks = trackList.filter { $0.type == "sub" }
                let idx = tvFocusedTrackIndex - 1 // -1 for "None" row
                if idx < subtitleTracks.count {
                    let track = subtitleTracks[idx]
                    setSubtitleTrackFunc?(track.id)
                    trackList = getTrackListFunc?() ?? []
                    let prefs = UserPreferences.load()
                    if prefs.subtitleMode == .auto {
                        var updated = prefs
                        updated.preferredSubtitleLanguage = track.lang ?? track.codec
                        updated.save()
                    }
                }
            }
        }
    }
    #endif

    private var panelLabelFont: Font {
        #if os(tvOS)
        .headline
        #else
        .caption
        #endif
    }

    private var panelTextFont: Font {
        #if os(tvOS)
        .headline
        #else
        .subheadline
        #endif
    }

    private func dismissSettingsPanel() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showSettingsPanel = false
        }
        scheduleHideControls()
    }

    private var streamSettingsPanel: some View {
        HStack(spacing: 0) {
            #if !os(tvOS)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSettingsPanel()
                }
            #else
            Spacer()
            #endif

            VStack(alignment: .leading, spacing: 0) {
                settingsTabBar
                    .padding(.top, Theme.spacingMD)

                Divider()
                    .background(Color.white.opacity(0.2))

                // Tab content
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        switch settingsTab {
                        case .video:
                            videoTabContent
                        case .audio:
                            audioTabContent
                        case .subtitles:
                            subtitlesTabContent
                        }
                    }
                    .padding(Theme.spacingMD)
                }
            }
            .frame(width: panelWidth)
            .background(Color.black.opacity(0.9))
        }
    }


    private var settingsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(StreamSettingsTab.allCases, id: \.self) { tab in
                Button {
                    settingsTab = tab
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(panelLabelFont)
                            Text(tab.rawValue)
                                .font(panelLabelFont)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(settingsTab == tab ? Theme.accent : .white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Rectangle()
                            .fill(settingsTab == tab ? Theme.accent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.spacingSM)
    }

    private var videoTabContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let height = videoHeight {
                videoInfoRow("Resolution", resolutionLabel(height: height))
            }
            if let codec = videoCodec {
                videoInfoRow("Video", formatCodecName(codec))
            }
            if let hw = hwDecoder, !hw.isEmpty, hw != "no" {
                videoInfoRow("HW Decode", hw)
            } else {
                videoInfoRow("HW Decode", "No")
            }
            if let gamma = videoGamma, !gamma.isEmpty {
                videoInfoRow("HDR", hdrLabel(gamma))
            }
            #if DISPATCHERPVR
            if let profile = dispatchProfileBadge {
                videoInfoRow("Profile", profile)
            }
            #endif
            videoInfoRow("Renderer", rendererTag)
            if droppedFrames > 0 {
                videoInfoRow("Dropped", "\(droppedFrames)")
            }

            if !isLiveStream && !isRecordingInProgress && duration > 0 {
                Divider()
                    .background(.gray.opacity(0.5))
                    .padding(.vertical, Theme.spacingSM)

                Text("Chapters")
                    .font(panelLabelFont)
                    .foregroundStyle(.gray)
                    .padding(.bottom, 4)

                ForEach(0..<10, id: \.self) { index in
                    let chapterPosition = duration / 10.0 * Double(index)
                    let isCurrentChapter = currentPosition >= chapterPosition &&
                        (index == 9 || currentPosition < duration / 10.0 * Double(index + 1))
                    Button {
                        seekToPosition(chapterPosition)
                    } label: {
                        HStack {
                            Text("Chapter \(index + 1)")
                                .font(panelTextFont)
                                .foregroundStyle(.white)
                            Spacer()
                            Text(formatTime(chapterPosition))
                                .font(panelLabelFont)
                                .foregroundStyle(.gray)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, Theme.spacingSM)
                        .background(
                            tvOSFocused(index) ? Color.white.opacity(0.2) :
                            isCurrentChapter ? Theme.accent.opacity(0.2) : Color.clear
                        )
                        .cornerRadius(Theme.cornerRadiusSM)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var audioTabContent: some View {
        let audioTracks = trackList.filter { $0.type == "audio" }
        return VStack(alignment: .leading, spacing: 0) {
            // Current audio info
            if let audio = audioChannelLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Audio")
                        .font(panelLabelFont)
                        .foregroundStyle(.gray)
                    if let selectedTrack = audioTracks.first(where: { $0.isSelected }) {
                        Text(selectedTrack.audioDetail)
                            .font(panelTextFont)
                            .foregroundStyle(.white)
                    } else {
                        Text(audio)
                            .font(panelTextFont)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, Theme.spacingMD)
            }

            if audioTracks.isEmpty {
                Text("No audio tracks available")
                    .font(panelTextFont)
                    .foregroundStyle(.gray)
                    .padding(.vertical, Theme.spacingMD)
            } else {
                Text("Audio Tracks")
                    .font(panelLabelFont)
                    .foregroundStyle(.gray)
                    .padding(.bottom, 4)

                ForEach(Array(audioTracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, isActive: track.isSelected, isTVFocused: tvOSFocused(index)) {
                        setAudioTrackFunc?(track.id)
                        trackList = getTrackListFunc?() ?? []
                    }
                }
            }
        }
    }

    private var subtitlesTabContent: some View {
        let subtitleTracks = trackList.filter { $0.type == "sub" }
        let noneSelected = !subtitleTracks.contains(where: { $0.isSelected })
        return VStack(alignment: .leading, spacing: 0) {
            Text("Subtitle Tracks")
                .font(panelLabelFont)
                .foregroundStyle(.gray)
                .padding(.bottom, 4)

            // "None" option
            Button {
                setSubtitleTrackFunc?(nil)
                trackList = getTrackListFunc?() ?? []
                let prefs = UserPreferences.load()
                if prefs.subtitleMode == .auto {
                    var updated = prefs
                    updated.preferredSubtitleLanguage = nil
                    updated.save()
                }
            } label: {
                HStack {
                    Text("None")
                        .font(panelTextFont)
                        .foregroundStyle(.white)
                    Spacer()
                    if noneSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, 10)
                .background(tvOSFocused(0) ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if subtitleTracks.isEmpty {
                Text("No subtitle tracks available")
                    .font(panelTextFont)
                    .foregroundStyle(.gray)
                    .padding(.vertical, Theme.spacingMD)
                    .padding(.horizontal, Theme.spacingMD)
            } else {
                ForEach(Array(subtitleTracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, isActive: track.isSelected, isTVFocused: tvOSFocused(index + 1)) {
                        setSubtitleTrackFunc?(track.id)
                        trackList = getTrackListFunc?() ?? []
                        let prefs = UserPreferences.load()
                        if prefs.subtitleMode == .auto {
                            var updated = prefs
                            updated.preferredSubtitleLanguage = track.lang ?? track.codec
                            updated.save()
                        }
                    }
                }
            }
        }
    }

    private func tvOSFocused(_ index: Int) -> Bool {
        #if os(tvOS)
        return tvFocusedTrackIndex == index
        #else
        return false
        #endif
    }

    private func trackRow(_ track: MPVTrack, isActive: Bool, isTVFocused: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayName)
                        .font(panelTextFont)
                        .foregroundStyle(.white)
                    if !track.audioDetail.isEmpty {
                        Text(track.audioDetail)
                            .font(panelLabelFont)
                            .foregroundStyle(.gray)
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, 10)
            .background(isTVFocused ? Color.white.opacity(0.2) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hdrLabel(_ gamma: String) -> String {
        switch gamma.lowercased() {
        case "pq", "smpte-st2084", "smpte2084": return "HDR10 (PQ)"
        case "hlg", "arib-std-b67": return "HLG"
        case "bt.1886": return "SDR (BT.1886)"
        case "srgb": return "SDR (sRGB)"
        default: return gamma
        }
    }

    private func videoInfoRow(_ label: String, _ value: String) -> some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.body)
                .foregroundStyle(.gray)
            Text(value)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .padding(.vertical, 4)
        #else
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        #endif
    }

    private var headerTitle: String {
        return title
    }

    private var rendererTag: String {
        #if os(tvOS)
        let api = UserPreferences.load().tvosGPUAPI
        #elseif os(iOS)
        let api = UserPreferences.load().iosGPUAPI
        #elseif os(macOS)
        let api = UserPreferences.load().macosGPUAPI
        #else
        return ""
        #endif
        switch api {
        case .metal: return "M"
        case .pixelbuffer: return "PB"
        case .opengl: return "GL"
        }
    }

    #if DISPATCHERPVR
    private var canQueryDispatchProxyStatus: Bool {
        // Streamer/output-only users don't have access to /proxy/ts/status.
        appState.userLevel >= 1 && !client.useOutputEndpoints
    }

    private func startDispatchProfileRefreshLoop() {
        dispatchProfileRefreshTask?.cancel()
        guard canQueryDispatchProxyStatus else {
            dispatchProfileBadge = nil
            dispatchProfileRefreshTask = nil
            return
        }
        dispatchProfileRefreshTask = Task {
            await refreshDispatchProfileBadge()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                await refreshDispatchProfileBadge()
            }
        }
    }

    private func refreshDispatchProfileBadge() async {
        guard canQueryDispatchProxyStatus else {
            dispatchProfileBadge = nil
            return
        }
        // Stream status can lag behind player start, so retry briefly.
        dispatchProfileBadge = nil
        for attempt in 0..<5 {
            if let profile = await loadDispatchProfileBadge() {
                dispatchProfileBadge = profile
                return
            }
            if attempt < 4 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func loadDispatchProfileBadge() async -> String? {
        do {
            let status = try await client.getProxyStatus()
            guard let channels = status.channels, !channels.isEmpty else { return nil }

            // Prefer active channels only when available.
            let activeChannels = channels.filter { $0.state.lowercased() == "active" }
            let candidates = activeChannels.isEmpty ? channels : activeChannels

            // Dispatcharr 0.24.0 stopped sending m3u_profile_name; resolve id → name client-side.
            await client.ensureM3UProfileNamesLoaded()
            let lookup: (Int) -> String? = { [client] id in client.m3uProfileName(forId: id) }

            let names = [
                appState.currentlyPlayingChannelName,
                appState.currentlyPlayingTitle,
                title
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

            if let matched = candidates.first(where: { channel in
                names.contains(where: { matchesStreamName(channel.displayName, $0) })
            }) {
                return matched.profileLabel(nameLookup: lookup)
            }

            // If only one active stream exists, use its profile as a fallback.
            if candidates.count == 1 {
                return candidates[0].profileLabel(nameLookup: lookup)
            }
        } catch {
            return nil
        }
        return nil
    }

    private func matchesStreamName(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizedStreamName(lhs)
        let b = normalizedStreamName(rhs)
        if a.isEmpty || b.isEmpty { return false }
        return a == b || a.contains(b) || b.contains(a)
    }

    private func normalizedStreamName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "default", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    #endif



    private func resolutionLabel(height: Int) -> String {
        if height >= 2160 { return "4K" }
        if height >= 1440 { return "1440p" }
        if height >= 1080 { return "1080p" }
        if height >= 720 { return "720p" }
        if height >= 480 { return "480p" }
        return "\(height)p"
    }

    private func formatCodecName(_ codec: String) -> String {
        let lower = codec.lowercased()
        if lower.contains("h264") || lower.contains("avc") { return "H.264" }
        if lower.contains("hevc") || lower.contains("h265") { return "HEVC" }
        if lower.contains("vp9") { return "VP9" }
        if lower.contains("av1") || lower.contains("av01") { return "AV1" }
        return codec.uppercased()
    }

    #if os(macOS)
    /// Takes whatever assertion the current playback state calls for, swapping the
    /// held one when the requirement changes. Idempotent, so it's safe to call from
    /// every state change.
    private func updatePowerAssertion() {
        let required = PlayerPowerAssertion.required(isLiveStream: isLiveStream, isPlaying: isPlaying)
        guard required != heldAssertion else { return }
        releasePowerAssertion()
        guard let type = required.ioKitType else { return }

        var id: IOPMAssertionID = 0
        let reason = required == .noIdleSleep ? "StreamClient paused live stream" : "StreamClient video playback"
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            print("[Player] Failed to take \(type) assertion: \(result)")
            return
        }
        sleepAssertionID = id
        heldAssertion = required
    }

    private func releasePowerAssertion() {
        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
        heldAssertion = .none
    }
    #endif

    @ViewBuilder
    private func subtitleLabel(_ text: String, size: SubtitleSize, showBackground: Bool) -> some View {
        if showBackground {
            Text(text)
                .font(.system(size: size.fontSize, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingSM)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
        } else {
            Text(text)
                .font(.system(size: size.fontSize, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: -1, y: -1)
                .shadow(color: .black, radius: 0, x: 1, y: -1)
                .shadow(color: .black, radius: 0, x: -1, y: 1)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .shadow(color: .black, radius: 2, x: 0, y: 0)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingSM)
        }
    }

    private func autoSelectSubtitleIfNeeded() {
        let prefs = UserPreferences.load()
        guard prefs.subtitleMode == .auto,
              let preferred = prefs.preferredSubtitleLanguage else { return }
        let tracks = getTrackListFunc?() ?? []
        let subtitleTracks = tracks.filter { $0.type == "sub" }
        // Match by language first, then fall back to codec (e.g. "eia_608" for CC)
        let match = subtitleTracks.first(where: { $0.lang == preferred })
            ?? subtitleTracks.first(where: { $0.codec == preferred })
        if let match {
            setSubtitleTrackFunc?(match.id)
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
            if !showControls && showSettingsPanel {
                showSettingsPanel = false
            }
        }

        if showControls {
            #if os(macOS)
            NSCursor.setHiddenUntilMouseMoves(false)
            #endif
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        guard !showSettingsPanel else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = false
                    }
                    #if os(macOS)
                    NSCursor.setHiddenUntilMouseMoves(true)
                    #endif
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    PlayerView(
        url: URL(string: "https://example.com/video.mp4")!,
        title: "Sample Video"
    )
    .environmentObject(AppState())
    .environmentObject(PVRClient())
}
#endif
