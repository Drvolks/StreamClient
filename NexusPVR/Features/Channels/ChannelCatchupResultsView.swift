//
//  ChannelCatchupResultsView.swift
//  NexusPVR
//
//  Search-style result list for one channel's catch-up archive.
//

import SwiftUI

#if DISPATCHERPVR
struct ChannelCatchupResultsView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState

    let channel: Channel
    let programs: [Program]

    @State private var selectedProgram: Program?
    @State private var refreshTrigger = UUID()

    var body: some View {
        resultsList
            .sheet(item: $selectedProgram) { program in
                ProgramDetailView(
                    program: program,
                    channel: channel,
                    onRecordingChanged: {
                        refreshTrigger = UUID()
                    }
                )
                .environmentObject(client)
                .environmentObject(appState)
            }
    }

    @ViewBuilder
    private var resultsList: some View {
        #if os(tvOS)
        ScrollView {
            LazyVStack(spacing: Theme.spacingMD) {
                ForEach(programs) { program in
                    SearchResultRowTV(
                        program: program,
                        channel: channel,
                        onRecordingChanged: {
                            refreshTrigger = UUID()
                        },
                        onShowDetails: {
                            selectedProgram = program
                        }
                    )
                    .environmentObject(client)
                    .environmentObject(appState)
                    .id("\(program.id)-\(refreshTrigger)")
                }
            }
            .padding()
        }
        #else
        List {
            ForEach(programs) { program in
                SearchResultRow(
                    program: program,
                    channel: channel,
                    onRecordingChanged: {
                        refreshTrigger = UUID()
                    },
                    onShowDetails: { _, _ in
                        selectedProgram = program
                    }
                )
                .contentShape(Rectangle())
                .listRowBackground(Theme.surface)
                .id("\(program.id)-\(refreshTrigger)")
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("channel-catchup-results")
        #endif
    }
}
#endif
