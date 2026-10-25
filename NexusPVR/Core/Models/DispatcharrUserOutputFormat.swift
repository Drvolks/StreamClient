//
//  DispatcharrUserOutputFormat.swift
//  DispatcherPVR
//
//  The per-user Output Format override in `GET /api/accounts/users/me/`
//  (`custom_properties.output_format`), read for Server default (#204).
//

import Foundation

nonisolated struct DispatcharrUserOutputFormat: Decodable, Sendable {
    /// nil when the user has no override.
    let outputFormat: String?

    enum CodingKeys: String, CodingKey {
        case customProperties = "custom_properties"
    }

    private struct CustomProperties: Decodable {
        let outputFormat: String?

        enum CodingKeys: String, CodingKey {
            case outputFormat = "output_format"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let properties = try? container.decodeIfPresent(CustomProperties.self, forKey: .customProperties)
        outputFormat = properties?.outputFormat
    }
}
