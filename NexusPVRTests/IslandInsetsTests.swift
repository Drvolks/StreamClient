//
//  IslandInsetsTests.swift
//  NexusPVRTests
//
//  Tests for the Dynamic Island insets in both landscape directions (#176).
//

import Testing
import Foundation
@testable import NextPVR

struct IslandInsetsTests {

    @Test("A landscape iPhone insets only the island's side")
    func landscapePhone() {
        #expect(IslandInsets.resolve(isPhone: true, islandSide: .left, safeLeft: 62, safeRight: 62)
            == IslandInsets(left: 62, right: 0))
        #expect(IslandInsets.resolve(isPhone: true, islandSide: .right, safeLeft: 62, safeRight: 62)
            == IslandInsets(left: 0, right: 62))
    }

    @Test("Portrait keeps the window's insets")
    func portraitPhone() {
        #expect(IslandInsets.resolve(isPhone: true, islandSide: .none, safeLeft: 0, safeRight: 0) == IslandInsets())
    }

    @Test("iPad keeps the window's insets whichever way it is turned")
    func pad() {
        #expect(IslandInsets.resolve(isPhone: false, islandSide: .left, safeLeft: 4, safeRight: 6)
            == IslandInsets(left: 4, right: 6))
        #expect(IslandInsets.resolve(isPhone: false, islandSide: .right, safeLeft: 4, safeRight: 6)
            == IslandInsets(left: 4, right: 6))
    }
}
