//
//  VODCodingHelpers.swift
//  DispatcherPVR
//
//  Lenient decoding for VOD fields. Dispatcharr relays provider metadata, so
//  a number may arrive as "2008" and a rating as 7.5.
//

import Foundation

extension KeyedDecodingContainer {
    /// An integer sent as a number, a numeric string, or a decimal.
    nonisolated func vodInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return Int(trimmed) ?? Double(trimmed).map { Int($0) }
        }
        return nil
    }

    /// A non-empty string, also accepting a bare number.
    nonisolated func vodString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }
}
