//
//  DispatcharrProgram.swift
//  DispatcherPVR
//
//  Dispatcharr EPG program API model
//

import Foundation

nonisolated struct DispatcharrProgram: Decodable, Sendable {
    let id: Int
    let idWasSynthetic: Bool
    let startTime: String
    let endTime: String
    let title: String
    let subTitle: String?
    let description: String?
    let tvgId: String?
    let channel: Int?
    let epgDataId: Int?
    let season: Int?
    let episode: Int?
    let bannerURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case title
        case subTitle = "sub_title"
        case description
        case tvgId = "tvg_id"
        case channel
        case epgDataId = "epg_data_id"
        case season
        case episode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // id can be Int or String from Dispatcharr
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = intId
            idWasSynthetic = false
        } else if let stringId = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(stringId) {
            id = parsed
            idWasSynthetic = false
        } else {
            // Use hash of the string value as fallback
            let raw = try container.decode(String.self, forKey: .id)
            id = abs(raw.hashValue)
            idWasSynthetic = true
        }

        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        title = try container.decode(String.self, forKey: .title)
        subTitle = try container.decodeIfPresent(String.self, forKey: .subTitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        tvgId = try container.decodeIfPresent(String.self, forKey: .tvgId)

        // channel can also be Int or String
        if let intCh = try? container.decode(Int.self, forKey: .channel) {
            channel = intCh
        } else if let stringCh = try? container.decodeIfPresent(String.self, forKey: .channel),
                  let parsed = Int(stringCh) {
            channel = parsed
        } else {
            channel = nil
        }

        if let intEpgDataId = try? container.decode(Int.self, forKey: .epgDataId) {
            epgDataId = intEpgDataId
        } else if let stringEpgDataId = try? container.decodeIfPresent(String.self, forKey: .epgDataId),
                  let parsed = Int(stringEpgDataId) {
            epgDataId = parsed
        } else {
            epgDataId = nil
        }

        season = try container.decodeIfPresent(Int.self, forKey: .season)
        episode = try container.decodeIfPresent(Int.self, forKey: .episode)

        let dynamic = try decoder.container(keyedBy: DispatcharrDynamicCodingKey.self)
        bannerURL = decodeFirstDispatcharrImageField(
            from: dynamic,
            keys: [
                "banner", "banner_url", "series_banner", "series_image",
                "poster", "poster_url", "artwork", "artwork_url",
                "image", "image_url", "thumbnail", "thumbnail_url"
            ]
        )
    }

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()

    /// Fast path parser for the common Dispatcharr shape "yyyy-MM-ddTHH:mm:ssZ" / with fractional seconds.
    /// Avoids ISO8601DateFormatter for the typical case (~10x faster across hundreds of thousands of programs).
    private static func fastParseISO(_ s: String) -> Date? {
        let chars = Array(s.utf8)
        // Need at least "yyyy-MM-ddTHH:mm:ssZ" (20 chars)
        guard chars.count >= 20 else { return nil }
        @inline(__always) func d(_ i: Int) -> Int { Int(chars[i]) - 48 }
        @inline(__always) func twoDigits(_ i: Int) -> Int? {
            let a = d(i), b = d(i + 1)
            guard (0...9).contains(a), (0...9).contains(b) else { return nil }
            return a * 10 + b
        }
        guard chars[4] == 0x2D, chars[7] == 0x2D, chars[10] == 0x54,
              chars[13] == 0x3A, chars[16] == 0x3A else { return nil }
        let y = (d(0) * 1000) + (d(1) * 100) + (d(2) * 10) + d(3)
        guard let mo = twoDigits(5), let da = twoDigits(8),
              let h = twoDigits(11), let mi = twoDigits(14), let se = twoDigits(17) else {
            return nil
        }
        // Days from civil (Howard Hinnant)
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = mo + (mo > 2 ? -3 : 9)
        let doy = (153 * mp + 2) / 5 + da - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        let secs = TimeInterval(days) * 86400 + TimeInterval(h * 3600 + mi * 60 + se)
        return Date(timeIntervalSince1970: secs)
    }

    func toProgram(channelId: Int? = nil) -> Program? {
        let startDate = Self.fastParseISO(startTime)
            ?? Self.isoFractional.date(from: startTime)
            ?? Self.isoPlain.date(from: startTime)
        let endDate = Self.fastParseISO(endTime)
            ?? Self.isoFractional.date(from: endTime)
            ?? Self.isoPlain.date(from: endTime)
        guard let startDate, let endDate, endDate > startDate else {
            return nil
        }

        return Program(
            id: id,
            name: title,
            subtitle: subTitle,
            desc: description,
            start: Int(startDate.timeIntervalSince1970),
            end: Int(endDate.timeIntervalSince1970),
            genres: nil,
            channelId: channelId ?? channel,
            season: season,
            episode: episode,
            bannerURL: bannerURL
        )
    }

}

nonisolated enum DispatcharrEPGProgramMapper {
    static func map(
        programs: [DispatcharrProgram],
        tvgIdToChannelIds: [String: [Int]],
        epgDataIdToChannelIds: [Int: [Int]],
        sortByStart: Bool
    ) -> [Int: [Program]] {
        var mapped = [Int: [Program]]()

        for program in programs {
            let channelIds = resolvedChannelIds(
                for: program,
                tvgIdToChannelIds: tvgIdToChannelIds,
                epgDataIdToChannelIds: epgDataIdToChannelIds
            )
            guard !channelIds.isEmpty else { continue }

            for channelId in channelIds {
                guard let mappedProgram = program.toProgram(channelId: channelId) else { continue }
                mapped[channelId, default: []].append(mappedProgram)
            }
        }

        if sortByStart {
            for (channelId, programs) in mapped {
                mapped[channelId] = programs.sorted { $0.start < $1.start }
            }
        }

        return mapped
    }

    private static func resolvedChannelIds(
        for program: DispatcharrProgram,
        tvgIdToChannelIds: [String: [Int]],
        epgDataIdToChannelIds: [Int: [Int]]
    ) -> [Int] {
        if let directId = program.channel {
            return [directId]
        }

        if let epgDataId = program.epgDataId,
           let channelIds = epgDataIdToChannelIds[epgDataId],
           !channelIds.isEmpty {
            return channelIds
        }

        if let tvgId = program.tvgId,
           !tvgId.isEmpty,
           let channelIds = tvgIdToChannelIds[tvgId] {
            return channelIds
        }

        return []
    }
}

extension Array where Element: Equatable {
    mutating func appendIfMissing(_ element: Element) {
        if !contains(element) {
            append(element)
        }
    }
}
