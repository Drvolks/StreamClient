# CLAUDE.md - StreamClient

## Project Overview

StreamClient is a native Apple streaming client for PVR/DVR servers. Supports iOS, iPadOS, tvOS, and macOS from a single codebase using SwiftUI.

### Variants
- **StreamClient - For NextPVR** (scheme: `NextPVR`) — targets NextPVR server
- **StreamClient** (scheme: `DispatcharrPVR`) — targets Dispatcharr server (Django REST API)

## Tech Stack

- **Platform**: iOS 16+ / macOS 15+ / tvOS 18+
- **Language**: Swift 6.0
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with @Observable
- **Minimum Deployment**: iOS 16.0
- **Package Manager**: Swift Package Manager
- **Video Playback**: MPV (libmpv) via Metal rendering
- **Networking**: URLSession with async/await
- **Data Sync**: iCloud Key-Value Store (NSUbiquitousKeyValueStore)

## Project Structure

```
NexusPVR/
├── NexusPVRApp.swift    # App entry point (@main)
├── ContentView.swift    # Main content view with server config check
├── Core/
│   ├── Models/
│   │   ├── Channel.swift          # Channel model (id, name, number, hasIcon)
│   │   ├── Program.swift          # EPG program model with computed airing/progress
│   │   ├── Recording.swift        # Recording model + RecordingStatus enum
│   │   ├── Session.swift          # API response models + ServerConfig
│   │   └── UserPreferences.swift  # User preferences + PlayerStats
│   ├── Services/
│   │   ├── NextPVRClient.swift    # Main API client with authentication
│   │   ├── ImageCache.swift       # In-memory image cache
│   │   └── MD5Hasher.swift        # MD5 hashing for authentication
│   └── Extensions/
│       └── Notification+Extensions.swift  # Notification names (preferencesDidSync, recordingsDidChange)
├── Design/
│   └── Theme.swift      # Colors, spacing, typography, corner radius, animation, platform-specific styles
├── Features/
│   ├── Guide/           # EPG grid view (GuideView, GuideViewModel, ProgramCell, ProgramDetailView, GuideScrollHelper)
│   ├── LiveTV/          # Live TV channel list (LiveTVView, LiveTVViewModel)
│   ├── Player/          # MPV video player (PlayerView containing MPVPlayerCore + MPVContainerView)
│   ├── Recordings/      # Recording management (RecordingsListView, RecordingsViewModel, RecordingRow, RecordingDetailView)
│   ├── Settings/        # App settings (SettingsView, ServerConfigView, KeywordsEditorView)
│   └── Topics/          # Keyword-based program discovery (TopicsView, TopicsViewModel, TopicProgramRow)
└── Navigation/
    ├── AppState.swift   # Global app state (Tab enum: guide, recordings, topics, settings)
    └── NavigationRouter.swift  # Platform-adaptive navigation (iOS, tvOS, macOS variants)
```

## Key Patterns

### Swift
All struct and enum are in their own swift file.

### Environment Objects
- `NextPVRClient` - API client, injected via `.environmentObject()`
- `AppState` - Global state for playback, navigation

### View Models
- Use `@MainActor` and `ObservableObject` for view models
- All view models follow this pattern: `GuideViewModel`, `LiveTVViewModel`, `RecordingsViewModel`, `TopicsViewModel`

### Platform Conditionals
Use `#if os(tvOS)` / `#if os(macOS)` for platform-specific code:
```swift
#if os(tvOS)
// tvOS-specific UI
#else
// iOS/macOS UI
#endif
```

### Theme System
All styling goes through `Theme.*`:
- **Colors**: `accent`, `accentSecondary`, `background`, `surface`, `surfaceElevated`, `surfaceHighlight`, `textPrimary`, `textSecondary`, `textTertiary`, `success`, `warning`, `error`, `recording`, `guideNowPlaying`, `guidePast`, `guideScheduled`
- **Spacing**: `spacingXS` (4), `spacingSM` (8), `spacingMD` (16), `spacingLG` (24), `spacingXL` (32)
- **Corner Radius**: `cornerRadiusSM` (8), `cornerRadiusMD` (12), `cornerRadiusLG` (20)
- **Animation**: `animationDuration` (0.25), `springAnimation`
- **Platform sizes**: `cellHeight`, `channelColumnWidth`, `hourColumnWidth`, `iconSize` (all differ per platform)
- **Typography**: Font extensions (`displayLarge`, `displayMedium`, `headline`, `subheadline`, `body`, `caption`, `footnote`) + tvOS-specific (`tvTitle`, `tvHeadline`, `tvBody`, `tvCaption`)
- **View Modifiers**: `CardStyle`, `AccentButtonStyle`, `SecondaryButtonStyle`

