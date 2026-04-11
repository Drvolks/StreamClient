//
//  M3UAccountTests.swift
//  NexusPVRTests
//
//  Tests for M3UAccount's flexible Codable field handling.
//

import Testing
import Foundation
@testable import NextPVR

struct M3UAccountTests {

    // MARK: - id field flexibility

    @Test("Decodes integer id directly")
    func intId() throws {
        let json = #"{"id": 123, "name": "X"}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.id == 123)
    }

    @Test("Decodes numeric string id as Int")
    func stringIdParsed() throws {
        let json = #"{"id": "456", "name": "X"}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.id == 456)
    }

    @Test("Unparseable string id falls back to hash-based positive integer")
    func stringIdHashFallback() throws {
        let json = #"{"id": "abc", "name": "X"}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        // Fallback uses abs(hashValue); we can't predict the exact value but it must be
        // non-negative and stable within a run.
        #expect(acc.id >= 0)
    }

    // MARK: - String field defaults

    @Test("name defaults to 'Unknown' when missing")
    func nameDefault() throws {
        let json = #"{"id": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.name == "Unknown")
    }

    @Test("server_url defaults to empty string when missing")
    func serverUrlDefault() throws {
        let json = #"{"id": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.serverUrl == "")
    }

    @Test("status defaults to 'unknown' when missing")
    func statusDefault() throws {
        let json = #"{"id": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.status == "unknown")
    }

    @Test("Optional updated_at and account_type are nil when missing")
    func optionalsNil() throws {
        let json = #"{"id": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.updatedAt == nil)
        #expect(acc.accountType == nil)
    }

    @Test("Maps snake_case server_url to camelCase field")
    func snakeCaseMapping() throws {
        let json = #"{"id": 1, "server_url": "http://host"}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.serverUrl == "http://host")
    }

    // MARK: - isActive field flexibility

    @Test("isActive decodes as Bool true")
    func isActiveBoolTrue() throws {
        let json = #"{"id": 1, "is_active": true}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.isActive)
    }

    @Test("isActive decodes as Int 1 → true")
    func isActiveInt1() throws {
        let json = #"{"id": 1, "is_active": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.isActive)
    }

    @Test("isActive decodes as Int 0 → false")
    func isActiveInt0() throws {
        let json = #"{"id": 1, "is_active": 0}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.isActive == false)
    }

    @Test("isActive defaults to true when missing")
    func isActiveDefault() throws {
        let json = #"{"id": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.isActive)
    }

    // MARK: - locked field flexibility

    @Test("locked decodes as Bool false")
    func lockedBoolFalse() throws {
        let json = #"{"id": 1, "locked": false}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.locked == false)
    }

    @Test("locked decodes as Int 1 → true")
    func lockedInt1() throws {
        let json = #"{"id": 1, "locked": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.locked)
    }

    @Test("locked defaults to false when missing")
    func lockedDefault() throws {
        let json = #"{"id": 1}"#
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.locked == false)
    }

    @Test("All fields present round-trips cleanly")
    func fullDecode() throws {
        let json = """
        {
          "id": 42,
          "name": "Test Account",
          "server_url": "http://example.com",
          "status": "active",
          "updated_at": "2026-01-01",
          "is_active": 1,
          "locked": 0,
          "account_type": "xtreamcodes"
        }
        """
        let acc = try JSONDecoder().decode(M3UAccount.self, from: Data(json.utf8))
        #expect(acc.id == 42)
        #expect(acc.name == "Test Account")
        #expect(acc.serverUrl == "http://example.com")
        #expect(acc.status == "active")
        #expect(acc.updatedAt == "2026-01-01")
        #expect(acc.isActive)
        #expect(acc.locked == false)
        #expect(acc.accountType == "xtreamcodes")
    }
}
