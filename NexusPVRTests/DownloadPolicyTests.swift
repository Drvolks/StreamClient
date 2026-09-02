//
//  DownloadPolicyTests.swift
//  NexusPVRTests
//
//  Coverage for the stop / progress math behind offline downloads.
//

import Testing
import Foundation
@testable import NextPVR

struct DownloadPolicyTests {

    @Test("A catch-up download stops at the programme length even though the archive runs much longer")
    func stopsAtProgrammeLength() {
        // A one-hour show that aired two days ago: the session's archive is
        // ~48 hours long, so nothing but this check ends the download.
        let expected = 3600 + DownloadPolicy.catchupTailSeconds

        #expect(!DownloadPolicy.shouldStop(writtenSeconds: 0, expectedDuration: expected))
        #expect(!DownloadPolicy.shouldStop(writtenSeconds: 3600, expectedDuration: expected))
        #expect(DownloadPolicy.shouldStop(writtenSeconds: expected, expectedDuration: expected))
        #expect(DownloadPolicy.shouldStop(writtenSeconds: 48 * 3600, expectedDuration: expected))
    }

    @Test("A source with no expected duration runs to its own end of stream")
    func neverStopsWithoutExpectedDuration() {
        #expect(!DownloadPolicy.shouldStop(writtenSeconds: 100_000, expectedDuration: nil))
        #expect(!DownloadPolicy.shouldStop(writtenSeconds: 10, expectedDuration: 0))
    }

    @Test("Progress is the written fraction, clamped to 0...1")
    func progressFraction() {
        #expect(DownloadPolicy.progress(writtenSeconds: 0, expectedDuration: 100) == 0)
        #expect(DownloadPolicy.progress(writtenSeconds: 25, expectedDuration: 100) == 0.25)
        #expect(DownloadPolicy.progress(writtenSeconds: 100, expectedDuration: 100) == 1)
        // Overshoot before the stop check runs must not report >100%.
        #expect(DownloadPolicy.progress(writtenSeconds: 150, expectedDuration: 100) == 1)
        #expect(DownloadPolicy.progress(writtenSeconds: -5, expectedDuration: 100) == 0)
    }

    @Test("Progress is unknown when there's no expected duration")
    func progressUnknown() {
        #expect(DownloadPolicy.progress(writtenSeconds: 42, expectedDuration: nil) == nil)
        #expect(DownloadPolicy.progress(writtenSeconds: 42, expectedDuration: 0) == nil)
    }

    @Test("A file with almost nothing in it counts as a failure, not a short recording")
    func usability() {
        #expect(!DownloadPolicy.isUsable(writtenSeconds: 0))
        #expect(!DownloadPolicy.isUsable(writtenSeconds: 1))
        #expect(DownloadPolicy.isUsable(writtenSeconds: DownloadPolicy.minimumUsableSeconds))
        #expect(DownloadPolicy.isUsable(writtenSeconds: 3600))
    }
}
