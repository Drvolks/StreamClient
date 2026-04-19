//
//  OpenGLCallbackTests.swift
//  NexusPVRTests
//
//  Regression test for OpenGL crash: MPVPlayerGLView.draw(_:) was being
//  triggered from a non-main queue via the mpv update callback path.
//

import Testing
import Foundation
@testable import NextPVR

struct OpenGLCallbackTests {

    /// Regression test: OpenGL callback main-queue scheduling.
    /// Verifies that `MPVPlayerCore.scheduleOnMain` delivers work to the main thread
    /// even when called from a background queue (simulating the mpv render callback path).
    @Test func openGLCallbackMainQueueRegression() async {
        let isMainThread = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                MPVPlayerCore.scheduleOnMain {
                    continuation.resume(returning: Thread.isMainThread)
                }
            }
        }

        #expect(isMainThread == true)
    }
}
