//
//  MPVContainerView+iOS.swift
//  nextpvr-apple-client
//
//  iOS MPVContainerView implementation — extracted from PlayerView.swift
//

#if os(iOS)

import UIKit
import SwiftUI
import AVFoundation

// iOS implementation — runtime-selected renderer (OpenGL/Metal)
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
    var onVideoInfoUpdate: ((String?, Int?, String?, String?, Int64, String?, Double) -> Void)?
    @Binding var cleanupAction: (() -> Void)?
    @Binding var pixelBufferViewRef: MPVPlayerPixelBufferView?
    @Binding var getTrackListFunc: (() -> [MPVTrack])?
    @Binding var setAudioTrackFunc: ((Int) -> Void)?
    @Binding var setSubtitleTrackFunc: ((Int?) -> Void)?
    @Binding var getSubtitleTextFunc: (() -> String?)?

    private func configureCommonCallbacks(for view: MPVPlayerGLView) {
        view.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress)
        view.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        view.onPlaybackEnded = onPlaybackEnded
        view.onVideoInfoUpdate = onVideoInfoUpdate
    }

    private func configureCommonCallbacks(for view: MPVPlayerMetalView) {
        view.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress)
        view.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        view.onPlaybackEnded = onPlaybackEnded
        view.onVideoInfoUpdate = onVideoInfoUpdate
    }

    private func configureCommonCallbacks(for view: MPVPlayerPixelBufferView) {
        view.setup(errorBinding: $errorMessage, isRecordingInProgress: isRecordingInProgress)
        view.onPositionUpdate = { position, dur in
            DispatchQueue.main.async {
                self.currentPosition = position
                self.duration = dur
            }
        }
        view.onPlaybackEnded = onPlaybackEnded
        view.onVideoInfoUpdate = onVideoInfoUpdate
    }

    private func setupSeekBindings(for view: MPVPlayerGLView) {
        DispatchQueue.main.async {
            self.seekForward = {
                view.seek(seconds: self.seekForwardTime)
            }
            self.seekBackward = {
                view.seek(seconds: -self.seekBackwardTime)
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

    private func setupSeekBindings(for view: MPVPlayerMetalView) {
        DispatchQueue.main.async {
            self.seekForward = {
                view.seek(seconds: self.seekForwardTime)
            }
            self.seekBackward = {
                view.seek(seconds: -self.seekBackwardTime)
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
            }
            self.seekBackward = {
                view.seek(seconds: -self.seekBackwardTime)
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
        let gpuAPI = UserPreferences.load().iosGPUAPI

        if gpuAPI == .pixelbuffer {
            let view = MPVPlayerPixelBufferView(frame: .zero, session: activePlayerSession, networkEventLogger: networkEventLogger)
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
                self.pixelBufferViewRef = view
            }
            setupSeekBindings(for: view)
            return view
        }

        if gpuAPI == .metal {
            let view = MPVPlayerMetalView(frame: .zero, networkEventLogger: networkEventLogger)
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

        let view = MPVPlayerGLView(frame: .zero, networkEventLogger: networkEventLogger)
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
            return
        }
        if let metalView = uiView as? MPVPlayerMetalView {
            if isPlaying { metalView.play() } else { metalView.pause() }
            return
        }
        if let glView = uiView as? MPVPlayerGLView {
            if isPlaying { glView.play() } else { glView.pause() }
            return
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
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

    class Coordinator {
        var playerView: UIView?
    }
}

#endif // os(iOS)
