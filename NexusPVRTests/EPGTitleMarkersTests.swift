//
//  EPGTitleMarkersTests.swift
//  NexusPVRTests
//

import Foundation
import Testing
@testable import NextPVR

struct EPGTitleMarkersTests {
    private func program(_ name: String, hoursFromNow start: Double = -0.5) -> Program {
        let startTime = Int(Date().addingTimeInterval(start * 3600).timeIntervalSince1970)
        return Program(id: 1, name: name, subtitle: nil, desc: nil, start: startTime, end: startTime + 3600, genres: nil, channelId: 1)
    }

    @Test("The ᴸᶦᵛᵉ marker is detected and stripped from the title")
    func liveMarker() {
        let p = program("Episode 28 ᴸᶦᵛᵉ")
        #expect(p.isLiveBroadcast)
        #expect(p.cleanName == "Episode 28")
    }

    @Test("Capital-letter variants of the marker count too")
    func liveVariants() {
        #expect(EPGTitleMarkers.isLive("Game Night ᴸᴵⱽᴱ"))
        #expect(EPGTitleMarkers.clean("Game Night ᴸᴵⱽᴱ") == "Game Night")
    }

    @Test("NEW and LIVE together are both stripped, wherever they sit")
    func bothMarkers() {
        #expect(EPGTitleMarkers.clean("ᴺᵉʷ Final ᴸᶦᵛᵉ") == "Final")
        #expect(EPGTitleMarkers.clean("Match ᴸᶦᵛᵉ\nᴺᵉʷ") == "Match")
    }

    @Test("Plain titles, and the word live itself, are left alone")
    func plainTitles() {
        #expect(!EPGTitleMarkers.isLive("Live at Five"))
        #expect(EPGTitleMarkers.clean("Live at Five") == "Live at Five")
    }

    @Test("The LIVE badge drops once the program has ended, like NEW")
    func badgeHidesAfterEnd() {
        #expect(program("Match ᴸᶦᵛᵉ").shouldShowLiveBadge)
        #expect(!program("Match ᴸᶦᵛᵉ", hoursFromNow: -3).shouldShowLiveBadge)
    }

    @Test("Recordings detect and strip the marker too")
    func recordings() {
        let r = Recording(id: 1, name: "Episode 28 ᴸᶦᵛᵉ")
        #expect(r.isLiveBroadcast)
        #expect(r.cleanName == "Episode 28")
    }
}
