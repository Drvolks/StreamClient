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
    /// Verifies that `MPVPlayerCore.scheduleOnMain` delivers work to the main dispatch queue
    /// even when called from a background queue (simulating the mpv render callback path).
    /// Uses dispatchPrecondition to assert queue identity, not just thread identity.
    @Test func openGLCallbackMainQueueRegression() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .background).async {
                MPVPlayerCore.scheduleOnMain {
                    dispatchPrecondition(condition: .onQueue(.main))
                    continuation.resume()
                }
            }
        }
    }
}
