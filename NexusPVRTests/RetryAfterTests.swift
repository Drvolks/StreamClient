//
//  RetryAfterTests.swift
//  NexusPVRTests
//
//  Parsing Retry-After for a rate-limited sign-in.
//

import Foundation
import Testing
@testable import NextPVR

struct RetryAfterTests {

    @Test("Missing or unreadable header uses the default")
    func defaults() {
        #expect(RetryAfter.delay(from: nil) == RetryAfter.defaultDelay)
        #expect(RetryAfter.delay(from: "") == RetryAfter.defaultDelay)
        #expect(RetryAfter.delay(from: "soon") == RetryAfter.defaultDelay)
    }

    @Test("Delay seconds, clamped")
    func seconds() {
        #expect(RetryAfter.delay(from: "42") == 42)
        #expect(RetryAfter.delay(from: "0") == 1)
        #expect(RetryAfter.delay(from: "86400") == RetryAfter.maximumDelay)
    }

    @Test("HTTP date")
    func httpDate() {
        let now = Date(timeIntervalSince1970: 784_111_777) // Sun, 06 Nov 1994 08:49:37 GMT
        #expect(RetryAfter.delay(from: "Sun, 06 Nov 1994 08:51:37 GMT", now: now) == 120)
    }
}
