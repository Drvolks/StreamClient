//
//  RecordingsViewModelTSTests.swift
//  NexusPVRTests
//
//  Tests for the MPEG-TS helpers in RecordingsViewModel that consume a full
//  188-byte TS packet containing a PES header with a PTS. These exercise:
//  extractFirstPTS, extractLastPTS, extractFirstPTSSample, extractLastPTSSample,
//  extractLastPTS(matchingPID:), extractPTSSamples, and extractPTSValues.
//

import Testing
import Foundation
@testable import NextPVR

struct RecordingsViewModelTSTests {

    // MARK: - TS packet builder

    /// Build a 188-byte MPEG-TS packet carrying a PES start with the given PTS
    /// on the given PID. Stream id is 0xE0 (video) by default. The packet has
    /// PUSI=1, AFC=01 (payload only), and no adaptation field.
    private func tsPacket(pid: Int, pts: UInt64, streamId: UInt8 = 0xE0) -> [UInt8] {
        var packet = [UInt8](repeating: 0xFF, count: 188)
        packet[0] = 0x47

        // PUSI bit + upper 5 bits of PID
        packet[1] = 0x40 | UInt8((pid >> 8) & 0x1F)
        // Lower 8 bits of PID
        packet[2] = UInt8(pid & 0xFF)
        // AFC = 01 (payload only) + continuity counter 0
        packet[3] = 0x10

        // PES header starts at byte 4
        packet[4] = 0x00  // start code prefix
        packet[5] = 0x00
        packet[6] = 0x01
        packet[7] = streamId
        packet[8] = 0x00  // packet length (unused)
        packet[9] = 0x00
        packet[10] = 0x80 // flags1 (marker bits)
        packet[11] = 0x80 // flags2: PTS present
        packet[12] = 0x05 // PES header data length (PTS is 5 bytes)

        // Encode the PTS into bytes 13..17 using the standard layout:
        //   byte 0: 0010 [P32 P31 P30] 1
        //   byte 1: [P29..P22]
        //   byte 2: [P21..P15] 1
        //   byte 3: [P14..P7]
        //   byte 4: [P6..P0] 1
        packet[13] = UInt8(((pts >> 30) & 0x07) << 1) | 0x21
        packet[14] = UInt8((pts >> 22) & 0xFF)
        packet[15] = UInt8((pts >> 15) & 0x7F) << 1 | 0x01
        packet[16] = UInt8((pts >> 7) & 0xFF)
        packet[17] = UInt8(pts & 0x7F) << 1 | 0x01

        return packet
    }

    // MARK: - extractFirstPTS / extractLastPTS

    @Test("extractFirstPTS reads the PTS from a single valid TS packet")
    func firstPTS_singlePacket() {
        let packet = tsPacket(pid: 0x0100, pts: 9_000_000)
        // Need at least one *more* packet after the first to satisfy the
        // `offset + packetSize <= data.count` loop guard on the second pass.
        let data = Data(packet + packet)
        #expect(RecordingsViewModel.extractFirstPTS(from: data) == 9_000_000)
    }

    @Test("extractLastPTS returns the PTS from the last packet when multiple are present")
    func lastPTS_multiPacket() {
        let first = tsPacket(pid: 0x0100, pts: 1_000_000)
        let last = tsPacket(pid: 0x0100, pts: 2_000_000)
        let data = Data(first + last)
        #expect(RecordingsViewModel.extractLastPTS(from: data) == 2_000_000)
    }

    @Test("extractLastPTS returns nil when there are no PES packets")
    func lastPTS_empty() {
        // Two sync-only packets with no PES start code: the parser advances
        // through them without finding a PTS.
        var bytes = [UInt8](repeating: 0x00, count: 188 * 2)
        bytes[0] = 0x47
        bytes[188] = 0x47
        #expect(RecordingsViewModel.extractLastPTS(from: Data(bytes)) == nil)
    }

    // MARK: - extractFirstPTSSample / extractLastPTSSample

    @Test("extractFirstPTSSample returns both PID and PTS")
    func firstPTSSample() {
        let packet = tsPacket(pid: 0x0101, pts: 5_000_000)
        let data = Data(packet + packet)
        let sample = RecordingsViewModel.extractFirstPTSSample(from: data)
        #expect(sample?.pid == 0x0101)
        #expect(sample?.pts == 5_000_000)
    }

    @Test("extractLastPTSSample returns the last-seen PID/PTS pair")
    func lastPTSSample() {
        let a = tsPacket(pid: 0x0100, pts: 1_000)
        let b = tsPacket(pid: 0x0200, pts: 2_000)
        let data = Data(a + b)
        let sample = RecordingsViewModel.extractLastPTSSample(from: data)
        #expect(sample?.pid == 0x0200)
        #expect(sample?.pts == 2_000)
    }

