//
//  VODView.swift
//  DispatcherPVR
//
//  On Demand (#17): Dispatcharr's movies and series as a poster index, with
//  a page per title. Laid out like the recorded-series pages.
//

#if DISPATCHERPVR
import SwiftUI

struct VODView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VODContentView(client: client, appState: appState)
    }
}

private struct VODContentView: View {
    @ObservedObject var client: PVRClient
    @ObservedObject var appState: AppState
    @StateObject private var viewModel: VODBrowseViewModel
    /// Saved positions, for the Resume / Watched chips on movie posters.
    @State private var progress = VODProgressStore.load()
    @Environment(\.colorScheme) private var colorScheme
    #if os(tvOS)
    @Environment(\.requestSidebarFocus) private var requestSidebarFocus
    @FocusState private var focusedItemID: String?
    @State private var requestSearchKeyboard = false
    @State private var isChoosingCategory = false
    /// The poster to return focus to when a title's page closes.
    @State private var lastOpenedItemID: String?
    #endif

    init(client: PVRClient, appState: AppState) {
        self.client = client
        self.appState = appState
        self._viewModel = StateObject(wrappedValue: VODBrowseViewModel(provider: client, kind: appState.vodKind))
    }

    private var kind: VODKind { appState.vodKind }
    private var selectedItem: VODItem? { appState.selectedVODItem }

    var body: some View {
        #if os(macOS)
        page
        #else
        NavigationStack { page }
        #endif
    }

    private var page: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            macHeader
            #elseif os(tvOS)
            tvHeader
            #endif