## NextPVR API

The app communicates with NextPVR server via JSON API:

### Authentication
- Endpoint: `session.initiate` → `session.login`
- Uses PIN-based auth with MD5 hashing: `md5(":" + md5(PIN) + ":" + salt)`
- Stores SID in session, auto-reauthenticates on 401 responses

### Key Endpoints (via NextPVRClient)

**Channels & EPG:**
- `getChannels()` - List all channels
- `getListings(channelId:)` - EPG data for a channel
- `getAllListings(for channels:)` - Batch fetch EPG data for multiple channels
- `channelIconURL(channelId:)` - Get channel icon URL

**Recordings:**
- `getAllRecordings()` - Returns 3-tuple: `(completed: [Recording], recording: [Recording], scheduled: [Recording])`
- `getRecordings(filter:)` - Get recordings with filter ("ready", "recording", "pending")
- `scheduleRecording(eventId:)` - Schedule a recording
- `cancelRecording(recordingId:)` - Cancel a scheduled or in-progress recording
- `setRecordingPosition(recordingId:, positionSeconds:)` - Set resume position for playback

**Streaming:**
- `liveStreamURL(channelId:)` - Get stream URL for live TV
- `recordingStreamURL(recordingId:)` - Get stream URL for recording

**Configuration:**
- `updateConfig(_:)` - Update server configuration

### Response Models
All API responses use `Codable` structs in `Core/Models/`:
- `Channel` - Channel with id, name, number, hasIcon, streamURL
- `Program` - EPG program with computed properties (startDate, endDate, duration, isCurrentlyAiring, progress)
- `Recording` - Recording with playbackPosition; `RecordingStatus` enum (pending, recording, ready, failed, conflict, deleted)
- `SessionInitiateResponse`, `SessionLoginResponse`, `APIResponse` - Auth flow responses
- `ServerConfig` - Server connection settings (synced via iCloud)
- `UserPreferences` - Keywords and seek times (synced via iCloud)
- `PlayerStats` - MPV playback statistics (avgFps, avgBitrate, droppedFrames)

## tvOS Considerations

- **Focus Management**: Use `@FocusState`, `.focusSection()`, `.prefersDefaultFocus()`
- **Button Styles**: Custom `TVGuideButtonStyle`, `TVChannelButtonStyle`, `TVNavigationButtonStyle`
- **Input Components**: `TVTextField`, `TVNumberField` (alert-based input), `TVSettingsSection`
- **Remote Control**: MPV player handles play/pause, seek via Siri Remote
- **Larger UI**: Theme provides larger sizes for tvOS (e.g., `cellHeight: 100` vs `60`, `iconSize: 80` vs `48`)

## Video Player (MPV)

All player code lives in `Features/Player/PlayerView.swift`:
- Uses libmpv compiled for each platform (`import Libmpv`)
- Metal-based rendering via `CAMetalLayer`
- `MPVPlayerCore` class - Core player logic (defined inside PlayerView.swift)
- `MPVContainerView` struct - Platform wrapper (NSViewRepresentable on macOS, UIViewRepresentable on iOS/tvOS)
- `PlayerView` - Main SwiftUI view wrapping the player
- Seek times configurable in settings (separate backward/forward)

## User Preferences

Stored in `UserPreferences` struct (Core/Models/UserPreferences.swift), synced via iCloud:
- `keywords` - Topic keywords for program matching
- `seekBackwardSeconds` - Default 10
- `seekForwardSeconds` - Default 30

Also defines `PlayerStats` struct for MPV playback statistics.

