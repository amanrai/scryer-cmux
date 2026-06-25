import SwiftUI
import ScryerCore

/// Core piece 1: select a backend (PTY machine) registered with the gateway.
struct BackendPickerView: View {
    @Environment(AppModel.self) private var model

    private var selectable: [BackendMachine] { model.backends.filter(\.isSelectable) }
    private var others: [BackendMachine] { model.backends.filter { !$0.isSelectable } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.phase == .loadingBackends && model.backends.isEmpty {
                loading
            } else if model.backends.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !selectable.isEmpty {
                            sectionLabel("ONLINE")
                            ForEach(selectable) { backend in
                                BackendRow(backend: backend) { model.select(backend) }
                            }
                        }
                        if !others.isEmpty {
                            sectionLabel("UNAVAILABLE")
                            ForEach(others) { backend in
                                BackendRow(backend: backend, disabled: true) {}
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Machines").font(.system(size: 17, weight: .semibold))
                if let endpoint = model.endpoint {
                    Text(endpoint.displayHost)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Change gateway") { model.disconnect() }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.25))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Discovering machines…").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("No machines registered").font(.system(size: 13, weight: .medium))
            if let error = model.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).multilineTextAlignment(.center)
            } else {
                Text("Start a PTY backend and register it with this gateway.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BackendRow: View {
    let backend: BackendMachine
    var disabled: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.label).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                if !disabled {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(disabled ? 0.12 : 0.3), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var subtitle: String {
        var parts = [backend.id]
        if let transport = backend.transport { parts.append(transport) }
        parts.append(backend.decodingStatusFallback().rawValue)
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch backend.decodingStatusFallback() {
        case .online: return .green
        case .stale: return .yellow
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}
