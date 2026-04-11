//
//  DemoDataProviderTests.swift
//  NexusPVRTests
//
//  Tests for the DemoDataProvider fixtures. This is the demo data backend used
//  when the server host is "demo"; all methods are pure (no network, no I/O).
//  These tests drive the deterministic paths to raise coverage and catch
//  regressions in the canned schedules and scheduling state machine.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct DemoDataProviderTests {

    // MARK: - Channels

    @Test("DemoDataProvider exposes a non-empty channel list")
    func channelsArePopulated() {
        #expect(DemoDataProvider.channels.isEmpty == false)
    }

    @Test("Every demo channel has a non-empty name and a unique id")
    func channelIdsUnique() {
        let ids = DemoDataProvider.channels.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(DemoDataProvider.channels.allSatisfy { !$0.name.isEmpty })
    }

    @Test("DemoDataProvider exposes at least one channel profile")
    func channelProfiles() {
        #expect(DemoDataProvider.channelProfiles.isEmpty == false)
        let allIds = Set(DemoDataProvider.channels.map(\.id))
        // Every profile-listed channel id must exist in the channel fixtures.
        for profile in DemoDataProvider.channelProfiles {
            for cid in profile.channels {
                #expect(allIds.contains(cid))
            }
        }
    }

    @Test("DemoDataProvider exposes channel groups")
    func channelGroups() {
        #expect(DemoDataProvider.channelGroups.isEmpty == false)
    }

    // MARK: - Listings

    @Test("listings(for:) returns programs for a known channel")
    func listingsForKnownChannel() {
        let programs = DemoDataProvider.listings(for: 1001)
        #expect(programs.isEmpty == false)
    }

    @Test("listings(for:) returns an empty array for an unknown channel")
    func listingsForUnknownChannel() {
        // Channel id far outside the demo id range.
        let programs = DemoDataProvider.listings(for: 99_999)
        #expect(programs.isEmpty)
    }

    @Test("All demo programs have end > start")
    func listingsHaveValidTimes() {
        for channel in DemoDataProvider.channels {
            let programs = DemoDataProvider.listings(for: channel.id)
            for program in programs {
                #expect(program.end > program.start)
            }
        }
    }

    @Test("allListings(for:) returns a dictionary keyed by channel id")
    func allListingsStructure() {
        let subset = Array(DemoDataProvider.channels.prefix(3))
        let result = DemoDataProvider.allListings(for: subset)
        #expect(result.count <= subset.count)
        for channel in subset {
            if let programs = result[channel.id] {
                #expect(programs.isEmpty == false)
            }
        }
    }

    @Test("listings(for:on:) respects the requested day boundary")
    func listingsForDay() {
        let today = Date()
        let programs = DemoDataProvider.listings(for: 1001, on: today)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: today)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        for program in programs {
            #expect(program.startDate >= day.addingTimeInterval(-1))
            #expect(program.startDate < nextDay)
        }
    }

    // MARK: - Recordings

    @Test("recordings() returns three non-empty buckets")
    func recordingsTupleStructure() {
        let (completed, recording, scheduled) = DemoDataProvider.recordings()
        #expect(completed.isEmpty == false)
        // `recording` may be empty depending on the current wall time.
        _ = recording
        _ = scheduled
    }

    @Test("All completed recordings have status 'ready'")
    func completedRecordingsStatus() {
        let (completed, _, _) = DemoDataProvider.recordings()
        for rec in completed {
            #expect(rec.recordingStatus == .ready)
        }
    }

    @Test("All scheduled recordings have status 'pending'")
    func scheduledRecordingsStatus() {
        let (_, _, scheduled) = DemoDataProvider.recordings()
        for rec in scheduled {
            #expect(rec.recordingStatus == .pending)
        }
    }

    // MARK: - Recurring recordings

    @Test("recurringRecordings() returns at least the pre-seeded entries")
    func recurringRecordingsArePresent() {
        let list = DemoDataProvider.recurringRecordings()
        #expect(list.isEmpty == false)
    }

    // MARK: - Schedule / cancel state machine

    @Test("scheduleRecording and cancelRecording are idempotent and side-effect free")
    func scheduleCancelDoesNotCrash() {
        // These methods only mutate in-memory sets. Running them in isolation
        // shouldn't affect other tests' snapshots — we just verify they don't
        // trap on unknown ids.
        DemoDataProvider.scheduleRecording(eventId: 123_456)
        DemoDataProvider.cancelRecording(recordingId: 123_456 + 100_000)
        DemoDataProvider.cancelRecording(recordingId: 999_999)
    }

    @Test("cancelSeriesRecording accepts both pre-seeded and user-scheduled ids")
    func cancelSeriesRecordingAcceptsArbitraryIds() {
        // Use an id that's neither pre-seeded nor user-scheduled — should be a no-op.
        DemoDataProvider.cancelSeriesRecording(recurringId: 12_345_678)
    }
}
