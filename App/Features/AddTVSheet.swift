import SwiftUI
import TVKit

/// Finds LG, Samsung and Vizio TVs on the Wi-Fi and pairs one. Pick a found TV (or type its IP address), say which
/// room it's in, and connect. The room is the name the app shows, not the maker's model name.
struct AddTVSheet: View {
    let store: RemoteStore
    let onClose: () -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var phase = Phase.editing
    @State private var search = Search.searching
    @State private var found: [DiscoveredTV] = []
    @State private var pickedID: String?
    /// Vizio shows a PIN on the TV; this waits for the person to type it.
    @State private var pin = ""
    @State private var pinRequest: CheckedContinuation<String?, Never>?
    @State private var pinWasAsked = false
    @FocusState private var focused: Field?

    enum Phase: Equatable {
        case editing
        case connecting
        case awaitingPrompt
        case enteringPIN
        case failed(String)
    }

    enum Search { case searching, done }

    enum Field { case name, host, pin }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var isBusy: Bool { phase == .connecting || phase == .awaitingPrompt || phase == .enteringPIN }
    private var trimmedPIN: String { pin.filter(\.isNumber) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Add a TV", onClose: close)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nearby
                    field("IP address", text: $host, prompt: "192.168.1.20", field: .host)
                        .keyboardType(.decimalPad)
                        .disabled(isBusy)

                    if found.isEmpty && search == .done {
                        Text("Or type its IP address. LG: Settings › Network › Wi‑Fi Connection › Advanced Wi‑Fi Settings. Samsung: Settings › General › Network › Network Status › IP Settings.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }

                    Text("Where is it?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                    RoomPicker(name: $name)
                        .disabled(isBusy)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if phase == .enteringPIN {
                pinEntry
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Button(action: connect) {
                    HStack(spacing: 10) {
                        if isBusy { ProgressView().tint(Theme.onAccent) }
                        Text(isBusy ? "Connecting" : "Connect")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent.opacity(trimmedHost.isEmpty ? 0.35 : 1), in: Capsule())
                    .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .disabled(trimmedHost.isEmpty || isBusy)
            }

            message
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .animation(Theme.settle, value: phase)
        }
        .sheetPadding()
        .padding(.bottom, 12)
        .task { await runSearch() }
        .onChange(of: host) { _, newHost in
            // Editing the address by hand un-picks the found TV.
            if let picked = found.first(where: { $0.id == pickedID }), picked.host != newHost { pickedID = nil }
        }
    }

    // MARK: - Found TVs

    @ViewBuilder
    private var nearby: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("On your Wi‑Fi")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if search == .searching {
                    ProgressView().controlSize(.small).tint(Theme.muted)
                } else {
                    Button("Search again") { Task { await runSearch() } }
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                        .disabled(isBusy)
                }
            }

            if found.isEmpty {
                Text(search == .searching ? "Looking for TVs…" : "No TVs found. Check the TV is on and on the same Wi‑Fi as this phone.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(found) { tv in
                    ChoiceRow(
                        icon: .tv,
                        title: tv.name ?? "\(tv.brand.displayName) TV",
                        subtitle: [tv.model, tv.host].compactMap { $0 }.joined(separator: " · "),
                        isSelected: pickedID == tv.id,
                        action: { pick(tv) }
                    ) {
                        RadioMark(isOn: pickedID == tv.id)
                    }
                    .disabled(isBusy)
                    .transition(.opacity)
                }
            }
        }
        .animation(Theme.settle, value: found)
    }

    private func runSearch() async {
        search = .searching
        let results = await store.discoverTVs()
        found = results
        search = .done
        // One TV: pick it, so Connect is one tap away. Otherwise wait for a choice.
        if results.count == 1, pickedID == nil, trimmedHost.isEmpty {
            pick(results[0])
        } else if results.isEmpty, trimmedHost.isEmpty {
            focused = .host
        }
    }

    private func pick(_ tv: DiscoveredTV) {
        focused = nil
        pickedID = tv.id
        host = tv.host
        if case .failed = phase { phase = .editing }
    }

    // MARK: - Pairing

    @ViewBuilder
    private var message: some View {
        switch phase {
        case .editing, .connecting:
            EmptyView()
        case .awaitingPrompt:
            IconLabel(title: "Choose Allow on your TV", icon: .tv)
                .foregroundStyle(Theme.text)
                .transition(.opacity)
        case .enteringPIN:
            IconLabel(title: "Type the PIN shown on your TV", icon: .tv)
                .foregroundStyle(Theme.text)
                .transition(.opacity)
        case .failed(let reason):
            Text(reason)
                .foregroundStyle(Theme.muted)
                .transition(.opacity)
        }
    }

    // MARK: - Vizio PIN

    private var pinEntry: some View {
        VStack(spacing: 12) {
            TextField("PIN", text: $pin, prompt: Text("PIN on the TV").foregroundStyle(Theme.mutedNumber))
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.text)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused, equals: .pin)
                .frame(height: 64)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: pin) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(4))
                    if digits != new { pin = digits }
                    if digits.count == 4 { submitPIN() }
                }

            Button(action: submitPIN) {
                Text("Pair")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent.opacity(trimmedPIN.count == 4 ? 1 : 0.35), in: Capsule())
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .disabled(trimmedPIN.count != 4)
        }
    }

    /// Called by the store while pairing a Vizio: shows the PIN field and waits.
    @MainActor
    private func askForPIN() async -> String? {
        pin = ""
        pinWasAsked = true
        withAnimation(Theme.settle) { phase = .enteringPIN }
        focused = .pin
        return await withCheckedContinuation { pinRequest = $0 }
    }

    private func submitPIN() {
        guard trimmedPIN.count == 4, let request = pinRequest else { return }
        pinRequest = nil
        focused = nil
        withAnimation(Theme.settle) { phase = .connecting }
        request.resume(returning: trimmedPIN)
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
                .onSubmit { connect() }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func connect() {
        guard !trimmedHost.isEmpty, !isBusy else { return }
        focused = nil
        phase = .connecting
        pinWasAsked = false
        let name = name.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let brand = found.first { $0.id == pickedID }?.brand
                try await store.addTV(
                    name: name.isEmpty ? "TV" : name, host: trimmedHost, brand: brand,
                    onPrompt: { if phase != .enteringPIN { phase = .awaitingPrompt } },
                    onPIN: { await askForPIN() }
                )
                onClose()
            } catch TVError.pairingRejected {
                phase = .failed(pinWasAsked
                    ? "That PIN didn't work. Try again with the one on the TV."
                    : "The TV didn't allow this phone. Try again and choose Allow.")
            } catch {
                phase = .failed("Couldn't reach a TV at \(trimmedHost). Check it's on and on the same Wi‑Fi.")
            }
        }
    }

    private func close() {
        pinRequest?.resume(returning: nil)
        pinRequest = nil
        store.cancelPairing()
        onClose()
    }
}
