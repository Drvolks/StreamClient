//
//  DispatcharrCoreSetting.swift
//  DispatcherPVR
//
//  One row of `GET /api/core/settings/`, read for the server's default live
//  output format (#204). Rows hold all kinds of values; only the stream
//  settings are decoded.
//

import Foundation

nonisolated struct DispatcharrCoreSetting: Decodable, Sendable {
    let key: String
    /// `stream_settings.default_output_format`; nil for other rows.
    let defaultOutputFormat: String?

    static let streamSettingsKey = "stream_settings"

    enum CodingKeys: String, CodingKey {
        case key, value
    }

    private struct StreamSettings: Decodable {
        let defaultOutputFormat: String?

        enum CodingKeys: String, CodingKey {
            case defaultOutputFormat = "default_output_format"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        if key == Self.streamSettingsKey {
            defaultOutputFormat = (try? container.decodeIfPresent(StreamSettings.self, forKey: .value))?
                .defaultOutputFormat
        } else {
            defaultOutputFormat = nil
        }
    }

    init(key: String, defaultOutputFormat: String?) {
        self.key = key
        self.defaultOutputFormat = defaultOutputFormat
    }
}
