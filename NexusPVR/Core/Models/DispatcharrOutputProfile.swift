//
//  DispatcharrOutputProfile.swift
//  DispatcherPVR
//
//  A Dispatcharr Output Profile (#161): a post-delivery FFmpeg remux or
//  transcode step the server applies to a live stream for one client. Distinct
//  from a Stream Profile, which controls how Dispatcharr *acquires* the
//  provider stream. Listed by `GET /api/core/outputprofiles/`; requested on a
//  live URL with `?output_profile=<id>`.
//

import Foundation

nonisolated struct DispatcharrOutputProfile: Identifiable, Decodable, Sendable, Hashable {
    let id: Int
    let name: String
    /// Dispatcharr only honours `?output_profile=` for active profiles, so an
    /// inactive one must be treated as unavailable rather than sent.
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isActive = "is_active"
    }

    init(id: Int, name: String, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Profile #\(id)"
        // Older payloads may omit the flag; a listed profile is active by default.
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    /// Query parameter name Dispatcharr's live proxy reads.
    static let queryItemName = "output_profile"

    /// Appends `?output_profile=<id>` to a live stream URL, keeping every
    /// existing query item (a catch-up `session_id`, an XC `output=`) intact.
    /// Nil `profileId` — the Original / pass-through choice — returns the URL
    /// untouched, so the default produces exactly the pre-#161 URLs.
    static func applying(profileId: Int?, to url: URL) -> URL {
        guard let profileId,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == queryItemName }
        items.append(URLQueryItem(name: queryItemName, value: String(profileId)))
        components.queryItems = items
        return components.url ?? url
    }

    /// Outcome of matching the user's saved choice against what the connected
    /// server offers.
    enum Resolution: Equatable, Sendable {
        /// Original / pass-through: send no `output_profile` at all.
        case original
        /// Send `output_profile=<id>` for this active profile.
        case profile(DispatcharrOutputProfile)
        /// The saved id isn't an active profile on this server (deleted,
        /// deactivated, or the endpoint couldn't be read). Play the original
        /// stream and tell the user why.
        case unavailable(profileId: Int, notice: String)

        /// Id to put on the URL, nil for anything that plays the original.
        var profileId: Int? {
            if case .profile(let profile) = self { return profile.id }
            return nil
        }

        var notice: String? {
            if case .unavailable(_, let notice) = self { return notice }
            return nil
        }
    }

    /// Decides what to send for `selectedId`, given the active profiles the
    /// server currently reports (`available` is nil when the list couldn't be
    /// fetched — an older server, or an account without API access).
    static func resolve(selectedId: Int?, available: [DispatcharrOutputProfile]?) -> Resolution {
        guard let selectedId else { return .original }
        if let match = available?.first(where: { $0.id == selectedId && $0.isActive }) {
            return .profile(match)
        }
        let notice: String
        if available == nil {
            notice = "Couldn't read the server's output profiles — playing the original stream."
        } else {
            notice = "Output profile #\(selectedId) is no longer available on this server — "
                + "playing the original stream."
        }
        return .unavailable(profileId: selectedId, notice: notice)
    }
}
