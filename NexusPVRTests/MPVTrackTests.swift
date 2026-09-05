//
//  MPVTrackTests.swift
//  NexusPVRTests
//
//  Automatic avoidance of audio-description / hearing-impaired audio tracks.
//

import Testing
@testable import NextPVR

struct MPVTrackTests {

    private func audio(_ id: Int, lang: String? = "eng", selected: Bool = false,
                       visualImpaired: Bool = false, hearingImpaired: Bool = false) -> MPVTrack {
        MPVTrack(id: id, type: "audio", title: nil, lang: lang, codec: "mp2", channels: "2",
                 bitrate: nil, isSelected: selected,
                 isVisualImpaired: visualImpaired, isHearingImpaired: hearingImpaired)
    }

    @Test func switchesFromAudioDescriptionToRegularTrack() {
        let tracks = [
            MPVTrack(id: 1, type: "video", title: nil, lang: nil, codec: "h264", channels: nil, bitrate: nil, isSelected: true),
            audio(1, selected: true, visualImpaired: true),
            audio(2),
        ]
        #expect(MPVTrack.regularAudioTrackToSelect(in: tracks) == 2)
    }

    @Test func switchesFromHearingImpairedTrack() {
        let tracks = [audio(1, selected: true, hearingImpaired: true), audio(2)]
        #expect(MPVTrack.regularAudioTrackToSelect(in: tracks) == 2)
    }

    @Test func leavesRegularSelectionAlone() {
        let tracks = [audio(1, selected: true), audio(2, visualImpaired: true)]
        #expect(MPVTrack.regularAudioTrackToSelect(in: tracks) == nil)
    }

    @Test func keepsAccessibilityTrackWhenNothingElseExists() {
        let tracks = [audio(1, selected: true, visualImpaired: true), audio(2, hearingImpaired: true)]
        #expect(MPVTrack.regularAudioTrackToSelect(in: tracks) == nil)
    }

    @Test func nothingSelectedDoesNothing() {
        let tracks = [audio(1, visualImpaired: true), audio(2)]
        #expect(MPVTrack.regularAudioTrackToSelect(in: tracks) == nil)
    }

    @Test func prefersRegularTrackInSameLanguage() {
        let tracks = [
            audio(1, lang: "eng", selected: true, visualImpaired: true),
            audio(2, lang: "mri"),
            audio(3, lang: "eng"),
        ]
        #expect(MPVTrack.regularAudioTrackToSelect(in: tracks) == 3)
    }

    @Test func fallsBackToFirstRegularTrackWhenNoLanguageMatch() {
        let tracks = [
            audio(1, lang: "eng", selected: true, visualImpaired: true),
            audio(2, lang: "mri"),
            audio(3, lang: "fra"),
        ]
        #expect(MPVTrack.regularAudioTrackToSelect(in: tracks) == 2)
    }

    @Test func displayNameLabelsAccessibilityTracks() {
        #expect(audio(1, visualImpaired: true).displayName.hasSuffix("Audio Description"))
        #expect(audio(1, hearingImpaired: true).displayName.hasSuffix("Hearing Impaired"))
        #expect(!audio(1).displayName.contains("Audio Description"))
    }
}
