//
//  MD5HasherTests.swift
//  NexusPVRTests
//
//  Tests for the MD5 helper used by NextPVR authentication.
//

import Testing
@testable import NextPVR

struct MD5HasherTests {

    @Test("empty string hashes to known MD5 constant")
    func hash_empty() {
        #expect(MD5Hasher.hash("") == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test("'password' hashes to known MD5 constant")
    func hash_password() {
        #expect(MD5Hasher.hash("password") == "5f4dcc3b5aa765d61d8327deb882cf99")
    }

    @Test("'hello' hashes to known MD5 constant")
    func hash_hello() {
        #expect(MD5Hasher.hash("hello") == "5d41402abc4b2a76b9719d911017c592")
    }

    @Test("hash is deterministic across calls")
    func hash_deterministic() {
        let a = MD5Hasher.hash("same-input")
        let b = MD5Hasher.hash("same-input")
        #expect(a == b)
    }

    @Test("hash output is lowercase 32-character hex string")
    func hash_format() {
        let hex = MD5Hasher.hash("anything")
        #expect(hex.count == 32)
        #expect(hex == hex.lowercased())
        #expect(hex.allSatisfy { $0.isHexDigit })
    }

    @Test("different inputs produce different hashes")
    func hash_distinct() {
        #expect(MD5Hasher.hash("a") != MD5Hasher.hash("b"))
    }
}
