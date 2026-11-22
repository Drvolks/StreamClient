//
//  RecordingsDurationCheckSettingTests.swift
//  NexusPVRTests
//
//  The duration check reads each completed recording's file, so it only
//  runs when Settings › Recordings › Verify Recording Durations is on, and
//  the preference is off for new and upgraded installs.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct RecordingsDurationCheckSettingTests {

    private func rec(id: Int) -> Recording {
        Recording(
            id: id, name: "Rec \(id)", subtitle: nil, desc: nil,
            startTime: 1_000 + id, duration: 3600, channel: "CH", channelId: 1,
            status: "ready", file: "rec\(id).ts", recurring: 0, recurringParent: nil,
            epgEventId: nil, size: nil, quality: nil, genres: nil,
            playbackPosition: nil, prePadding: nil, postPadding: nil,
            season: nil, episode: nil, seriesBannerURL: nil
        )
    }

    private func makeVM(verifies: Bool) -> RecordingsViewModel {
        RecordingsViewModel(
            client: NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false)),
            verifiesDurations: { verifies }
        )
    }

    @Test("Off: loading recordings starts no duration check")
    func disabledStartsNothing() {
        let vm = makeVM(verifies: false)
        vm.completedRecordings = (1...2_500).map(rec)
        vm.probeDurations()
        #expect(vm.probeTask == nil)
        #expect(vm.durationMismatches.isEmpty)
        #expect(vm.durationUnverifiable.isEmpty)
    }

    @Test("On: completed recordings are checked, and a reload replaces the running check")
    func enabledStartsOneCheck() {
        let vm = makeVM(verifies: true)
        vm.completedRecordings = [rec(id: 987_654_321)]
        vm.probeDurations()
        let first = vm.probeTask
        #expect(first != nil)
        vm.probeDurations()
        #expect(first?.isCancelled == true)
        vm.probeTask?.cancel()
    }

    @Test("The preference defaults to off, also for prefs saved before it existed")
    func preferenceDefaultsOff() throws {
        #expect(UserPreferences().verifyRecordingDurations == false)
        let legacy = Data(#"{"keywords":[],"seekBackwardSeconds":10,"seekForwardSeconds":30}"#.utf8)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        #expect(decoded.verifyRecordingDurations == false)
    }

    @Test("The preference survives an encode/decode round trip")
    func preferenceRoundTrip() throws {
        var prefs = UserPreferences()
        prefs.verifyRecordingDurations = true
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(UserPreferences.self, from: data).verifyRecordingDurations)
    }
}
