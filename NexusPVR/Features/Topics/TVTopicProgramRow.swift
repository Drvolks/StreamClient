//
//  TVTopicProgramRow.swift
//  nextpvr-apple-client
//
//  A program matching a topic, in the tvOS Topics list (Midnight). Select
//  records it (or cancels the recording); once it has ended, or when
//  recording features are hidden, select opens its details instead. Holding
//  select offers Details. The row's face is TVTopicProgramRowLabel.
//

#if os(tvOS)
import SwiftUI

struct TVTopicProgramRow: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState

    let program: Program
    let channel: Channel
    var onRecordingChanged: (() -> Void)?
    let onShowDetails: () -> Void

    @StateObject private var vm: TopicProgramRowViewModel

    init(
        program: Program,
        channel: Channel,
        onRecordingChanged: (() -> Void)? = nil,
        onShowDetails: @escaping () -> Void
    ) {
        self.program = program
        self.channel = channel
        self.onRecordingChanged = onRecordingChanged
        self.onShowDetails = onShowDetails
        _vm = StateObject(wrappedValue: TopicProgramRowViewModel(program: program, channel: channel))
    }

    private var selectRecords: Bool {
        appState.showsRecordings && !program.hasEnded
    }

    var body: some View {
        Button {
            guard !vm.isProcessing else { return }
            if selectRecords {
                vm.toggleRecording(using: client, onChanged: onRecordingChanged)
            } else {
                onShowDetails()
            }
        } label: {
            TVTopicProgramRowLabel(
                program: program,
                channel: channel,
                isRecording: vm.isRecording,
                isScheduled: vm.isScheduled,
                isProcessing: vm.isProcessing,
                existingRecording: vm.existingRecording,
                earlierScheduled: vm.earlierScheduled,
                selectAction: selectAction
            )
        }
        .buttonStyle(TVMidnightButtonStyle())
        .contextMenu {
            Button {
                onShowDetails()
            } label: {
                Label("Details", systemImage: "info.circle")
            }
        }
        .accessibilityIdentifier("topic-program-\(program.id)")
        .task {
            if appState.showsRecordings {
                await vm.checkIfScheduled(using: client)
            }
        }
    }

    /// What select does, shown on the focused row.
    private var selectAction: String {
        guard selectRecords else { return "Details" }
        return vm.isScheduled || vm.isRecording ? "Cancel recording" : "Record"
    }
}
#endif
