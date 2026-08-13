//
//  PlayerPowerAssertionTests.swift
//  NexusPVRTests
//
//  Tests for what the player keeps awake while it's on screen (issue #125).
//

import Testing
@testable import NextPVR

struct PlayerPowerAssertionTests {

    @Test("Playing video keeps the display awake")
    func playingHoldsDisplay() {
        #expect(PlayerPowerAssertion.required(isLiveStream: true, isPlaying: true) == .noDisplaySleep)
        #expect(PlayerPowerAssertion.required(isLiveStream: false, isPlaying: true) == .noDisplaySleep)
    }

    @Test("A paused live stream keeps the system awake so the keep-alive keeps firing")
    func pausedLiveHoldsSystem() {
        // The screen may go dark, but the machine must not idle-sleep — NextPVR
        // reclaims the tuner after 15s without a renewal.
        #expect(PlayerPowerAssertion.required(isLiveStream: true, isPlaying: false) == .noIdleSleep)
    }

    @Test("A paused recording lets the Mac sleep normally")
    func pausedRecordingHoldsNothing() {
        #expect(PlayerPowerAssertion.required(isLiveStream: false, isPlaying: false) == .none)
    }

    @Test("Pausing live TV changes the assertion rather than dropping it")
    func pausingLiveSwapsRatherThanReleases() {
        let playing = PlayerPowerAssertion.required(isLiveStream: true, isPlaying: true)
        let paused = PlayerPowerAssertion.required(isLiveStream: true, isPlaying: false)
        #expect(playing != paused)
        #expect(paused != PlayerPowerAssertion.none)
    }

    #if os(macOS)
    @Test("Every awake state maps to an IOKit assertion type, and .none to nil")
    func ioKitTypesAreDistinct() {
        let display = PlayerPowerAssertion.noDisplaySleep.ioKitType
        let idle = PlayerPowerAssertion.noIdleSleep.ioKitType
        #expect(display != nil)
        #expect(idle != nil)
        #expect(display != idle)
        #expect(PlayerPowerAssertion.none.ioKitType == nil)
    }
    #endif
}