    @Test("extractLastPTSSample returns nil for empty TS data")
    func lastPTSSample_empty() {
        var bytes = [UInt8](repeating: 0x00, count: 188 * 2)
        bytes[0] = 0x47
        bytes[188] = 0x47
        #expect(RecordingsViewModel.extractLastPTSSample(from: Data(bytes)) == nil)
    }

    // MARK: - extractLastPTS(matchingPID:)

    @Test("extractLastPTS(matchingPID:) only considers packets for the requested PID")
    func lastPTS_matchingPID() {
        let video = tsPacket(pid: 0x0100, pts: 10_000)
        let audio = tsPacket(pid: 0x0200, pts: 20_000)
        let videoLater = tsPacket(pid: 0x0100, pts: 15_000)
        let data = Data(video + audio + videoLater)
        #expect(RecordingsViewModel.extractLastPTS(from: data, matchingPID: 0x0100) == 15_000)
        #expect(RecordingsViewModel.extractLastPTS(from: data, matchingPID: 0x0200) == 20_000)
    }

    @Test("extractLastPTS(matchingPID:) returns nil when the PID never appears")
    func lastPTS_matchingPID_missing() {
        let packet = tsPacket(pid: 0x0100, pts: 1)
        let data = Data(packet + packet)
        #expect(RecordingsViewModel.extractLastPTS(from: data, matchingPID: 0x0999) == nil)
    }

    // MARK: - extractPTSSamples

    @Test("extractPTSSamples returns all samples in stream order")
    func ptsSamples_inOrder() {
        let a = tsPacket(pid: 0x0100, pts: 100)
        let b = tsPacket(pid: 0x0200, pts: 200)
        let c = tsPacket(pid: 0x0100, pts: 300)
        let data = Data(a + b + c)
        let samples = RecordingsViewModel.extractPTSSamples(from: data)
        #expect(samples.count == 3)
        #expect(samples[0].pid == 0x0100)
        #expect(samples[0].pts == 100)
        #expect(samples[1].pid == 0x0200)
        #expect(samples[1].pts == 200)
        #expect(samples[2].pid == 0x0100)
        #expect(samples[2].pts == 300)
    }

    @Test("extractPTSSamples returns empty array for TS data with no PES packets")
    func ptsSamples_empty() {
        var bytes = [UInt8](repeating: 0x00, count: 188 * 2)
        bytes[0] = 0x47
        bytes[188] = 0x47
        #expect(RecordingsViewModel.extractPTSSamples(from: Data(bytes)).isEmpty)
    }

    // MARK: - estimateDurationSecondsAcrossCommonPIDs

    @Test("estimateDurationSecondsAcrossCommonPIDs picks the best PID-matched delta")
    func estimateAcrossPIDs_picksBest() {
        // Head window has both audio (0x100) and video (0x200) at t=0.
        // Tail window has both at 3600 seconds later (324_000_000 ticks).
        // Expected: 3600.
        let headData = Data(
            tsPacket(pid: 0x0100, pts: 0) +
            tsPacket(pid: 0x0200, pts: 0)
        )
        let tailData = Data(
            tsPacket(pid: 0x0100, pts: 324_000_000) +
            tsPacket(pid: 0x0200, pts: 324_000_000)
        )
        let secs = RecordingsViewModel.estimateDurationSecondsAcrossCommonPIDs(
            headData: headData,
            tailData: tailData,
            expectedSeconds: 3600
        )
        #expect(secs == 3600)
    }

    @Test("estimateDurationSecondsAcrossCommonPIDs returns nil when no PIDs overlap")
    func estimateAcrossPIDs_noOverlap() {
        let headData = Data(tsPacket(pid: 0x0100, pts: 0) + tsPacket(pid: 0x0100, pts: 0))
        let tailData = Data(tsPacket(pid: 0x0200, pts: 324_000_000) + tsPacket(pid: 0x0200, pts: 324_000_000))
        let secs = RecordingsViewModel.estimateDurationSecondsAcrossCommonPIDs(
            headData: headData,
            tailData: tailData,
            expectedSeconds: 3600
        )
        #expect(secs == nil)
    }

    @Test("estimateDurationSecondsAcrossCommonPIDs returns nil when head is empty")
    func estimateAcrossPIDs_emptyHead() {
        let tailData = Data(tsPacket(pid: 0x0100, pts: 0) + tsPacket(pid: 0x0100, pts: 0))
        let secs = RecordingsViewModel.estimateDurationSecondsAcrossCommonPIDs(
            headData: Data(),
            tailData: tailData,
            expectedSeconds: 3600
        )
        #expect(secs == nil)
    }
}
