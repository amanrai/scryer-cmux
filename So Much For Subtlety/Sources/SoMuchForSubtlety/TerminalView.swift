import SwiftUI
import AppKit
import ScryerRender

/// Displays a (persistent) terminal controller: a slim header plus the controller's
/// owned Metal view. Creates/tears down nothing — the controller lives in the store,
/// so this view can come and go (sidebar toggle, pane switch) without reconnecting.
struct TerminalHostView: View {
    let controller: TerminalController
    let fallbackTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TerminalSurface(view: controller.metalView)
                .background(Color(hex: "#222B36") ?? .black)
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
/// Because the same NSView instance is returned, layout changes just move it.
private struct TerminalSurface: NSViewRepresentable {
    let view: TerminalMetalView

    func makeNSView(context: Context) -> TerminalMetalView { view }
    func updateNSView(_ nsView: TerminalMetalView, context: Context) {}
}
