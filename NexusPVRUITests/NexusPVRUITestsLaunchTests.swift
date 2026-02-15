//
//  NexusPVRUITestsLaunchTests.swift
//  NexusPVRUITests
//
//  Created by drvolks on 2026-02-02.
//

import XCTest

final class NexusPVRUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        throw XCTSkip("Launch screenshot test — run manually")
    }
}
