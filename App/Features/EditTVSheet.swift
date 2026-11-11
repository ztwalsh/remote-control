import SwiftUI

/// Picks where a TV is: one tap on a common room, or type any name.
/// Used when adding a TV and when editing one, so the app shows "Living room", not LG's model name.
struct RoomPicker: View {
    @Binding var name: String
    var onSubmit: () -> Void = {}

    static let rooms = [
        "Living room", "Family room", "Bedroom", "Guest room", "Kitchen",
        "Office", "Basement", "Den", "Game room", "Kids' room",
    ]

    @FocusState private var typing: Bool
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Self.rooms, id: \.self) { room in
                    let isOn = name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(room) == .orderedSame
                    Button {
                        typing = false
                        name = room
                    } label: {
                        Text(room)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(isOn ? Theme.accent : Theme.raised, in: Capsule())
                            .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.95))
                    .animation(.easeOut(duration: 0.18), value: isOn)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }

            HStack(spacing: 10) {
                IconView(.edit, size: 18)
                    .foregroundStyle(Theme.muted)
                TextField("Name", text: $name, prompt: Text("Or type a name").foregroundStyle(Theme.mutedNumber))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Renames a TV by where it is. Opened from Rename after holding a TV in Your TVs.
struct EditTVSheet: View {
    let store: RemoteStore
    let tvID: String
    let onClose: () -> Void

    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Where is this TV?", onClose: onClose)
            RoomPicker(name: $name, onSubmit: save)

            Button(action: save) {
                Text("Save")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent.opacity(trimmed.isEmpty ? 0.35 : 1), in: Capsule())
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .disabled(trimmed.isEmpty)

            Spacer(minLength: 0)
        }
        .sheetPadding()
        .onAppear { name = store.tvs.first { $0.id == tvID }?.name ?? "" }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        store.renameTV(tvID, to: trimmed)
        onClose()
    }
}
