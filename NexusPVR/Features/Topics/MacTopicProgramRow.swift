//
//  MacTopicProgramRow.swift
//  nextpvr-apple-client
//
//  A program matching a topic, in the macOS Topics list (Midnight): title
//  and badges, time and channel, description and any earlier-recording note;
//  on the right its recording state, then watch / record / info.
//

#if os(macOS)
import SwiftUI

struct MacTopicProgramRow: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState

    let program: Program
    let channel: Channel
    let onWatch: () -> Void
    var onRecordingChanged: (() -> Void)?
    let onShowDetails: (Int?, Recording?) -> Void

    @StateObject private var vm: TopicProgramRowViewModel
    @State private var isHovering = false

    init(
        program: Program,
        channel: Channel,
        onWatch: @escaping () -> Void,
        onRecordingChanged: (() -> Void)? = nil,
        onShowDetails: @escaping (Int?, Recording?) -> Void
    ) {
        self.program = program
        self.channel = channel
        self.onWatch = onWatch
        self.onRecordingChanged = onRecordingChanged
        self.onShowDetails = onShowDetails
        _vm = StateObject(wrappedValue: TopicProgramRowViewModel(program: program, channel: channel))
    }

    private var canRecord: Bool {
        appState.showsRecordings && !program.hasEnded
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            details
            Spacer(minLength: Theme.spacingSM)
            stateChip
                .frame(width: 104, alignment: .trailing)
            actionStrip
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(isHovering ? MidnightPalette.hoverTint : .clear)
        .overlay(alignment: .leading) {
            // Same cue as the guide: what is on now gets the accent bar.
            if program.isCurrentlyAiring {
                Rectangle().fill(MidnightPalette.accentSoft).frame(width: 4)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            onShowDetails(vm.existingRecordingId, vm.existingRecording)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("topic-program-\(program.id)")
        .task {
            if appState.showsRecordings {
                await vm.checkIfScheduled(using: client)
            }
        }
    }

    // MARK: Left

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(program.cleanName)
                    .font(.archivo(15.5, .extraBold))
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
                if program.shouldShowLiveBadge { LiveBadge() }
                if program.shouldShowNewBadge { NewBadge() }
            }

            Text("\(GuideCellTimeLabel.text(start: program.startDate, end: program.endDate, width: GuideCellTimeLabel.fullWidth)) · \(channel.name)")
                .midnightMeta(11)
                .foregroundStyle(MidnightPalette.inkSoft)
                .lineLimit(1)

            if let desc = description {
                Text(desc)
                    .font(.archivo(12.5))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            if let note = earlierRecordingNote {
                Text(note)
                    .midnightMeta(10.5)
                    .foregroundStyle(MidnightPalette.inkFaint)
            }
        }
    }

    private var description: String? {
        [program.subtitle, program.desc]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// Says when this program was already recorded, or is set to record at
    /// an earlier airing, so the user can skip this one.
    private var earlierRecordingNote: String? {
        if let existing = vm.existingRecording, let start = existing.startDate {
            return "Already recorded · \(start.formatted(date: .abbreviated, time: .omitted)) \(GuideCellTimeLabel.time(start))"
        }
        if let earlier = vm.earlierScheduled, let start = earlier.startDate {
            return "Recording an earlier airing · \(start.formatted(date: .abbreviated, time: .omitted)) \(GuideCellTimeLabel.time(start))"
        }
        return nil
    }

    // MARK: Right

    @ViewBuilder
    private var stateChip: some View {
        if vm.isRecording {
            chip("Recording", ink: .white, fill: Theme.recording)
        } else if vm.isScheduled {
            Text("Scheduled")
                .badgeLabel()
                .foregroundStyle(MidnightPalette.inkSoft)
                .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
                .accessibilityIdentifier("scheduled-indicator")
        } else if program.isCurrentlyAiring {
            MidnightFieldChip(text: "On now", size: 9)
        }
    }

    private func chip(_ text: String, ink: Color, fill: Color) -> some View {
        Text(text)
            .badgeLabel()
            .foregroundStyle(ink)
            .background(fill)
    }

    private var actionStrip: some View {
        HStack(spacing: 0) {
            MidnightActionCell(
                systemImage: "play.fill",
                help: "Watch",
                isEnabled: program.isCurrentlyAiring,
                isDimmed: !program.isCurrentlyAiring,
                action: onWatch
            )
            divider
            MidnightActionCell(
                systemImage: vm.isScheduled ? "record.circle.fill" : "record.circle",
                help: vm.isScheduled ? "Cancel recording" : "Record",
                isEnabled: canRecord && !vm.isProcessing,
                isDimmed: !canRecord,
                action: { vm.toggleRecording(using: client, onChanged: onRecordingChanged) }
            )
            divider
            MidnightActionCell(systemImage: "info.circle", help: "Info") {
                onShowDetails(vm.existingRecordingId, vm.existingRecording)
            }
        }
        .frame(width: 34 * 3 + 2, height: 34)
        .overlay { Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1) }
    }

    private var divider: some View {
        Rectangle().fill(MidnightPalette.lineSoft).frame(width: 1)
    }
}
#endif