Server config stored separately in `ServerConfig` (Core/Models/Session.swift).

## XcodeBuildMCP Integration
**IMPORTANT**: This project uses XcodeBuildMCP for all Xcode operations.
## Build Commands
- **Build**: Use `mcp__xcodebuildmcp__build_sim_name_proj` for simulator builds
- **Test**: Use `mcp__xcodebuildmcp__test_sim_name_proj` for running tests
- **Clean**: Use `mcp__xcodebuildmcp__clean` before major rebuilds
- **Logs**: Use `mcp__xcodebuildmcp__capture_logs` to debug runtime issues

## Build Instructions

The project has two schemes:
- **NextPVR** — StreamClient - For NextPVR
- **Dispatcharr** — StreamClient

Never build after a change unless explicitly requested.

### Running the App

1. Open `NexusPVR.xcodeproj` in Xcode
2. Select scheme (NextPVR for StreamClient - For NextPVR, or DispatcharrPVR for StreamClient)
3. Select target (iOS, tvOS, or macOS)
4. Build and run (Cmd+R)

Note: MPV framework must be properly linked for video playback.

## Dependencies

- **XcodeGen**: Used to generate .xcodeproj from project.yml (if applicable)
- **libmpv**: Video playback framework (compiled for each platform)
- **Swift Package Manager**: Any additional packages via SPM

## Architecture Decisions

### MVVM + Environment Objects
- View models use `@MainActor` and `ObservableObject` for UI state
- `NextPVRClient` and `AppState` are injected via `.environmentObject()` for global access
- This pattern allows testing view models independently from SwiftUI views

### @Observable vs @ObservableObject
- Use `@ObservableObject` for view models that need Combine publishers
- Consider `@Observable` for simpler state management in SwiftUI views
- Current view models use `@ObservableObject` (GuideViewModel, LiveTVViewModel, etc.)

## Common Development Workflows

### Adding a New Feature
1. Create feature folder in `Features/` if needed
2. Add models in `Core/Models/`
3. Add API methods in `NextPVRClient.swift` if backend calls needed
4. Create ViewModel with `@MainActor @ObservableObject`
5. Create SwiftUI views
6. Add navigation entry in `NavigationRouter.swift`
7. Build and test on all platforms

### Adding a New API Endpoint
1. Add method to `NextPVRClient.swift` using async/await
2. Create response model in `Core/Models/Session.swift` if needed
3. Update view models to call the new method
4. Handle errors consistently with existing patterns

### Unit testing
- Unit tests for all ViewModels
- UI tests for critical user flows
- Use Swift Testing framework (@Test, #expect)
- Minimum 80% code coverage for business logic

#### DO NOT
- Write UITests during scaffolding phase
- Use deprecated APIs (UIKit when SwiftUI suffices)
- Create massive monolithic views
- Use force unwrapping (!) without justification
- Ignore Swift 6 concurrency warnings

### Debugging
- Use `#if DEBUG` for debug-only code (logging, test data)
- MPV player logs to console - useful for playback issues
- Enable network logging in Xcode to inspect API calls

## Coding Standards

### Swift Style
- Use Swift 6 strict concurrency
- Prefer `@Observable` over `ObservableObject`
- Use `async/await` for all async operations
- Follow Apple's Swift API Design Guidelines
- Use `guard` for early exits
- Prefer value types (structs) over reference types (classes)

### SwiftUI Patterns
- Extract views when they exceed 100 lines
- Use `@State` for local view state only
- Use `@Environment` for dependency injection
- Prefer `NavigationStack` over deprecated `NavigationView`
- Use `@Bindable` for bindings to @Observable objects

### Navigation Pattern
```swift
// Use NavigationStack with type-safe routing
enum Route: Hashable {
    case detail(Item)
    case settings
}

NavigationStack(path: $router.path) {
    ContentView()
        .navigationDestination(for: Route.self) { route in
            // Handle routing
        }
}
```

### Error handling
```swift
// Always use typed errors
enum AppError: LocalizedError {
    case networkError(underlying: Error)
    case validationError(message: String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error): return error.localizedDescription
        case .validationError(let msg): return msg
        }
    }
}
```
