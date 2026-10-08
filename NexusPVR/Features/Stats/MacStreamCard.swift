//
//  MacStreamCard.swift
//  nextpvr-apple-client
//
//  One channel the server is streaming, on the macOS Status page (Midnight):
//  name and state, a grid of stream stats, the source switcher and the
//  connected clients.
//

#if os(macOS) && DISPATCHERPVR
import SwiftUI

struct MacStreamCard: View {
    let channel: ProxyChannelStatus
    var profileName: String?
    var streams: [ChannelStream] = []
    var activeStreamId: Int?
    var isSwitchingStream = false
    var accountNameLookup: ((Int) -> String?)?
    var onSelectStream: ((ChannelStream) -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 18, alignment: .topLeading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(channel.displayName)
                    .font(.archivo(17, .extraBold))
                    .textCase(.uppercase)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
                if let profileName {
                    Text(profileName)
                        .badgeLabel()
                        .foregroundStyle(MidnightPalette.accentSoft)
                        .background(MidnightPalette.barSoft)
                }
                Spacer()
                MacStateChip(state: channel.state)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                stats
            }

            if let onSelectStream, !streams.isEmpty {
                StreamSelectorView(
                    streams: streams,
                    activeStreamId: activeStreamId,
                    isSwitching: isSwitchingStream,
                    accountNameLookup: accountNameLookup,
                    onSelect: onSelectStream
                )
            }

            if let clients = channel.clients, !clients.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Connected clients · \(channel.clientCount ?? clients.count)")
                        .midnightKicker(9.5)
                        .foregroundStyle(MidnightPalette.inkSoft)
                        .padding(.bottom, 6)
                    ForEach(clients) { client in
                        clientRow(client)
                    }
                }
            }
        }
        .padding(16)
        .background(MidnightPalette.cellRest)
        .overlay { Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1) }
    }

    @ViewBuilder
    private var stats: some View {
        if let resolution = channel.resolution { stat("Resolution", resolution) }
        stat("Codecs", channel.codecSummary)
        if let bitrate = channel.avgBitrate { stat("Bitrate", bitrate) }
        if let fps = channel.sourceFps { stat("FPS", String(format: "%.0f", fps)) }
        if let speed = channel.ffmpegSpeed { stat("FFmpeg speed", String(format: "%.2fx", speed)) }
        if let uptime = channel.uptime { stat("Uptime", ProxyChannelStatus.durationText(uptime)) }
        if let bytes = channel.totalBytes { stat("Total data", ProxyChannelStatus.dataText(bytes)) }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .midnightKicker(9)
                .foregroundStyle(MidnightPalette.inkFaint)
            Text(value)
                .midnightMeta(13.5, weight: .semibold)
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(1)
        }
    }

    private func clientRow(_ client: ProxyClientInfo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(client.ipAddress)
                .midnightMeta(12, weight: .semibold)
                .foregroundStyle(MidnightPalette.ink)
            Text(client.userAgent)
                .font(.archivo(11.5))
                .foregroundStyle(MidnightPalette.inkFaint)
                .lineLimit(1)
            Spacer()
            if let since = client.connectedTime {
                Text(ProxyChannelStatus.durationText(since))
                    .midnightMeta(12, weight: .semibold)
                    .foregroundStyle(MidnightPalette.accentSoft)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
    }
}
#endif
