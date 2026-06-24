import SwiftUI

/// First screen: point the app at a gateway origin (the browser derives this from
/// the URL; a native app needs it explicit).
struct GatewayConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var hostDraft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("So Much For Subtlety")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Connect to an smux gateway")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("GATEWAY HOST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                TextField("machine.tailnet.ts.net:43223", text: $hostDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .focused($fieldFocused)
                    .onSubmit(connect)

                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 380)

            Button(action: connect) {
                Text("Connect")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .frame(width: 380)
            .disabled(hostDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            hostDraft = model.gatewayHostDraft
            fieldFocused = true
        }
    }

    private func connect() {
        model.connect(toGatewayInput: hostDraft)
    }
}
