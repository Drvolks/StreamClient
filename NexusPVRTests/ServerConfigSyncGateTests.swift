//
//  ServerConfigSyncGateTests.swift
//  NexusPVRTests
//
//  Tests for the iCloud server-config sync suppression gate.
//

import Testing
@testable import NextPVR

@MainActor
struct ServerConfigSyncGateTests {

    @Test func gateStartsOpenAndSuspendsWhileHeld() {
        #expect(ServerConfigSyncGate.isSuspended == false)

        ServerConfigSyncGate.acquire()
        #expect(ServerConfigSyncGate.isSuspended)

        ServerConfigSyncGate.release()
        #expect(ServerConfigSyncGate.isSuspended == false)
    }

    @Test func nestedHoldsRequireMatchingReleases() {
        ServerConfigSyncGate.acquire()
        ServerConfigSyncGate.acquire()

        ServerConfigSyncGate.release()
        #expect(ServerConfigSyncGate.isSuspended)

        ServerConfigSyncGate.release()
        #expect(ServerConfigSyncGate.isSuspended == false)
    }

    @Test func unbalancedReleaseCannotDriveTheGateNegative() {
        ServerConfigSyncGate.release()
        #expect(ServerConfigSyncGate.isSuspended == false)

        ServerConfigSyncGate.acquire()
        #expect(ServerConfigSyncGate.isSuspended)
        ServerConfigSyncGate.release()
        #expect(ServerConfigSyncGate.isSuspended == false)
    }
}
