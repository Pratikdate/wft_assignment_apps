# AI Ledger

This ledger documents the AI-assisted prompts, intents, outputs, and debugging sessions used during the development of the WTF Flutter Test assessment.

## AI Usage Entries

### Entry 1
- **Prompt #**: 1
- **Tool**: Antigravity (Gemini 3.5 Flash)
- **Intent**: Scaffolding the workspace, establishing shared schemas, local sync Express server, and abstract services.
- **Output/Changes**: Created monorepo structure, Node.js server setup, and Hive-based models in the shared package.
- **Commit Link**: `N/A` (Initial scaffold commit)

### Entry 2
- **Prompt #**: 2
- **Tool**: Antigravity (Gemini 3.5 Flash)
- **Intent**: Resolve syncServiceProvider UnimplementedError scoping bug by flattening ProviderScopes and moving initialization logic to the shared package.
- **Output/Changes**: Refactored `shared/lib/services/sync_service.dart`, `guru_app/lib/main.dart`, and `trainer_app/lib/main.dart`.
- **Commit Link**: `N/A`

### Entry 3
- **Prompt #**: 3
- **Tool**: Antigravity (Gemini 3.5 Flash)
- **Intent**: Fix 100ms Video Call Peer Connection Status Bug so that the remote participant is no longer stuck in the "(Waiting...)" status when a user joins the session.
- **Output/Changes**: Updated `shared/lib/services/call_service.dart` to request camera & microphone permissions dynamically, look up the existing remote peer on join to set initial participant name and audio/video track states, ignore local peer updates in the update listeners, and support reactive mute/unmute status tracking for both remote audio and video tracks.
- **Commit Link**: `N/A`

### Entry 4
- **Prompt #**: 4
- **Tool**: Antigravity (Gemini 3.5 Flash)
- **Intent**: Fix Chat Message Sync and Loading Bug so that messages resolve their status correctly from "sending" to "sent" on the server and synchronize correctly in real time between apps.
- **Output/Changes**: Updated `/api/chat` POST route in `token_server/server.js` to change message status from `'sending'` to `'sent'` on initial creation. Updated `/api/sync` GET route to query messages and session logs based on `updatedAt` timestamps instead of creation/ended timestamps to support status updates (like `'read'`) and prevent time skew issues. Added `updatedAt` field to system-generated chat messages.
- **Commit Link**: `N/A`

### Entry 5
- **Prompt #**: 5
- **Tool**: Antigravity (Gemini 3.5 Flash)
- **Intent**: Resolve issue where approved sessions do not show up in the Sessions screen.
- **Output/Changes**: Modified the Sessions screen in both `trainer_app` and `guru_app` to include a TabBar with "Upcoming Sessions" and "Session History" tabs. Upcoming sessions lists approved calls that do not have a completed session log, and provides a direct "Join Call" button to start the session.
- **Commit Link**: `N/A`

### Entry 6
- **Prompt #**: 6
- **Tool**: Antigravity (Gemini 3.5 Flash)
- **Intent**: Implement Simulated Call State Synchronization for non-Android clients running on macOS Desktop or Web.
- **Output/Changes**: Added simulated calling state synchronization (polling the token server every 500ms and posting local state) to `CallService` in `call_service.dart`. Synchronized camera flip and audio/video mute states across running desktop clients. Updated call screens (`guru_app` and `trainer_app`) to display front/back camera state strings dynamically and handle flip button styling.
- **Commit Link**: `N/A`

---

## Debugging Sessions with AI

### Debugging Entry 1
- **Date**: 2026-05-22
- **Issue**: Both `guru_app` and `trainer_app` failed to compile during `flutter test` due to missing color members (`Colors.black50` and `Colors.black70`) in their respective `call_screen.dart` files.
- **Resolution**: Replaced the invalid color constants with standard Dart colors (`Colors.black.withOpacity(0.5)` and `Colors.black.withOpacity(0.7)`).
- **Result**: Successfully resolved compilation errors. All client tests now compile and pass.

