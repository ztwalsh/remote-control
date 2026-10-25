import SwiftUI
import TVKit

/// Title and close button shared by every sheet.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            RoundIconButton(systemImage: "xmark", label: "Close", action: onClose)
        }
    }
}

/// Both pickers move the selection first, then close a moment later, so the change is visible.
@MainActor
private func pickThenClose(_ pick: () -> Void, close: @escaping () -> Void) {
    pick()
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(300))
        close()
    }
}

struct TVPickerSheet: View {
    let store: RemoteStore
    let onAdd: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Your TVs", onClose: onClose)
            VStack(spacing: 10) {
                ForEach(store.tvs) { tv in
                    ChoiceRow(
                        systemImage: "tv",
                        title: tv.name,
                        subtitle: store.status(for: tv),
                        isSelected: tv.id == store.selectedID,
                        action: { pickThenClose({ store.select(tv.id) }, close: onClose) }
                    ) {
                        RowPowerButton(isOn: tv.isOn, label: (tv.isOn ? "Turn off " : "Turn on ") + tv.name) {
                            store.setPower(!tv.isOn, for: tv.id)
                        }
                    }
                    .contextMenu {
                        if !store.isDemo {
                            Button("Remove \(tv.name)", systemImage: "trash", role: .destructive) {
                                store.removeTV(tv.id)
                            }
                        }
                    }
                }
            }
            PillButton(title: "Add a TV", systemImage: "plus", action: onAdd)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

struct SoundOutSheet: View {
    let store: RemoteStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Sound out", onClose: onClose)
            VStack(spacing: 10) {
                ForEach(SoundOutput.choices, id: \.self) { output in
                    let isSelected = store.selected.soundOutput == output
                    let pick = { pickThenClose({ store.setSoundOutput(output) }, close: onClose) }
                    ChoiceRow(
                        systemImage: output.systemImage,
                        title: output.displayName,
                        isSelected: isSelected,
                        action: pick
                    ) {
                        Button(action: pick) { RadioMark(isOn: isSelected) }
                            .buttonStyle(.plain)
                            .accessibilityHidden(true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
