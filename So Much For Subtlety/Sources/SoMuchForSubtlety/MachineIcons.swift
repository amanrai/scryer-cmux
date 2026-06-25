import SwiftUI

/// Selectable machine icons, mirroring `gateway-ui/src/machineIcons.ts` (FontAwesome
/// there → SF Symbols here).
struct MachineIconOption: Identifiable {
    enum Group: String, CaseIterable { case os = "OS", machine = "Machine" }
    let id: String
    let label: String
    let symbol: String
    let group: Group
}

enum MachineIcons {
    static let options: [MachineIconOption] = [
        .init(id: "os-macos", label: "macOS", symbol: "apple.logo", group: .os),
        .init(id: "os-linux", label: "Linux", symbol: "terminal", group: .os),
        .init(id: "os-windows", label: "Windows", symbol: "macwindow", group: .os),
        .init(id: "device-mini", label: "Mini", symbol: "cube", group: .machine),
        .init(id: "device-laptop", label: "Laptop", symbol: "laptopcomputer", group: .machine),
        .init(id: "device-desktop", label: "Desktop", symbol: "desktopcomputer", group: .machine),
        .init(id: "device-server", label: "Server", symbol: "server.rack", group: .machine),
        .init(id: "device-gpu", label: "GPU", symbol: "memorychip", group: .machine),
        .init(id: "device-cloud", label: "Cloud", symbol: "cloud", group: .machine),
    ]

    static func symbol(for id: String) -> String {
        options.first { $0.id == id }?.symbol ?? "circle"
    }
}

struct MachineIconGlyph: View {
    let id: String
    var selected = false
    var compact = false

    var body: some View {
        Image(systemName: MachineIcons.symbol(for: id))
            .font(.system(size: compact ? 10 : 12, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .frame(width: compact ? 20 : 26, height: compact ? 18 : 22)
            .background(selected ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: compact ? 4 : 5))
    }
}
