# So Much For Subtlety — Native App Agent Notes

This folder contains the native SwiftUI app for **So Much For Subtlety**, targeting:

- macOS
- iPhone
- iPad

The Xcode project is intentionally configured for `iphoneos`, `iphonesimulator`, and `macosx`, with iPhone/iPad device families enabled.

## Platform-specific UI is expected

Do **not** treat this as one stretched universal layout. The app may and should have very specific UI for each form factor:

- **iPhone**: compact, single-column, touch-first flow. Favor stacked navigation, bottom/toolbar actions, quick inputs, and modal sheets.
- **iPad**: workspace/dashboard layout. Favor split views, sidebars, keyboard shortcuts, pointer support, Stage Manager resizing, and terminal-focused multitasking.
- **macOS**: desktop control surface. Favor multi-pane windows, menu commands, keyboard-first interactions, resizable sidebars, inspector panels, and native window behavior.

Use shared domain models and service clients, but allow separate SwiftUI view trees when the interaction model differs.

## Recommended structure

Prefer a shared core with explicit platform shells:

```text
So Much For Subtlety/
  App/
    So_Much_For_SubtletyApp.swift
    ContentView.swift
  Core/
    GatewayClient.swift
    TerminalSession.swift
    Models.swift
  Features/
    MachinePicker/
    Terminal/
    Workspaces/
    Interactions/
    ScryerPicker/
  Platform/
    Phone/
      PhoneRootView.swift
    Pad/
      PadRootView.swift
    Mac/
      MacRootView.swift
```

Platform routing can use SwiftUI environment and compile-time checks, for example:

```swift
#if os(macOS)
MacRootView()
#else
switch horizontalSizeClass {
case .compact:
    PhoneRootView()
default:
    PadRootView()
}
#endif
```

When behavior differs substantially, create separate views rather than burying everything in conditionals.

## Product direction

The native app should talk to the smux gateway and PTY backends rather than reimplement backend behavior locally:

```text
Native app
  -> smux gateway
    -> selected machine-local PTY backend
      -> terminal/session/comms/Scryer services
```

Initial implementation priority:

1. Gateway URL configuration and health check.
2. Machine registry picker via `/api/backends`.
3. Single terminal session over WebSocket.
4. Workspace state sync.
5. Quick inputs and command composer.
6. Interaction request and semantic update UI.
7. Native Scryer project/ticket picker.

## Validation

Use `xcodebuild` from this folder when possible:

```bash
xcodebuild -project "So Much For Subtlety.xcodeproj" -list
```

For code changes, validate at least one iOS simulator build and one macOS build when the local Xcode install supports those SDKs.
