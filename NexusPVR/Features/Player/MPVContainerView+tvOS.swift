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

// tvOS implementation — runtime-selected renderer (Metal/OpenGL)
struct MPVContainerView: UIViewRepresentable {
    typealias UIViewType = UIView

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
    let activePlayerSession: any ActivePlayerSessionManaging
    let networkEventLogger: any NetworkEventLogging

    var onPlaybackEnded: (() -> Void)?
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

    private func configureCommonCallbacks(for view: MPVPlayerMetalView) {
        view.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        view.onPlaybackEnded = onPlaybackEnded
        view.onVideoInfoUpdate = onVideoInfoUpdate
        view.onPlayPause = onTogglePlayPause
        view.onSeekForward = {
            view.seek(seconds: self.seekForwardTime)
            self.onShowControls?()
        }
        view.onSeekBackward = {
            view.seek(seconds: -self.seekBackwardTime)
            self.onShowControls?()
        }
        view.onSelect = onToggleControls
        view.onMenu = onDismiss
    }

    private func configureCommonCallbacks(for view: MPVPlayerGLView) {
        view.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        view.onPlaybackEnded = onPlaybackEnded
        view.onVideoInfoUpdate = onVideoInfoUpdate
        view.onPlayPause = onTogglePlayPause
        view.onSeekForward = {
            view.seek(seconds: self.seekForwardTime)
            self.onShowControls?()
        }
        view.onSeekBackward = {
            view.seek(seconds: -self.seekBackwardTime)
            self.onShowControls?()
        }
        view.onSelect = onToggleControls
        view.onMenu = onDismiss
    }

    private func configureCommonCallbacks(for view: MPVPlayerPixelBufferView) {
        view.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        view.onPlaybackEnded = onPlaybackEnded
        view.onVideoInfoUpdate = onVideoInfoUpdate
        view.onPlayPause = onTogglePlayPause
        view.onSeekForward = {
            view.seek(seconds: self.seekForwardTime)
            self.onShowControls?()
        }
        view.onSeekBackward = {
            view.seek(seconds: -self.seekBackwardTime)
            self.onShowControls?()
        }
        view.onSelect = onToggleControls
        view.onMenu = onDismiss
    }

