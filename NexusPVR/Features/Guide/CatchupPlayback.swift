//
//  CatchupPlayback.swift
//  nextpvr-apple-client
//
//  Starts catch-up playback of a past program (#119). Shared by the program
//  detail sheet and the macOS guide's detail bar.
//

#if DISPATCHERPVR
import Foundation

enum CatchupPlayback {
    enum Failure: LocalizedError {
        case unavailableForChannel

        var errorDescription: String? {
            switch self {
            case .unavailableForChannel: "Catch-up isn't available for this channel."
            }
        }
    }

    /// Mints a catch-up session for `program` and hands it to the player.
    /// Errors from the mint call (400/403/404/503) are thrown to the caller.
    static func start(
        program: Program,
        channel: Channel,
        client: PVRClient,
        appState: AppState,
        guideReturnTime: Date?
    ) async throws {
        guard let channelUuid = client.channelUUID(forChannelId: channel.id) else {
            throw Failure.unavailableForChannel
        }
        let service = CatchupService(client: client, baseURL: client.baseURL)
        let startISO8601 = ISO8601DateFormatter().string(from: program.startDate)
        let session = try await appState.preparingStream {
            try await service.startSession(channelUuid: channelUuid, startISO8601: startISO8601)
        }
        let url = try service.playbackURL(for: session)
        appState.playStream(
            url: url,
            title: "\(channel.name) - \(program.name)",
            channelId: channel.id,
            channelName: channel.name,
            catchupSessionId: session.sessionId,
            catchupProgram: CatchupProgramContext(
                channelUuid: channelUuid,
                programStart: program.startDate,
                programEnd: program.endDate
            ),
            catchupGuideReturnTime: guideReturnTime
        )
    }
}
#endif
