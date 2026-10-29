//
//  MPVContainerView+tvOS.swift
//  nextpvr-apple-client
//
//  tvOS MPVContainerView implementation — extracted from PlayerView.swift
//

#if os(tvOS)

import UIKit
import SwiftUI
import AVFoundation

// tvOS implementation — PixelBuffer renderer (AVSampleBufferDisplayLayer)
struct MPVContainerView: UIViewRepresentable {
    typealias UIViewType = MPVPlayerPixelBufferView

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
    let activePlayerSession: any ActivePlayerSessionManaging
    let networkEventLogger: any NetworkEventLogging

    var onPlaybackEnded: (() -> Void)?
    var onPlaybackRestarted: (() -> Void)?
    /// Set for live streams. NextPVR can't seek an open `/live` response, so the
    /// remote's skip buttons have to reopen the stream at a byte offset instead of
    /// issuing an mpv seek — an mpv seek only moves inside the demuxer cache, which
    /// leaves the viewer permanently behind the live edge after a pause (#126).
    /// Takes a signed delta in seconds and returns whether it handled the seek;
    /// when it returns false the plain mpv seek is used instead.
    var onLiveSeek: ((Double) -> Bool)?
    /// Fired right before a catch-up (#119) seek is issued via the remote's
    /// skip buttons/hold-to-scrub, so PlayerView can show its "Seeking…"
    /// overlay — these calls go straight to `view.seek(seconds:)` below,
    /// bypassing PlayerView's own seekForward/seekBackward bindings
    /// entirely, so nothing else observes them.
    var onCatchupSeekStarted: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onToggleControls: (() -> Void)?
    var onShowControls: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    @Binding var cleanupAction: (() -> Void)?
    @Binding var getTrackListFunc: (() -> [MPVTrack])?
    @Binding var setAudioTrackFunc: ((Int) -> Void)?
    @Binding var setSubtitleTrackFunc: ((Int?) -> Void)?
    @Binding var getSubtitleTextFunc: (() -> String?)?
    @Binding var showSettingsPanel: Bool
    @Binding var settingsTab: StreamSettingsTab
    @Binding var tvFocusedTrackIndex: Int
    var tvTrackCountProvider: (() -> Int)?
    var tvSelectTrack: (() -> Void)?
    var onDismissSettingsPanel: (() -> Void)?

    private func configureCommonCallbacks(for view: MPVPlayerPixelBufferView) {
        view.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        view.onPlaybackEnded = onPlaybackEnded
        view.onPlaybackRestarted = onPlaybackRestarted
        view.onVideoInfoUpdate = onVideoInfoUpdate
        view.onPlayPause = onTogglePlayPause
        view.onSeekForward = { multiplier in
            let delta = self.seekForwardTime * multiplier
            if self.onLiveSeek?(Double(delta)) != true {
                self.onCatchupSeekStarted?()
                view.seek(seconds: delta)
            }
            self.onShowControls?()
        }
        view.onSeekBackward = { multiplier in
            let delta = -self.seekBackwardTime * multiplier
            if self.onLiveSeek?(Double(delta)) != true {
                self.onCatchupSeekStarted?()
                view.seek(seconds: delta)
            }
            self.onShowControls?()
        }
        view.onSelect = onToggleControls
        view.onMenu = onDismiss
    }

    private func setupSeekBindings(for view: MPVPlayerPixelBufferView) {
        DispatchQueue.main.async {
            self.seekForward = {
                view.seek(seconds: self.seekForwardTime)
                self.onShowControls?()
            }
            self.seekBackward = {
                view.seek(seconds: -self.seekBackwardTime)
                self.onShowControls?()
            }
            self.seekToPosition = { position in
                view.seekTo(position: position)
            }
            self.reloadURL = { newURL in
                view.loadURL(newURL)
            }
            self.getTrackListFunc = { view.getTrackList() }
            self.setAudioTrackFunc = { view.setAudioTrack($0) }
            self.setSubtitleTrackFunc = { view.setSubtitleTrack($0) }
            self.getSubtitleTextFunc = { view.getSubtitleText() }
        }
    }

    func makeUIView(context: Context) -> MPVPlayerPixelBufferView {
        let view = MPVPlayerPixelBufferView(frame: .zero, session: activePlayerSession, networkEventLogger: networkEventLogger)
        view.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress, recordingStartTime: recordingStartTime, preferKeyframeSeek: preferKeyframeSeek)
        configureCommonCallbacks(for: view)
        view.setStreamHeaders(streamHeaders)
        view.loadURL(url)
        view.startPositionPolling()
        if isRecordingInProgress {
            view.startRecordingMonitor(url: url)
            view.recordingMonitor?.onRecordingFinished = {
                print("Recording completed, normal playback mode")
            }
        }
        context.coordinator.playerView = view
        DispatchQueue.main.async {
            self.cleanupAction = { view.cleanup() }
        }
        setupSeekBindings(for: view)
        return view
    }

    func updateUIView(_ uiView: MPVPlayerPixelBufferView, context: Context) {
        if isPlaying { uiView.play() } else { uiView.pause() }
        applySettingsCallbacks(to: uiView)
    }

    static func dismantleUIView(_ uiView: MPVPlayerPixelBufferView, coordinator: Coordinator) {
        uiView.cleanup()
    }

    private func applySettingsCallbacks(to view: MPVPlayerPixelBufferView) {
        let panelBinding = $showSettingsPanel
        let tabBinding = $settingsTab
        let focusBinding = $tvFocusedTrackIndex
        let openSettings = onOpenSettings
        view.onUpArrow = openSettings
        let dismissPanel = onDismissSettingsPanel
        view.onMenuOverride = {
            print("[tvOS] onMenuOverride called, panelOpen=\(panelBinding.wrappedValue)")
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.25)) { dismissPanel?() }
            return true
        }
        view.onLeftArrow = {
            guard panelBinding.wrappedValue else { return false }
            switch tabBinding.wrappedValue {
            case .video:
                withAnimation(.easeInOut(duration: 0.25)) { dismissPanel?() }
            case .audio:
                withAnimation(.easeInOut(duration: 0.15)) { tabBinding.wrappedValue = .video }
                focusBinding.wrappedValue = -1
            case .subtitles:
                withAnimation(.easeInOut(duration: 0.15)) { tabBinding.wrappedValue = .audio }
                focusBinding.wrappedValue = -1
            }
            return true
        }
        view.onRightArrow = {
            guard panelBinding.wrappedValue else { return false }
            switch tabBinding.wrappedValue {
            case .video:
                withAnimation(.easeInOut(duration: 0.15)) { tabBinding.wrappedValue = .audio }
                focusBinding.wrappedValue = -1
            case .audio:
                withAnimation(.easeInOut(duration: 0.15)) { tabBinding.wrappedValue = .subtitles }
                focusBinding.wrappedValue = -1
            case .subtitles:
                // Right-click on the last tab dismisses the panel (mirrors left-click on .video)
                withAnimation(.easeInOut(duration: 0.25)) { dismissPanel?() }
            }
            return true
        }
        view.onDownArrow = {
            guard panelBinding.wrappedValue else { return false }
            let maxIndex = (self.tvTrackCountProvider?() ?? 0) - 1
            if maxIndex >= 0 && focusBinding.wrappedValue < maxIndex {
                focusBinding.wrappedValue += 1
            }
            return true
        }
        view.onSelectOverride = {
            guard panelBinding.wrappedValue else { return false }
            self.tvSelectTrack?()
            return true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var playerView: MPVPlayerPixelBufferView?
    }
}

#endif // os(tvOS)