### Debugging Entry 2
- **Date**: 2026-05-22
- **Issue**: Default widget test templates (`test/widget_test.dart` in both client apps) failed because they referenced a non-existent `MyApp` widget.
- **Resolution**: Replaced the boilerplate tests with basic, lightweight smoke tests checking that a simple Material app containing the app label renders correctly.
- **Result**: Client test suites now run and pass.

### Debugging Entry 3
- **Date**: 2026-05-22
- **Issue**: Runtime crash when sending a message on both apps: `UnimplementedError: syncServiceProvider must be overridden` due to `chatServiceProvider` resolving in the outer `ProviderScope` where `syncServiceProvider` was not overridden.
- **Resolution**: Redefined `syncServiceProvider` in the `shared` package to initialize and reactively control the sync loop via `currentUserProvider`. Removed `MainAppLoader` and nested `ProviderScope`s from `guru_app` and `trainer_app` entrypoints, and watched `syncServiceProvider` eagerly in root app widgets.
- **Result**: Provider scopes are flattened, eliminating the UnimplementedError crash, and all unit tests pass.

### Debugging Entry 4
- **Date**: 2026-05-22
- **Issue**: Remote participant displayed as "(Waiting...)" on the video call screen even after both users join the 100ms call.
- **Resolution**: Updated `onJoin` in `CallService` to extract the first remote peer in the room and initialize `remoteParticipantName` and their video/audio track mute states. Added filters in `onPeerUpdate` and `onTrackUpdate` to ignore local peer updates and reactively handle remote audio/video mute transitions. Added runtime permission requests for camera and mic.
- **Result**: Remote participant transitions from "(Waiting...)" to "Joined" (displaying their name) as expected on join.

### Debugging Entry 5
- **Date**: 2026-05-22
- **Issue**: Messages stuck in "sending" status with permanent loading spinner in both client applications; messages not syncing between the two apps.
- **Resolution**:
  1. Updated the Node token server's `/api/chat` POST route to set `status = msg.status === 'sending' ? 'sent' : (msg.status || 'sent')` to transition new client-generated messages to 'sent'.
  2. Changed `/api/sync` message filtering from `createdAt` to `updatedAt` to ensure updates (like status changes to `'read'`) sync successfully and to fix time skew syncing bugs.
  3. Ensured system-generated chat messages in `server.js` also write `updatedAt`.
- **Result**: Messages transition from loading spinner to checkmark immediately on response from the server, and sync instantly to the peer application.

---

## Refactoring Log

### Refactoring Entry 1
- **Date**: 2026-05-22
- **Files Modified**: `shared/lib/services/sync_service.dart`, `guru_app/lib/main.dart`, `trainer_app/lib/main.dart`
- **Description**: Flattened Riverpod provider scopes across the monorepo to fix scoping lookup mismatch. Moved sync loop auto-start/stop logic to `syncServiceProvider` via `ref.listen` on `currentUserProvider`. Eagerly watched the provider in root widgets to ensure background sync runs without nested `ProviderScope`s.

### Refactoring Entry 2
- **Date**: 2026-05-22
- **Files Modified**: `trainer_app/lib/features/sessions/sessions_screen.dart`, `guru_app/lib/features/sessions/sessions_screen.dart`
- **Description**: Refactored the Sessions screen in both client apps to use a tabbed interface (Upcoming Sessions and Session History) to render approved scheduled calls that are not yet conducted, solving the issue of approved calls being completely invisible to the trainer and member. Added a direct button to start/join the call.

### Refactoring Entry 3
- **Date**: 2026-05-22
- **Files Modified**: `shared/lib/services/call_service.dart`, `guru_app/lib/features/calls/call_screen.dart`, `trainer_app/lib/features/calls/call_screen.dart`
- **Description**: Refactored `CallService` to support simulated calling state synchronization via HTTP polling to coordinate participant track changes (audio/video mute and camera flip) across desktop/simulator instances. Extended the upcoming call filter to allow day-of-call join access.

