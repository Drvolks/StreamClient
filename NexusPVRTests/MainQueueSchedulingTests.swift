//
//  MainQueueSchedulingTests.swift
//  NexusPVRTests
//
//  The PixelBuffer views hop from mpv's threads to the main queue through
//  `MPVPlayerCore.scheduleOnMain` (display-layer geometry updates).
//

import Testing
import Foundation
@testable import NextPVR

struct MainQueueSchedulingTests {

    /// Uses dispatchPrecondition to assert queue identity, not just thread identity.
    @Test func scheduleOnMainRunsOnMainQueue() async {
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
