//
//  MacM3UAccountRow.swift
//  nextpvr-apple-client
//
//  An M3U account on the macOS Status page (Midnight): name, type and server
//  on the left, refresh state and when it was last updated on the right.
//

#if !os(tvOS) && DISPATCHERPVR
import SwiftUI

struct MacM3UAccountRow: View {
    let account: M3UAccount

    private var typeTag: String {
        account.accountType?.lowercased() == "xtream_codes" ? "XC" : "STD"
    }

    /// "3 hr. ago" from the account's ISO 8601 update time.
    private var updated: String? {
        guard let raw = account.updatedAt else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = precise.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(account.name)
                        .font(.archivo(15.5, .extraBold))
                        .foregroundStyle(MidnightPalette.ink)
                        .lineLimit(1)
                    Text(typeTag)
                        .badgeLabel()
                        .foregroundStyle(MidnightPalette.inkSoft)
                        .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
                }
                Text(account.serverUrl)
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: Theme.spacingSM)
            VStack(alignment: .trailing, spacing: 6) {
                MacStateChip(state: account.status)
                if let updated {
                    Text(updated)
                        .midnightMeta(10.5)
                        .foregroundStyle(MidnightPalette.inkFaint)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
    }
}
#endif
