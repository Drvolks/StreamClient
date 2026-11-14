//
//  EventLogView.swift
//  PVR Client
//
//  Network event log sub-page in Settings
//

import SwiftUI

struct EventLogView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showingCopied = false
    @State private var snapshot: [NetworkEvent] = []
    @State private var sessions: [UUID: PlaybackSession] = [:]
    @State private var filter: EventLogFilter = .all
    @State private var expandedEventIds: Set<UUID> = []
    #if os(tvOS)
    @State private var selectedSession: PlaybackSession?
    @State private var shareRequest: LogShareRequest?
    #endif
    private let eventLog: NetworkEventLog

    init(eventLog: NetworkEventLog = Dependencies.networkEventLog) {
        self.eventLog = eventLog
    }

    private func reload() {
        snapshot = eventLog.events
        sessions = eventLog.sessions
    }

    /// Newest first, narrowed by the filter.
    private var visibleEvents: [NetworkEvent] {
        snapshot.reversed().filter { filter.includes($0, session: session(for: $0)) }
    }

    private func session(for event: NetworkEvent) -> PlaybackSession? {
        event.sessionId.flatMap { sessions[$0] }
    }

    private func toggleExpanded(_ event: NetworkEvent) {
        if expandedEventIds.contains(event.id) {
            expandedEventIds.remove(event.id)
        } else {
            expandedEventIds.insert(event.id)
        }
    }

    var body: some View {
        #if os(tvOS)
        tvOSContent
        #else
        listContent
            .navigationTitle("Event Log")
        #endif
    }

    // MARK: - iOS / macOS

    #if !os(tvOS)
    private var listContent: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(EventLogFilter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("event-log-filter")
            }
            Section {
                if visibleEvents.isEmpty {
                    Text(filter.emptyMessage)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(visibleEvents) { event in
                        listRow(event)
                    }
                }
            }
        }
        .onAppear { reload() }
        #if os(macOS)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        #elseif os(iOS)
        .listStyle(.insetGrouped)
        .refreshable { reload() }
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                #if os(macOS)
                Button {
                    reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                #endif
                if !snapshot.isEmpty {
                    ShareLink(
                        item: EventLogExportFile.eventLog(events: snapshot, sessions: sessions),
                        preview: SharePreview("Event Log")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        copyLog()
                    } label: {
                        Label(showingCopied ? "Copied" : "Copy All", systemImage: showingCopied ? "checkmark" : "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        eventLog.clear()
                        reload()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listRow(_ event: NetworkEvent) -> some View {
        if let session = session(for: event) {
            NavigationLink {
                PlaybackSessionDetailView(session: session)
            } label: {
                EventLogRow(event: event, session: session)
            }
        } else {
            Button {
                toggleExpanded(event)
            } label: {
                EventLogRow(event: event, session: nil, isExpanded: expandedEventIds.contains(event.id))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func copyLog() {
        let text = eventLog.exportText()
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        showingCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopied = false
        }
    }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
    private var tvOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                TVSettingsSection(
                    title: "Event Log",
                    icon: "list.bullet.rectangle"
                ) {
                    LazyVStack(alignment: .leading, spacing: Theme.spacingSM) {
                        tvToolbar
                            .focusSection()

                        if visibleEvents.isEmpty {
                            Text(filter.emptyMessage)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.vertical, Theme.spacingMD)
                        } else {
                            ForEach(visibleEvents) { event in
                                tvRow(event)
                            }
                        }
                    }
                }
                .focusSection()
            }
            .padding(.vertical)
            .padding(.horizontal, 40)
        }
        .onAppear {
            appState.tvosBlocksSidebarExitCommand = true
            reload()
        }
        .onDisappear {
            appState.tvosBlocksSidebarExitCommand = false
        }
        .onExitCommand {
            dismiss()
        }
        .fullScreenCover(item: $selectedSession) { session in
            PlaybackSessionDetailView(session: session)
        }
        .fullScreenCover(item: $shareRequest) { request in
            TVLogShareView(request: request)
        }
    }

    /// Filter, Share and Clear.
    private var tvToolbar: some View {
        HStack(spacing: Theme.spacingMD) {
            ForEach(EventLogFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    tvChip(option.label, selected: filter == option)
                }
                .buttonStyle(TVEventLogActionButtonStyle())
            }
            Spacer()
            if !snapshot.isEmpty {
                Button {
                    shareRequest = LogShareRequest(
                        title: "Event Log",
                        fileName: EventLogExporter.fileName(),
                        text: EventLogExporter.text(events: snapshot, sessions: sessions)
                    )
                } label: {
                    tvChip("Share", systemImage: "qrcode", selected: false)
                }
                .buttonStyle(TVEventLogActionButtonStyle())

                Button {
                    eventLog.clear()
                    reload()
                } label: {
                    tvChip("Clear", selected: false, prominent: true)
                }
                .buttonStyle(TVEventLogActionButtonStyle())
            }
        }
    }

    private func tvChip(_ title: String, systemImage: String? = nil, selected: Bool, prominent: Bool = false) -> some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.tvScaled(size: 20, weight: .semibold))
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingSM)
        .background(
            selected ? Theme.accent
                : prominent ? Theme.guideNowPlaying.opacity(0.85)
                : Theme.surfaceElevated
        )
        .foregroundStyle(Theme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
    }

    /// Every row is a button, so the remote can scroll the list by moving
    /// focus; a playback session opens its log, a request shows its full
    /// error detail.
    private func tvRow(_ event: NetworkEvent) -> some View {
        let session = session(for: event)
        return Button {
            if let session {
                selectedSession = session
            } else {
                toggleExpanded(event)
            }
        } label: {
            EventLogRow(event: event, session: session, isExpanded: expandedEventIds.contains(event.id))
        }
        .buttonStyle(TVEventLogRowButtonStyle())
    }
    #endif
}

#if os(tvOS)
private struct TVEventLogActionButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                    .stroke(isFocused ? Theme.accent : Color.clear, lineWidth: isFocused ? 3 : 0)
            }
            .shadow(color: isFocused ? Theme.accent.opacity(0.22) : .clear, radius: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
    }
}
#endif