            ZStack {
                // Stays alive under an open title, so closing it returns to
                // the same scroll position and the pages already loaded.
                index
                    .opacity(selectedItem == nil ? 1 : 0)
                    .allowsHitTesting(selectedItem == nil)
                    .accessibilityHidden(selectedItem != nil)
                    .disabled(selectedItem != nil)
                if let selectedItem {
                    VODDetailView(item: selectedItem, client: client, appState: appState)
                        .id(selectedItem.id)
                }
            }
        }
        .accessibilityIdentifier("vod-view")
        #if os(iOS)
        .sidebarMenuToolbar()
        .midnightNavigationTitle(selectedItem?.name ?? kind.title, kicker: navigationKicker)
        #endif
        .background(MidnightGradients.ground(colorScheme))
        .task(id: kind) {
            await viewModel.show(kind)
        }
        .onChange(of: viewModel.searchText) { _ in
            viewModel.searchTextChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vodProgressDidChange)) { _ in
            progress = VODProgressStore.load()
        }
        #if os(tvOS)
        .onChange(of: selectedItem) { oldItem, newItem in
            if let newItem {
                lastOpenedItemID = newItem.id
            } else if oldItem != nil {
                focusPoster(lastOpenedItemID)
            }
        }
        .confirmationDialog("Category", isPresented: $isChoosingCategory, titleVisibility: .visible) {
            Button("All categories") { selectCategory(nil) }
            ForEach(viewModel.categories) { category in
                Button(category.name) { selectCategory(category) }
            }
        }
        .onExitCommand {
            // Back closes the open title first, then leaves for the sidebar.
            if selectedItem != nil {
                appState.selectedVODItem = nil
            } else {
                requestSidebarFocus()
            }
        }
        .onMoveCommand { direction in
            if direction == .left { requestSidebarFocus() }
        }
        #endif
    }

    private var readout: String {
        let count = kind.countLabel(viewModel.totalCount)
        return viewModel.isFiltered ? "\(count) found" : count
    }

    private var backTitle: String { "All \(kind.title.lowercased())" }

    private func selectCategory(_ category: VODCategory?) {
        Task { await viewModel.selectCategory(category) }
    }

    private func open(_ item: VODItem) {
        appState.selectedVODItem = item
    }

    // MARK: - Headers

    #if os(iOS)
    private var navigationKicker: String {
        selectedItem == nil ? "On Demand · \(readout)" : kind.title
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private var macHeader: some View {
        if let selectedItem {
            MidnightPageHeader(kicker: kind.title, title: selectedItem.name, readout: selectedItem.metaLine) {
                Button {
                    appState.selectedVODItem = nil
                } label: {
                    Label(backTitle, systemImage: "chevron.left")
                }
                .buttonStyle(MidnightOutlineButtonStyle())
                .accessibilityIdentifier("vod-back-button")
            }
        } else {
            MidnightPageHeader(kicker: "On Demand", title: kind.title, readout: readout) {
                categoryPicker
                MidnightSearchField(
                    prompt: "Search \(kind.title.lowercased())",
                    text: $viewModel.searchText,
                    width: MacGuideHeaderMetrics.searchWidth,
                    height: MacGuideHeaderMetrics.searchHeight,
                    identifier: "vod-search-field"
                )
            }
        }
    }
    #endif

    #if !os(tvOS)
    @ViewBuilder
    private var categoryPicker: some View {
        if !viewModel.categories.isEmpty {
            MidnightPicker(
                title: "Category",
                selection: Binding(
                    get: { viewModel.selectedCategory },
                    set: { selectCategory($0) }
                ),
                options: [(label: "All categories", value: VODCategory?.none)]
                    + viewModel.categories.map { (label: $0.name, value: Optional($0)) }
            )
            .accessibilityIdentifier("vod-category-picker")
        }
    }
    #endif

    #if os(tvOS)
    @ViewBuilder
    private var tvHeader: some View {
        if let selectedItem {
            TVPageHeader(kicker: kind.title, title: selectedItem.name, readout: selectedItem.metaLine) {
                Button {
                    appState.selectedVODItem = nil
                } label: {
                    TVMidnightOutlineLabel(title: backTitle, systemImage: "chevron.left")
                }
                .buttonStyle(TVMidnightButtonStyle(focusScale: 1.04))
                .accessibilityIdentifier("vod-back-button")
            }
            .focusSection()
        } else {
            TVPageHeader(kicker: "On Demand", title: kind.title, readout: readout) {
                if !viewModel.categories.isEmpty {
                    Button {
                        isChoosingCategory = true
                    } label: {
                        TVMidnightOutlineLabel(
                            title: viewModel.selectedCategory?.name ?? "All categories",
                            systemImage: "line.3.horizontal.decrease"
                        )
                    }
                    .buttonStyle(TVMidnightButtonStyle(focusScale: 1.04))
                    .accessibilityIdentifier("vod-category-picker")
                }
                tvSearchButton
            }
            .focusSection()
        }
    }

    /// A focusable button shows the query; the text itself is entered through
    /// a hidden, non-focusable field that brings up the system keyboard.
    private var tvSearchButton: some View {
        Button {
            requestSearchKeyboard = true
        } label: {
            TVMidnightOutlineLabel(
                title: viewModel.searchText.isEmpty ? "Search" : viewModel.searchText,
                systemImage: "magnifyingglass"
            )
        }
        .buttonStyle(TVMidnightButtonStyle(focusScale: 1.04))
        .accessibilityIdentifier("vod-search-field")
        .background(
            TVKeyboardField(
                text: $viewModel.searchText,
                placeholder: "Search \(kind.title.lowercased())",
                requestFocus: $requestSearchKeyboard,
                onFocusChange: { focused in
                    if !focused { requestSearchKeyboard = false }
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private func focusPoster(_ id: String?) {
        guard selectedItem == nil else { return }
        let ids = viewModel.items.map(\.id)
        guard let target = id.flatMap({ ids.contains($0) ? $0 : nil }) ?? ids.first else { return }
        DispatchQueue.main.async {
            focusedItemID = target
        }
    }
    #endif

    // MARK: - Index

    @ViewBuilder
    private var index: some View {
        #if os(iOS)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MidnightSearchField(
                    prompt: "Search \(kind.title.lowercased())",
                    text: $viewModel.searchText,
                    height: 38,
                    identifier: "vod-search-field"
                )
                categoryPicker
            }
            .padding(.horizontal, 16)
            .padding(.top, Theme.spacingMD)
            indexContent
        }
        #else
        indexContent
        #endif
    }

    @ViewBuilder
    private var indexContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            messageView(symbol: nil, title: "Loading \(kind.title.lowercased())...", detail: nil)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            messageView(
                symbol: "exclamationmark.triangle",
                title: "Unable to load \(kind.title.lowercased())",
                detail: error,
                showsRetry: true
            )
        } else if viewModel.items.isEmpty {
            messageView(
                symbol: kind == .movies ? "film" : "rectangle.stack",
                title: "No \(kind.title.lowercased())",
                detail: viewModel.isFiltered
                    ? "Nothing matches the search or category."
                    : "The server has no \(kind.title.lowercased()) on demand."
            )
            .accessibilityIdentifier("vod-empty")
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridRowSpacing) {
                ForEach(viewModel.items) { item in
                    posterCard(item)
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(after: item) }
                        }
                }
            }
            .padding(.horizontal, gridHorizontalPadding)
            .padding(.top, gridTopPadding)

            if viewModel.isLoadingMore {
                ProgressView()
                    .padding(.vertical, Theme.spacingLG)
            }
            #if os(iOS)
            // Clears the floating bottom bar.
            Color.clear.frame(height: 120)
            #else
            Color.clear.frame(height: Theme.spacingLG)
            #endif
        }
        .accessibilityIdentifier("vod-grid")
        #if os(iOS)
        .refreshable {
            await viewModel.reload()
        }
        #endif
        #if os(tvOS)
        .onAppear {
            if focusedItemID == nil { focusPoster(lastOpenedItemID) }
        }
        .onChange(of: viewModel.items.map(\.id)) { _, ids in
            if !ids.contains(focusedItemID ?? "") { focusPoster(nil) }
        }
        #endif
    }

    #if os(tvOS)
    private let gridColumns = [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 36, alignment: .top)]
    private let gridRowSpacing: CGFloat = 40
    private let gridHorizontalPadding = Theme.spacingLG
    private let gridTopPadding = Theme.spacingLG
    #elseif os(macOS)
    private let gridColumns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 16, alignment: .top)]
    private let gridRowSpacing: CGFloat = 16
    private let gridHorizontalPadding: CGFloat = 20
    private let gridTopPadding: CGFloat = 18
    #else
    private let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14, alignment: .top)]
    private let gridRowSpacing: CGFloat = 14
    private let gridHorizontalPadding: CGFloat = 16
    private let gridTopPadding = Theme.spacingMD
    #endif

    @ViewBuilder
    private func posterCard(_ item: VODItem) -> some View {
        let posterURL = client.vodImageURL(item.logo?.preferredURLString)
        let symbol = item.kind == .movies ? "film" : "rectangle.stack"
        #if os(tvOS)
        Button {
            open(item)
        } label: {
            TVPosterCard(
                title: item.name,
                meta: item.metaLine,
                posterURL: posterURL,
                badge: badge(for: item),
                placeholderSymbol: symbol,
                identifier: "vod-card-\(item.name)"
            )
        }
        .buttonStyle(TVMidnightButtonStyle(focusScale: 1.04))
        .focused($focusedItemID, equals: item.id)
        #else
        PosterCard(
            title: item.name,
            meta: item.metaLine,
            posterURL: posterURL,
            badge: badge(for: item),
            placeholderSymbol: symbol,
            identifier: "vod-card-\(item.name)"
        ) {
            open(item)
        }
        #endif
    }

    /// "Resume" or "Watched" on a movie that has been started on this device.
    private func badge(for item: VODItem) -> String? {
        guard item.kind == .movies else { return nil }
        let saved = progress[item.uuid]
            ?? (client.config.isDemoMode ? DemoVODLibrary.seededProgress[item.uuid] : nil)
        switch saved?.watchState {
        case .resume: return "Resume"
        case .watched: return "Watched"
        case .new, nil: return nil
        }
    }

    // MARK: - States

    private func messageView(symbol: String?, title: String, detail: String?, showsRetry: Bool = false) -> some View {
        VStack(spacing: Theme.spacingMD) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.accent)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if showsRetry {
                Button("Try Again") {
                    Task { await viewModel.reload() }
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tvOSFocusableEmptyState()
    }
}
#endif
