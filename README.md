# WTF Gym App Monorepo

Welcome to the **WTF Gym App** monorepo! This repository contains a paired ecosystem of Flutter applications and a supporting Node.js synchronization backend. They are designed to work together locally to deliver a high-fidelity coaching experience:

1. **Guru App (Member App)**: Used by member **"DK"** to onboard, schedule calls, chat with their trainer, join video sessions, and rate coaching sessions.
2. **Trainer App (Trainer App)**: Used by coach **"Aarav"** to review profiles, approve scheduled calls, chat with members, join video sessions, and submit session logs.
3. **Token Server**: A lightweight Node.js Express server facilitating local message synchronization, typing indicator broadcasts, call scheduling, and 100ms room token generation.

---

## 📽️ Project Walkthrough Video

A complete end-to-end screen recording walkthrough is included directly in the root of the repository:
* **File Location**: [Screen Recording 2026-05-22 at 4.25.55 PM.mov](file:///Users/shanacoder/Documents/wft_assignment_apps/Screen%20Recording%202026-05-22%20at%204.25.55%20PM.mov)
* **What it demonstrates**:
  * Side-by-side execution of Guru App and Trainer App.
  * Local synchronization and real-time chat with typing states and read receipts.
  * Flow of scheduling a call, approving it, and starting the pre-join camera/microphone check.
  * Real-time state synchronization of video feeds, camera flip, and audio/video mute transitions.
  * Completing calls and submitting post-session ratings and log records.

---

## 🏗️ Repository & Directory Layout

```
wtf_assignment_apps/
├─ Screen Recording 2026-05-22 at 4.25.55 PM.mov # End-to-end video demo
├─ README.md                                    # Root guide and setup instructions
├─ AI_LEDGER.md                                 # Full log of AI interactions and prompts
├─ ARCHITECTURE.md                              # Detailed architectural block diagram
├─ DECISIONS.md                                 # ADR (Architectural Decision Records)
├─ token_server/                                # Express Node.js Backend (port 3000)
│  ├─ server.js                                 # Main Server logic & in-memory DB
│  └─ package.json
├─ shared/                                      # Shared Dart Package
│  ├─ lib/
│  │  ├─ models/                                # User, Message, CallRequest, SessionLog, RoomMeta
│  │  ├─ services/                              # AuthService, ChatService, CallService, LogService
│  │  └─ utils/                                 # Styling, Themes, Developer overlay panel
│  └─ pubspec.yaml
├─ guru_app/                                    # Guru App (Flutter Project)
│  ├─ lib/main.dart
│  └─ pubspec.yaml
└─ trainer_app/                                 # Trainer App (Flutter Project)
   ├─ lib/main.dart
   └─ pubspec.yaml
```

---

## 🚀 Getting Started

Follow these steps to spin up the local ecosystem.

### Prerequisites
* Flutter SDK (3.22.x or later recommended)
* Node.js (v18+ recommended)
* Android Studio / Emulators or iOS Simulator for testing

---

### Step 1: Start the Local Sync Server
First, run the backend server to enable syncing between the two client apps:
```bash
cd token_server
npm install
npm run start
```
*The server will run on `http://localhost:3000`.*

---

### Step 2: Set Up and Run the Flutter Client Apps
In separate terminal windows, clean, configure, and launch the applications:

#### A. Run the Trainer App (Aarav - Coach)
```bash
cd trainer_app
flutter clean
flutter pub get
flutter run -d <your-device-id>
```

#### B. Run the Guru App (DK - Member)
```bash
cd guru_app
flutter clean
flutter pub get
flutter run -d <your-device-id>
```

---

## 🛠️ Key Architectural Features & Solutions

We resolved several key challenges during development to ensure robustness and ease of testing:

1. **Riverpod Scope Flattening**:
   Fixed a runtime `UnimplementedError: syncServiceProvider must be overridden` crash. We refactored provider scoping to watch `syncServiceProvider` eagerly in the root app widgets and start/stop the background poll loop dynamically on user auth changes.
2. **Real-time Chat Status Sync**:
   Fixed permanent "sending" message spinners by transitioning new messages from `'sending'` to `'sent'` on the backend. We updated the sync polling route `/api/sync` to filter based on `updatedAt` to ensure status modifications (e.g. read receipts) propagate instantly across devices.
3. **Double-Book Scheduling Validation**:
   Implemented robust overlapping duration checks (30-minute block boundaries) to prevent proposing overlapping sessions.
4. **100ms Video Calling & Cross-Client Sync**:
   * **Real 100ms (Android/iOS)**: Uses `hmssdk_flutter` to render native video feeds using `HMSVideoView`.
   * **Simulated Sync (macOS/Web/Desktop)**: Polling-based sync (500ms intervals) ensures that toggling mute, turning off video, or flipping the camera updates in real-time across both instances.
   * **Avatar Fallbacks**: Avoids black screens when video feeds are inactive or missing track bindings.
   * **Pre-Join Preservation**: Audio, video, and camera flip preferences configured in the preview screen are preserved and applied to the live call session on entry.
5. **Robust Workspace Relocation**:
   Fixed Gradle and Dart tool configuration issues caused by moving the parent directory from `wft gyme app` to `wft_assignment_apps` by cleaning and rebuilding all packages.

---

## 🧪 Running Automated Tests

A comprehensive suite of unit and widget tests is available and passes successfully.

### 1. Run Unit Tests (Shared Package)
Verifies models serialization, date logic, and session overlap validations:
```bash
cd shared
flutter test
```

### 2. Run Member App Smoke Tests
Verifies basic widget tree compilation and landing rendering layout:
```bash
cd guru_app
flutter test
```

### 3. Run Trainer App Smoke Tests
```bash
cd trainer_app
flutter test
```
