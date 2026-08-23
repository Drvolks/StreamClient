//
//  CatchupContinuationTests.swift
//  NexusPVRTests
//
//  Coverage for keeping catch-up playback going past the live edge that
//  existed when the session was minted (#150).
//

import Testing
import Foundation
@testable import NextPVR

struct CatchupContinuationTests {
    private let hour: TimeInterval = 3600

    @Test("An airing programme resumes where playback stopped instead of ending")
    func airingProgrammeResumes() {
        let now = Date()
        // Started 70 minutes ago and runs for two hours. Playback began 35
        // minutes in, so the archive it was handed held 35 minutes — all of it
        // played by now, 35 minutes later.
        let start = now.addingTimeInterval(-70 * 60)
        let end = start.addingTimeInterval(2 * hour)

        let decision = CatchupContinuation.decide(
            programStart: start,
            programEnd: end,
            playedSeconds: 35 * 60,
            now: now
        )

        // Still 35 minutes of programme to fetch, not the end of the show.
        #expect(decision == .resume(start: now.addingTimeInterval(-35 * 60)))
    }

    @Test("Each continuation covers exactly the wall clock the previous one played")
    func continuationsLeaveNoGap() {
        let programStart = Date()
        let programEnd = programStart.addingTimeInterval(2 * hour)

        // Session 1 was minted 35 minutes in and played all 35 minutes.
        var played: Double = 35 * 60
        var now = programStart.addingTimeInterval(played * 2)

        guard case .resume(let firstResume) = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: played,
            now: now
        ) else {
            Issue.record("expected a resume")
            return
        }
        // Picks up exactly where the first archive stopped — no interval skipped.
        #expect(firstResume == programStart.addingTimeInterval(35 * 60))

        // That session holds firstResume → now, i.e. another 35 minutes, and
        // playing it takes 35 more minutes of wall clock.
        let secondLength = now.timeIntervalSince(firstResume)
        played += secondLength
        now = now.addingTimeInterval(secondLength)

        guard case .resume(let secondResume) = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: played,
            now: now
        ) else {
            Issue.record("expected a resume")
            return
        }
        // Continuous with the end of the second archive, and still the same
        // distance behind live as when playback started.
        #expect(secondResume == firstResume.addingTimeInterval(secondLength))
        #expect(now.timeIntervalSince(secondResume) == 35 * 60)
    }

    @Test("Playing the whole programme ends playback")
    func fullyPlayedProgrammeFinishes() {
        let programStart = Date().addingTimeInterval(-2 * hour)
        let programEnd = programStart.addingTimeInterval(hour)

        let decision = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: hour,
            now: Date()
        )

        #expect(decision == .finished)
    }

    @Test("A past programme's archive overshoot ends playback as before")
    func pastProgrammeKeepsExistingBehavior() {
        let now = Date()
        // Aired three hours ago; its archive runs from the programme start all
        // the way to the live edge, so EOF arrives long past the programme end.
        let programStart = now.addingTimeInterval(-3 * hour)
        let programEnd = programStart.addingTimeInterval(hour)

        let decision = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: 3 * hour,
            now: now
        )

        #expect(decision == .finished)
    }

    @Test("Waits rather than minting an archive with nothing in it")
    func waitsWhenLevelWithTheBroadcast() {
        let now = Date()
        let programStart = now.addingTimeInterval(-hour)
        let programEnd = programStart.addingTimeInterval(2 * hour)

        // Played to within 5 seconds of the broadcast.
        let decision = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: hour - 5,
            now: now
        )

        #expect(decision == .wait(seconds: CatchupContinuation.minimumLeadSeconds - 5))
    }

    @Test("Waiting long enough turns into a resume")
    func waitThenResume() {
        let programStart = Date().addingTimeInterval(-hour)
        let programEnd = programStart.addingTimeInterval(2 * hour)
        let played = hour - 5

        guard case .wait(let seconds) = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: played,
            now: programStart.addingTimeInterval(hour)
        ) else {
            Issue.record("expected a wait")
            return
        }

        let decision = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: played,
            now: programStart.addingTimeInterval(hour + seconds)
        )
        #expect(decision == .resume(start: programStart.addingTimeInterval(played)))
    }

    @Test("Exactly the minimum lead resumes without waiting")
    func minimumLeadResumes() {
        let now = Date()
        let programStart = now.addingTimeInterval(-hour)
        let programEnd = programStart.addingTimeInterval(2 * hour)
        let played = hour - CatchupContinuation.minimumLeadSeconds

        let decision = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: played,
            now: now
        )

        #expect(decision == .resume(start: programStart.addingTimeInterval(played)))
    }

    @Test("Negative played time is treated as the programme start")
    func negativePlayedClamps() {
        let now = Date()
        let programStart = now.addingTimeInterval(-hour)
        let programEnd = now.addingTimeInterval(hour)

        let decision = CatchupContinuation.decide(
            programStart: programStart,
            programEnd: programEnd,
            playedSeconds: -30,
            now: now
        )

        #expect(decision == .resume(start: programStart))
    }

    @Test("Sessions that play nothing are counted, and give up before looping")
    func givesUpOnRepeatedShortSessions() {
        #expect(CatchupContinuation.isShortSession(playedSeconds: 0))
        #expect(CatchupContinuation.isShortSession(
            playedSeconds: CatchupContinuation.minimumSessionProgressSeconds - 0.5
        ))
        #expect(!CatchupContinuation.isShortSession(playedSeconds: 30 * 60))

        #expect(!CatchupContinuation.shouldGiveUp(consecutiveShortSessions: 0))
        #expect(!CatchupContinuation.shouldGiveUp(
            consecutiveShortSessions: CatchupContinuation.maxConsecutiveShortSessions - 1
        ))
        #expect(CatchupContinuation.shouldGiveUp(
            consecutiveShortSessions: CatchupContinuation.maxConsecutiveShortSessions
        ))
    }

    @Test("A programme's catch-up duration growing while it plays never ends it early")
    func growingArchiveNeverEndsEarly() {
        // Regression for #150: walk a full airing programme the way playback
        // does — mint, play the archive dry, remint — and assert playback only
        // finishes once the whole programme has been played.
        let programStart = Date()
        let programEnd = programStart.addingTimeInterval(hour)

        var played: Double = 35 * 60           // archive at the first mint
        var now = programStart.addingTimeInterval(played)
        var reminted = 0

        while true {
            // Playing the current archive dry consumes that much wall clock.
            now = programStart.addingTimeInterval(played * 2)
            switch CatchupContinuation.decide(
                programStart: programStart,
                programEnd: programEnd,
                playedSeconds: played,
                now: now
            ) {
            case .finished:
                #expect(played >= hour)         // the whole programme, not the initial edge
                #expect(reminted > 0)
                return
            case .wait:
                Issue.record("a viewer 35 minutes behind live never has to wait")
                return
            case .resume(let start):
                #expect(start == programStart.addingTimeInterval(played))
                reminted += 1
                #expect(reminted < 10, "continuation is not converging")
                played += now.timeIntervalSince(start)
            }
        }
    }
}
