//
//  TVRootExitAction.swift
//  NexusPVR
//
//  Decides what the tvOS root navigation does with a Siri Remote Back
//  (exit command) press. Kept platform-independent so it can be unit tested
//  from the iOS test target.
//

import Foundation

/// The action the tvOS root navigation takes for one Back press.
nonisolated enum TVRootExitAction: Equatable {
    /// Close the Settings option popup.
    case dismissSettingsPopup
    /// Close the Settings event log.
    case dismissEventLog
    /// Move focus from the content area back to the sidebar.
    case focusSidebar
    /// Consume the press without doing anything (a child view owns it).
    case ignore
    /// Leave the press unhandled so tvOS returns to the app launcher (#155).
    case exitToSystem

    /// Resolves the action for the current navigation state.
    ///
    /// Priority mirrors standard tvOS behaviour: dismiss overlays first, then
    /// step back inside the app, and only when there is nothing left to
    /// dismiss hand the press to the system so a single tap leaves the app.
    ///
    /// - Parameters:
    ///   - selectedTab: the tab currently shown in the content area.
    ///   - sidebarHasFocus: whether a sidebar item currently holds focus.
    ///   - settingsHasPopup: whether the Settings option popup is open.
    ///   - settingsShowingEventLog: whether the Settings event log is open.
    ///   - blocksSidebarExit: whether a child view asked the root to leave the
    ///     press alone (`AppState.tvosBlocksSidebarExitCommand`).
    static func resolve(
        selectedTab: Tab,
        sidebarHasFocus: Bool,
        settingsHasPopup: Bool,
        settingsShowingEventLog: Bool,
        blocksSidebarExit: Bool
    ) -> TVRootExitAction {
        if selectedTab == .settings {
            if settingsHasPopup { return .dismissSettingsPopup }
            if settingsShowingEventLog { return .dismissEventLog }
        } else if blocksSidebarExit {
            return .ignore
        }
        return sidebarHasFocus ? .exitToSystem : .focusSidebar
    }
}
