import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// A bare SwiftPM executable launches as a background accessory (no bundle), so its
/// window never comes forward. Promote it to a regular foreground app at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

@main
struct SoMuchForSubtletyApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 480)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .disconnected:
                GatewayConnectView()
            case .loadingBackends, .picking:
                BackendPickerView()
            case .attached(let backend):
                AttachedView(backend: backend).id(backend.id)
            }
        }
        // Kanbaner board overlays the attached screen so the live terminal stays mounted
        // underneath (reached from the machine modal; PM is global, not backend-scoped).
        .overlay {
            if model.showingKanbaner, case .attached = model.phase {
                KanbanerView()
                    .environment(model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.showingKanbaner)
        .preferredColorScheme(model.theme.isDark ? .dark : .light)
        #if os(macOS)
        .background(WindowAccessor { window in
            // Extend content under the title bar so our top bar shares the row with the
            // traffic lights (cmux-style).
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        })
        #endif
    }
}

#if os(macOS)
/// Reaches the hosting `NSWindow` to apply native window configuration.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { configure(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let window = nsView.window { configure(window) } }
    }
}

/// Temporarily toggles background window dragging while an overlay is mounted. This keeps
/// detail-drawer resize handles from being interpreted as window drags on macOS.
struct WindowBackgroundDragSetter: NSViewRepresentable {
    let isMovable: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.isMovableByWindowBackground = isMovable }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.isMovableByWindowBackground = isMovable }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        DispatchQueue.main.async { nsView.window?.isMovableByWindowBackground = true }
    }
}
#endif
