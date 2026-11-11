import SwiftUI
import TVKit

/// Title and close button shared by every sheet.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            RoundIconButton(icon: .close, label: "Close", action: onClose)
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

/// The TVs, with power for each. Hold a TV to rename or remove it: the row lifts, the others dim,
/// and its power button turns into Rename and Remove icons.
struct TVPickerSheet: View {
    let store: RemoteStore
    let onAdd: () -> Void
    let onRename: (String) -> Void
    let onClose: () -> Void

    @AppStorage("appearance") private var appearance = Appearance.system
    /// The TV whose actions are showing.
    @State private var menuID: String?
    /// True after the first tap on Remove; the second tap removes.
    @State private var confirmingRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Your TVs", onClose: onClose)
            VStack(spacing: 10) {
                ForEach(store.tvs) { tv in
                    row(tv)
                        .opacity(menuID != nil && menuID != tv.id ? 0.3 : 1)
                }
            }
            .animation(Theme.settle, value: menuID)
            .animation(Theme.settle, value: confirmingRemove)

            PillButton(title: "Add a TV", icon: .plus, action: onAdd)
                .opacity(menuID == nil ? 1 : 0.3)
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                ThemeColorPicker()
                HStack {
                    Text("Theme")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    AppearanceSwitch(selection: $appearance)
                }
            }
            .opacity(menuID == nil ? 1 : 0.3)
            .padding(.bottom, 12)
        }
        .sheetPadding()
        // Tapping anywhere outside the actions closes them.
        .contentShape(Rectangle())
        .onTapGesture { closeMenu() }
        .sensoryFeedback(.impact(weight: .medium), trigger: menuID) { _, new in new != nil }
    }

    private func row(_ tv: TVState) -> some View {
        let isMenu = menuID == tv.id
        return ChoiceRow(
            icon: .tv,
            title: tv.name,
            subtitle: isMenu && confirmingRemove ? "Remove this TV?" : store.status(for: tv),
            isSelected: tv.id == store.selectedID,
            action: {
                // The finger lifting after a hold also lands here; keep the actions open.
                if menuID != nil {
                    if menuID != tv.id { closeMenu() }
                    return
                }
                pickThenClose({ store.select(tv.id) }, close: onClose)
            }
        ) {
            if isMenu {
                actions(for: tv)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                RowPowerButton(isOn: tv.isOn, label: (tv.isOn ? "Turn off " : "Turn on ") + tv.name) {
                    store.setPower(!tv.isOn, for: tv.id)
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .scaleEffect(isMenu ? 1.02 : 1)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                confirmingRemove = false
                menuID = tv.id
            }
        )
        .accessibilityAction(named: "Rename") { onRename(tv.id) }
    }

    /// Rename and Remove as icons, in place of the power button. Remove asks first:
    /// the row reads "Remove this TV?" with cancel and a red confirm.
    @ViewBuilder
    private func actions(for tv: TVState) -> some View {
        HStack(spacing: 8) {
            if confirmingRemove {
                RowIconButton(icon: .close, label: "Keep \(tv.name)") { confirmingRemove = false }
                RowIconButton(icon: .check, label: "Remove \(tv.name)", style: .danger) {
                    closeMenu()
                    store.removeTV(tv.id)
                }
            } else {
                RowIconButton(icon: .edit, label: "Rename \(tv.name)") {
                    closeMenu()
                    onRename(tv.id)
                }
                if !store.isDemo {
                    RowIconButton(icon: .trash, label: "Remove \(tv.name)", style: .dangerOutline) {
                        confirmingRemove = true
                    }
                }
            }
        }
    }

    private func closeMenu() {
        menuID = nil
        confirmingRemove = false
    }
}

/// A round icon button in a TV row's trailing slot. Adapts to the selected (reversed) row.
private struct RowIconButton: View {
    enum Style { case plain, dangerOutline, danger }

    let icon: Icon
    let label: String
    var style = Style.plain
    let action: () -> Void
    @Environment(\.isInverted) private var inverted

    private var fill: Color {
        switch style {
        case .danger: return Theme.danger
        case .plain, .dangerOutline: return inverted ? Theme.onAccent.opacity(0.14) : Theme.iconTile
        }
    }

    private var glyph: Color {
        switch style {
        case .danger: return .white
        case .dangerOutline: return Theme.danger
        case .plain: return inverted ? Theme.onAccent : Theme.text
        }
    }

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 20)
                .frame(width: 46, height: 46)
                .background(fill, in: Circle())
                .foregroundStyle(glyph)
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// System, light and dark as three icons in a pill; the chosen one sits on a sliding chip.
struct AppearanceSwitch: View {
    @Binding var selection: Appearance
    @Namespace private var chip

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Appearance.allCases) { option in
                let isOn = selection == option
                Button {
                    withAnimation(Theme.settle) { selection = option }
                } label: {
                    IconView(option.icon, size: 20)
                        .frame(width: 44, height: 36)
                        .foregroundStyle(isOn ? Theme.onAccent : Theme.muted)
                        .background {
                            if isOn {
                                Capsule().fill(Theme.accent).matchedGeometryEffect(id: "chip", in: chip)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.raised, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }
}

/// The selected TV's sound outputs. webOS can't list what a TV has, so this shows the outputs the TV
/// has actually used. Others can be tried from "Try another output"; one the TV refuses disappears.
struct SoundOutSheet: View {
    let store: RemoteStore
    let onClose: () -> Void

    @State private var showUntried = false
    @State private var trying: SoundOutput?
    @State private var refusedName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Sound out", onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.availableOutputs, id: \.self) { output in
                        outputRow(output) {
                            pickThenClose({ Task { await store.setSoundOutput(output) } }, close: onClose)
                        }
                    }

                    if let refusedName {
                        Text("This TV doesn't have \(refusedName).")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                            .transition(.opacity)
                    }

                    if !store.untriedOutputs.isEmpty {
                        Button {
                            withAnimation(Theme.settle) { showUntried.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Try another output")
                                IconView(.chevronDown, size: 16)
                                    .rotationEffect(.degrees(showUntried ? 180 : 0))
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 6)
                        }
                        .buttonStyle(.plain)

                        if showUntried {
                            ForEach(store.untriedOutputs, id: \.self) { output in
                                outputRow(output) { tryOutput(output) }
                                    .opacity(trying == nil || trying == output ? 1 : 0.4)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .animation(Theme.settle, value: store.availableOutputs)
                .animation(Theme.settle, value: store.untriedOutputs)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheetPadding()
    }

    private func outputRow(_ output: SoundOutput, action: @escaping () -> Void) -> some View {
        let isSelected = store.selected.soundOutput == output
        return ChoiceRow(icon: output.icon, title: output.displayName, isSelected: isSelected, action: action) {
            if trying == output {
                ProgressView().tint(Theme.muted)
            } else {
                Button(action: action) { RadioMark(isOn: isSelected) }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
            }
        }
        .disabled(trying != nil)
    }

    /// Asks the TV to switch to an output it hasn't used. If it can't, says so and hides it.
    private func tryOutput(_ output: SoundOutput) {
        trying = output
        refusedName = nil
        Task {
            let worked = await store.setSoundOutput(output)
            trying = nil
            if worked {
                pickThenClose({}, close: onClose)
            } else {
                withAnimation(Theme.settle) { refusedName = output.displayName }
            }
        }
    }
}