    private func setupSeekBindings(for view: MPVPlayerMetalView) {
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
            self.getTrackListFunc = { view.getTrackList() }
            self.setAudioTrackFunc = { view.setAudioTrack($0) }
            self.setSubtitleTrackFunc = { view.setSubtitleTrack($0) }
            self.getSubtitleTextFunc = { view.getSubtitleText() }
        }
    }

    private func setupSeekBindings(for view: MPVPlayerGLView) {
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
            self.getTrackListFunc = { view.getTrackList() }
            self.setAudioTrackFunc = { view.setAudioTrack($0) }
            self.setSubtitleTrackFunc = { view.setSubtitleTrack($0) }
            self.getSubtitleTextFunc = { view.getSubtitleText() }
        }
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
            self.getTrackListFunc = { view.getTrackList() }
            self.setAudioTrackFunc = { view.setAudioTrack($0) }
            self.setSubtitleTrackFunc = { view.setSubtitleTrack($0) }
            self.getSubtitleTextFunc = { view.getSubtitleText() }
        }
    }

    func makeUIView(context: Context) -> UIView {
        let gpuAPI = UserPreferences.load().tvosGPUAPI

        if gpuAPI == .pixelbuffer {
            let view = MPVPlayerPixelBufferView(frame: .zero, session: activePlayerSession, networkEventLogger: networkEventLogger)
            view.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress)
            configureCommonCallbacks(for: view)
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

        if gpuAPI == .opengl {
            let view = MPVPlayerGLView(frame: .zero, networkEventLogger: networkEventLogger)
            view.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress)
            configureCommonCallbacks(for: view)
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

        let view = MPVPlayerMetalView(frame: .zero, networkEventLogger: networkEventLogger)
        view.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress)
        configureCommonCallbacks(for: view)
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

    func updateUIView(_ uiView: UIView, context: Context) {
        if let pbView = uiView as? MPVPlayerPixelBufferView {
            if isPlaying { pbView.play() } else { pbView.pause() }
            applySettingsCallbacks(to: pbView)
            return
        }
        if let metalView = uiView as? MPVPlayerMetalView {
            if isPlaying { metalView.play() } else { metalView.pause() }
            applySettingsCallbacks(to: metalView)
            return
        }
        if let glView = uiView as? MPVPlayerGLView {
            if isPlaying { glView.play() } else { glView.pause() }
            applySettingsCallbacks(to: glView)
            return
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let pbView = uiView as? MPVPlayerPixelBufferView {
            pbView.cleanup()
        } else if let metalView = uiView as? MPVPlayerMetalView {
            metalView.cleanup()
        } else {
            (uiView as? MPVPlayerGLView)?.cleanup()
        }
    }

    private func applySettingsCallbacks(to view: MPVPlayerMetalView) {
        let panelBinding = $showSettingsPanel
        let tabBinding = $settingsTab
        let focusBinding = $tvFocusedTrackIndex
        let openSettings = onOpenSettings
        view.onUpArrow = openSettings
        view.onMenuOverride = {
            print("[tvOS] onMenuOverride called, panelOpen=\(panelBinding.wrappedValue)")
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.25)) { panelBinding.wrappedValue = false }
            focusBinding.wrappedValue = -1
            return true
        }
        view.onLeftArrow = {
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                switch tabBinding.wrappedValue {
                case .video:
                    withAnimation(.easeInOut(duration: 0.25)) { panelBinding.wrappedValue = false }
                case .audio: tabBinding.wrappedValue = .video
                case .subtitles: tabBinding.wrappedValue = .audio
                }
            }
            focusBinding.wrappedValue = -1
            return true
        }
        view.onRightArrow = {
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                switch tabBinding.wrappedValue {
                case .video: tabBinding.wrappedValue = .audio
                case .audio: tabBinding.wrappedValue = .subtitles
                case .subtitles: break
                }
            }
            focusBinding.wrappedValue = -1
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

    private func applySettingsCallbacks(to view: MPVPlayerPixelBufferView) {
        let panelBinding = $showSettingsPanel
        let tabBinding = $settingsTab
        let focusBinding = $tvFocusedTrackIndex
        let openSettings = onOpenSettings
        view.onUpArrow = openSettings
        view.onMenuOverride = {
            print("[tvOS] onMenuOverride called, panelOpen=\(panelBinding.wrappedValue)")
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.25)) { panelBinding.wrappedValue = false }
            focusBinding.wrappedValue = -1
            return true
        }
        view.onLeftArrow = {
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                switch tabBinding.wrappedValue {
                case .video:
                    withAnimation(.easeInOut(duration: 0.25)) { panelBinding.wrappedValue = false }
                case .audio: tabBinding.wrappedValue = .video
                case .subtitles: tabBinding.wrappedValue = .audio
                }
            }
            focusBinding.wrappedValue = -1
            return true
        }
        view.onRightArrow = {
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                switch tabBinding.wrappedValue {
                case .video: tabBinding.wrappedValue = .audio
                case .audio: tabBinding.wrappedValue = .subtitles
                case .subtitles: break
                }
            }
            focusBinding.wrappedValue = -1
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

    private func applySettingsCallbacks(to view: MPVPlayerGLView) {
        let panelBinding = $showSettingsPanel
        let tabBinding = $settingsTab
        let focusBinding = $tvFocusedTrackIndex
        let openSettings = onOpenSettings
        view.onUpArrow = openSettings
        view.onMenuOverride = {
            print("[tvOS] onMenuOverride called, panelOpen=\(panelBinding.wrappedValue)")
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.25)) { panelBinding.wrappedValue = false }
            focusBinding.wrappedValue = -1
            return true
        }
        view.onLeftArrow = {
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                switch tabBinding.wrappedValue {
                case .video:
                    withAnimation(.easeInOut(duration: 0.25)) { panelBinding.wrappedValue = false }
                case .audio: tabBinding.wrappedValue = .video
                case .subtitles: tabBinding.wrappedValue = .audio
                }
            }
            focusBinding.wrappedValue = -1
            return true
        }
        view.onRightArrow = {
            guard panelBinding.wrappedValue else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                switch tabBinding.wrappedValue {
                case .video: tabBinding.wrappedValue = .audio
                case .audio: tabBinding.wrappedValue = .subtitles
                case .subtitles: break
                }
            }
            focusBinding.wrappedValue = -1
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
        var playerView: UIView?
    }
}

#endif // os(tvOS)
