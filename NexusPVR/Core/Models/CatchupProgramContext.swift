//
//  CatchupProgramContext.swift
//  nextpvr-apple-client
//
//  What the player needs to keep a catch-up session going as the programme
//  keeps airing (issue #150).
//

import Foundation

/// The programme a catch-up session was minted for, carried alongside the
/// session id so `PlayerView` can mint the next session in the chain when the
/// current archive runs out — see `CatchupContinuation`.
///
/// The channel identifier is the Dispatcharr UUID, the same one
/// `DispatcherClient.startCatchupSession` takes, because the numeric channel id
/// isn't accepted by the catch-up API.
nonisolated struct CatchupProgramContext: Equatable, Sendable {
    let channelUuid: String
    let programStart: Date
    let programEnd: Date

    init(channelUuid: String, programStart: Date, programEnd: Date) {
        self.channelUuid = channelUuid
        self.programStart = programStart
        self.programEnd = programEnd
    }
}
