//
//  HLSPlaylistDurationTests.swift
//  NexusPVRTests
//
//  Tests for HLS playlist duration parsing, including malformed #EXTINF lines (#171).
//

import Testing
import Foundation
@testable import NextPVR

struct HLSPlaylistDurationTests {

    @Test func sumsWellFormedPlaylist() {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:7
        #EXTINF:6.006,
        seg0.ts
        #EXTINF:6.006,Title
        seg1.ts
        #EXTINF:4.5
        seg2.ts
        """
        #expect(abs(HLSPlaylistDuration.totalSeconds(in: playlist) - 16.512) < 0.0001)
    }

    @Test func emptyExtinfIsSkippedWithoutCrashing() {
        #expect(HLSPlaylistDuration.totalSeconds(in: "#EXTINF:") == 0)
    }

    @Test func extinfWithTitleButNoDurationIsSkipped() {
        #expect(HLSPlaylistDuration.totalSeconds(in: "#EXTINF:,title") == 0)
    }

    @Test func extinfWithTrailingComma() {
        #expect(HLSPlaylistDuration.totalSeconds(in: "#EXTINF:6.006,") == 6.006)
    }

    @Test func malformedLinesDoNotDiscardValidSegments() {
        let playlist = "#EXTINF:6,\nseg0.ts\n#EXTINF:\n#EXTINF:abc,\n#EXTINF: 4 ,x\r\nseg1.ts\n#EXTINF:"
        #expect(HLSPlaylistDuration.totalSeconds(in: playlist) == 10)
    }

    @Test func emptyPlaylistIsZero() {
        #expect(HLSPlaylistDuration.totalSeconds(in: "") == 0)
    }
}
