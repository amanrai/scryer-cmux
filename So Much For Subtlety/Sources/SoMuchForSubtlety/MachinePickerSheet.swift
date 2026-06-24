import SwiftUI
import ScryerCore

/// Modal machine switcher: pick another online backend, or drop back to the gateway.
struct MachinePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let currentBackendId: String
    let onSelect: (BackendMachine) -> Void

    private var selectable: [BackendMachine] { model.backends.filter(\.isSelectable) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Switch Machine").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    if selectable.isEmpty {
                        Text("No machines online")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    ForEach(selectable) { backend in
                        Button {
                            onSelect(backend)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.machineName(for: backend.id) ?? backend.label).font(.system(size: 13, weight: .medium))
                                    Text(backend.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if backend.id == currentBackendId {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tint)
                                }
                            }
                            .padding(12)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button {
                    model.disconnect()
                    dismiss()
                } label: {
                    Label("Change gateway…", systemImage: "network").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                if let endpoint = model.endpoint {
                    Text(endpoint.displayHost).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 440, height: 400)
    }
}
