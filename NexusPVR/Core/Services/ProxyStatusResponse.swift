//
//  ProxyStatusResponse.swift
//  DispatcherPVR
//
//  Proxy status API response models
//  Compatible with Dispatcharr pre-0.24.0 and 0.24.0+
//

import Foundation

nonisolated struct ProxyStatusResponse: Decodable {
    let count: Int?
    let channels: [ProxyChannelStatus]?
}

nonisolated struct ProxyChannelStatus: Decodable, Identifiable {
    var id: String { channelId ?? streamName ?? UUID().uuidString }

    let streamName: String?
    let channelId: String?
    let channelName: String?
    let streamId: Int?
    let url: String?
    let streamProfile: String?
    let owner: String?
    let bufferIndex: Int?
    let state: String
    let resolution: String?
    let videoCodec: String?
    let audioCodec: String?
    let audioChannels: String?
    let avgBitrate: String?
    let avgBitrateKbps: Double?
    let sourceFps: Double?
    let ffmpegSpeed: Double?
    let uptime: Double?
    let totalBytes: Int64?
    let healthy: Bool?
    let m3uProfileName: String?
    let m3uProfileId: Int?
    let clientCount: Int?
    let clients: [ProxyClientInfo]?

    var displayName: String {
        if let name = channelName, !name.isEmpty { return name }
        if let name = streamName, !name.isEmpty { return name }
        return channelId ?? "Unknown"
    }

    var profileLabel: String? {
        if let name = m3uProfileName, !name.isEmpty {
            let short = name
                .replacingOccurrences(of: "Default", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !short.isEmpty { return short }
        }
        if let id = m3uProfileId { return String(id) }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case streamName = "stream_name"
        case channelId = "channel_id"
        case channelName = "channel_name"
        case streamId = "stream_id"
        case url
        case streamProfile = "stream_profile"
        case owner
        case bufferIndex = "buffer_index"
        case state, resolution
        case videoCodec = "video_codec"
        case audioCodec = "audio_codec"
        case audioChannels = "audio_channels"
        case avgBitrate = "avg_bitrate"
        case avgBitrateKbps = "avg_bitrate_kbps"
        case sourceFps = "source_fps"
        case ffmpegSpeed = "ffmpeg_speed"
        case uptime
        case totalBytes = "total_bytes"
        case healthy
        case m3uProfileName = "m3u_profile_name"
        case m3uProfileId = "m3u_profile_id"
        case clientCount = "client_count"
        case clients
    }
}

nonisolated struct ProxyClientInfo: Decodable, Identifiable {
    var id: String { clientId ?? ipAddress + userAgent }

    let ipAddress: String
    let userAgent: String
    let clientId: String?
    let userId: String?
    let connectedSince: Double?
    let connectedAt: Double?

    var connectedTime: Double? { connectedAt ?? connectedSince }

    enum CodingKeys: String, CodingKey {
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
        case clientId = "client_id"
        case userId = "user_id"
        case connectedSince = "connected_since"
        case connectedAt = "connected_at"
    }
}
