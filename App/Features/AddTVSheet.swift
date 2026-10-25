import SwiftUI
import TVKit

/// Pairs a TV by its IP address. Stands in for discovery until Apple grants the multicast
/// entitlement (docs/PLAN.md, section 2).
struct AddTVSheet: View {
    let store: RemoteStore
    let onClose: () -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var phase = Phase.editing
    @FocusState private var focused: Field?

    enum Phase: Equatable {
        case editing
        case connecting
        case awaitingPrompt
        case failed(String)
    }

    enum Field { case name, host }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var isBusy: Bool { phase == .connecting || phase == .awaitingPrompt }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Add a TV", onClose: close)
            VStack(spacing: 10) {
                field("Name", text: $name, prompt: "Living room", field: .name)
                field("IP address", text: $host, prompt: "192.168.1.20", field: .host)
                    .keyboardType(.decimalPad)
            }
            .disabled(isBusy)

            Text("On the TV, open Settings › Network › Wi‑Fi Connection › Advanced Wi‑Fi Settings to find its IP address. The phone and TV need to be on the same Wi‑Fi.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)

            Button(action: connect) {
                HStack(spacing: 10) {
                    if isBusy { ProgressView().tint(.white) }
                    Text(isBusy ? "Connecting" : "Connect")
                }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.blue.opacity(trimmedHost.isEmpty ? 0.4 : 1), in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .disabled(trimmedHost.isEmpty || isBusy)

            message
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .animation(Theme.settle, value: phase)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .onAppear { focused = .name }
    }

    @ViewBuilder
    private var message: some View {
        switch phase {
        case .editing, .connecting:
            EmptyView()
        case .awaitingPrompt:
            Label("Choose Allow on your TV", systemImage: "tv")
                .foregroundStyle(Theme.text)
                .transition(.opacity)
        case .failed(let reason):
            Text(reason)
                .foregroundStyle(Theme.muted)
                .transition(.opacity)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, field: Field) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .frame(width: 96, alignment: .leading)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(Theme.mutedNumber))
                .font(.system(size: 17))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(field == .name ? .words : .never)
                .focused($focused, equals: field)
                .submitLabel(field == .name ? .next : .go)
                .onSubmit { field == .name ? (focused = .host) : connect() }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func connect() {
        guard !trimmedHost.isEmpty, !isBusy else { return }
        focused = nil
        phase = .connecting
        let name = name.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await store.addTV(name: name.isEmpty ? "TV" : name, host: trimmedHost) {
                    phase = .awaitingPrompt
                }
                onClose()
            } catch TVError.pairingRejected {
                phase = .failed("The TV didn't allow this phone. Try again and choose Allow.")
            } catch {
                phase = .failed("Couldn't reach a TV at \(trimmedHost). Check it's on and on the same Wi‑Fi.")
            }
        }
    }

    private func close() {
        store.cancelPairing()
        onClose()
    }
}
