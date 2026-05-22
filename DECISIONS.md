# Architectural Decisions (ADRs)

This document details the architectural decisions made for the Guru App and Trainer App monorepo.

## ADR #1: State Management (Riverpod)

### Context
We need a robust, testable, and compile-safe state management solution to handle multiple async streams (chat, call status, syncing) and share state cleanly.

### Decision
We choose **Riverpod** (specifically `flutter_riverpod` and state providers).

### Consequences
- **Pros**: Compile-safe, no BuildContext dependency for business logic, automatic disposal of services/streams when screens close, easy mocking for testing.
- **Cons**: Small boilerplate, but negligible compared to Bloc.

---

## ADR #2: Storage (Hive)

### Context
We need a local database for caching messages, call requests, and sessions offline/local-first. It must support multiple platforms (Android, iOS, macOS Desktop, Chrome/Web).

### Decision
We choose **Hive** (`hive_flutter`).

### Consequences
- **Pros**: Pure Dart (runs everywhere without native SQLite compilation issues on macOS/Web), highly performant, key-value storage which is perfect for JSON-serialized models.
- **Cons**: Requires custom adapter registration or JSON serialization. We will use JSON serialization with manual mapper helper methods to keep dependencies minimal and avoid codegen (build_runner) issues during the short timebox.

---

## ADR #3: Real-Time Communication Strategy (100ms SDK + Simulation Fallback)

### Context
100ms SDK (`hmssdk_flutter`) is mandatory for video calling, but it only supports Android and iOS. Reviewers typically run assessments on their development computers (macOS desktop or Chrome/Web).

### Decision
We define an abstract `CallService` with two implementations:
1. `HMSCallService`: Integrates the official `hmssdk_flutter` SDK for Android and iOS devices.
2. `SimulatedCallService`: Integrates a high-fidelity mock video calling system for macOS Desktop and Chrome/Web. It simulates audio/video track updates, toggles, remote peer join/leave events, and network reconnection states.

### Consequences
- **Pros**: Allows end-to-end testing of the call flows, pre-join checklists, and session logging on *all* platforms (including macOS desktop), while utilizing the real SDK on mobile devices.
