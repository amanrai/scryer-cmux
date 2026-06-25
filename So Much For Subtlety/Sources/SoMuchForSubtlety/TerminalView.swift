import SwiftUI
import ScryerRender

/// Displays a (persistent) terminal controller: a slim header plus the controller's
/// owned Metal view. Creates/tears down nothing — the controller lives in the store,
/// so this view can come and go (sidebar toggle, pane switch) without reconnecting.
struct TerminalHostView: View {
    @Environment(AppModel.self) private var model
    let controller: TerminalController
    let fallbackTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TerminalSurface(view: controller.metalView)
                .background(Color(hex: model.theme.terminal.background.hex) ?? .black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(controller.title ?? fallbackTitle).font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.quaternary.opacity(0.18))
    }

    private var statusColor: Color {
        switch controller.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .closed: return .red
        }
    }
}

/// Reparents the controller's persistent `TerminalMetalView` into the SwiftUI tree.
/// The same view instance is returned, so layout changes just move it (no reconnect).
#if os(macOS)
import AppKit

private struct TerminalSurface: NSViewRepresentable {
    let view: TerminalMetalView
    func makeNSView(context: Context) -> TerminalMetalView { view }
    func updateNSView(_ nsView: TerminalMetalView, context: Context) {}
}
#else
import UIKit

private struct TerminalSurface: UIViewRepresentable {
    let view: TerminalMetalView
    func makeUIView(context: Context) -> TerminalMetalView { view }
    func updateUIView(_ uiView: TerminalMetalView, context: Context) {}
}
#endif
