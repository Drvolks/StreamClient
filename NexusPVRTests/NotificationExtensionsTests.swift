//
//  NotificationExtensionsTests.swift
//  NexusPVRTests
//
//  Tests for Notification.Name extension constants.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct NotificationExtensionsTests {

    @Test("preferencesDidSync has the correct raw name")
    func preferencesDidSyncName() {
        #expect(Notification.Name.preferencesDidSync.rawValue == "preferencesDidSync")
    }

    @Test("recordingsDidChange has the correct raw name")
    func recordingsDidChangeName() {
        #expect(Notification.Name.recordingsDidChange.rawValue == "recordingsDidChange")
    }

    @Test("preferencesDidSync and recordingsDidChange are different")
    func notificationsAreDifferent() {
        #expect(Notification.Name.preferencesDidSync != Notification.Name.recordingsDidChange)
    }
}
