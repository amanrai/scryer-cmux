import SwiftUI
import ScryerCore

/// Modal machine switcher: pick another online backend, or drop back to the gateway.
struct MachinePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let currentBackendId: String
    let onSelect: (BackendMachine) -> Void
    var kanbanerSelected = false
    var onKanbaner: () -> Void = {}

    private var selectable: [BackendMachine] { model.backends.filter(\.isSelectable) }

    var body: some View {
        List {
            Section {
                if selectable.isEmpty {
                    Text("No machines online").foregroundStyle(.secondary)
                }
                ForEach(selectable) { backend in
                    Button {
                        onSelect(backend)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.machineName(for: backend.id) ?? backend.label)
                                Text(backend.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !kanbanerSelected, backend.id == currentBackendId {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button {
                    dismiss()
                    onKanbaner()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.split.3x1")
                            .foregroundStyle(.tint)
                            .frame(width: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kanbaner")
                            Text("Project board").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if kanbanerSelected {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        } else {
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                Button(role: .destructive) {
                    model.disconnect()
                    dismiss()
                } label: {
                    Label("Change gateway…", systemImage: "network")
                }
            } footer: {
                if let endpoint = model.endpoint {
                    Text("Connected to \(endpoint.displayHost)").font(.caption.monospaced())
                }
            }
        }
        .modalList()
        .modalChrome("Select Backend", systemImage: "desktopcomputer", width: 440, height: 400)
    }
}
