//
//  DispatcharrSessionStoreTests.swift
//  NexusPVRTests
//
//  The saved Dispatcharr session is only reused for the same server and login.
//

import Foundation
import Testing
@testable import NextPVR

struct DispatcharrSessionStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "DispatcharrSessionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func config(host: String = "tv.example", username: String = "ada", password: String = "secret") -> ServerConfig {
        var config = ServerConfig(host: host, port: 9191, pin: "", useHTTPS: false)
        config.username = username
        config.password = password
        return config
    }

    @Test("A saved session comes back for the same server and login")
    func roundTrip() {
        let defaults = makeDefaults()
        DispatcharrSessionStore.save(access: "a", refresh: "r", for: config(), defaults: defaults)
        let loaded = DispatcharrSessionStore.load(for: config(), defaults: defaults)
        #expect(loaded?.access == "a")
        #expect(loaded?.refresh == "r")
    }

    @Test("Another server, user or password does not get the session")
    func keyedByCredentials() {
        let defaults = makeDefaults()
        DispatcharrSessionStore.save(access: "a", refresh: "r", for: config(), defaults: defaults)
        #expect(DispatcharrSessionStore.load(for: config(host: "other.example"), defaults: defaults) == nil)
        #expect(DispatcharrSessionStore.load(for: config(username: "bob"), defaults: defaults) == nil)
        #expect(DispatcharrSessionStore.load(for: config(password: "changed"), defaults: defaults) == nil)
    }

    @Test("The password is not stored in the key")
    func keyHidesPassword() {
        let key = DispatcharrSessionStore.credentialKey(for: config(password: "hunter2-very-secret"))
        #expect(!key.contains("hunter2"))
        #expect(key.count == 64)
    }

    @Test("Clearing removes the session")
    func clear() {
        let defaults = makeDefaults()
        DispatcharrSessionStore.save(access: "a", refresh: nil, for: config(), defaults: defaults)
        DispatcharrSessionStore.clear(defaults: defaults)
        #expect(DispatcharrSessionStore.load(for: config(), defaults: defaults) == nil)
    }
}
