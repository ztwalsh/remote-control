import SwiftUI

/// The main screen: which TV, its power, and the tools for it.
struct RemoteScreen: View {
    let store: RemoteStore

    @State private var sheet: Sheet?

    /// Which sheet is up. Editing carries the TV's ID with it: kept in separate state, the sheet
    /// was built before that state arrived, found no TV and came up blank.
    enum Sheet: Identifiable, Hashable {
        case tvs, addTV, editTV(String), soundOut, sleep, navigate, allApps

        var id: String {
            switch self {
            case .editTV(let tvID): return "editTV-\(tvID)"
            default: return String(describing: self)
            }
        }
    }

    var body: some View {
        let tv = store.selected
        VStack(alignment: .leading, spacing: 16) {
            header(tv)
            if tv.isOn {
                ScrollView {
                    tools(tv)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Over the whole screen, so the power button is centered on it, not on the space below the header.
        .overlay {
            if !tv.isOn {
                OffView(tvName: tv.name, onTurnOn: { store.setPower(true, for: tv.id) })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(Theme.settle, value: tv.isOn)
        .animation(Theme.settle, value: tv.id)
        .sheet(item: $sheet) { kind in
            sheetContent(kind)
                .environment(store)
                .presentationBackground(Theme.card)
                .presentationCornerRadius(30)
                .presentationDragIndicator(.visible)
        }
        .task { store.start() }
    }

    private func header(_ tv: TVState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { sheet = .tvs } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(tv.name)
                            .font(.system(size: 27, weight: .semibold))
                            .contentTransition(.opacity)
                        IconView(.chevronDown, size: 20)
                            .foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.text)
                    Text(store.status(for: tv))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose TV. Current: \(tv.name)")

            if tv.isOn {
                Button { store.setPower(false, for: tv.id) } label: {
                    IconView(.power, size: 26)
                        .frame(width: 54, height: 54)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(PressScaleStyle(scale: 0.92))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .accessibilityLabel("Turn off \(tv.name)")
            }
        }
    }

    private func tools(_ tv: TVState) -> some View {
        VStack(spacing: 12) {
            VolumeCard(
                volume: tv.volume,
                isMuted: tv.isMuted,
                onChange: store.setVolume,
                onStep: store.stepVolume(by:),
                onToggleMute: store.toggleMute
            )
            HStack(spacing: 12) {
                // Samsung doesn't let other apps choose the sound output, so it gets no tile.
                if store.supportsSoundOutput {
                    ToolTile(icon: .speaker, label: "Sound out", value: tv.soundOutput.displayName) {
                        sheet = .soundOut
                    }
                }
                ToolTile(
                    icon: .moon,
                    label: "Sleep timer",
                    value: tv.sleepEndsAt.map { RemoteStore.duration(minutes: max(1, Int(($0.timeIntervalSinceNow / 60).rounded(.up)))) + " left" } ?? "Off"
                ) {
                    sheet = .sleep
                }
            }
            ToolTile(icon: .touch, label: "Navigate", value: "Swipe and tap") {
                sheet = .navigate
            }
            FavoritesCard(
                apps: store.favorites,
                currentAppID: tv.foregroundAppID,
                onOpen: store.launch(appID:),
                onUnpin: store.unpin,
                onShowAll: { sheet = .allApps }
            )
        }
    }

    @ViewBuilder
    private func sheetContent(_ kind: Sheet) -> some View {
        let close = { sheet = nil }
        switch kind {
        case .tvs:
            TVPickerSheet(
                store: store,
                onAdd: { sheet = .addTV },
                onRename: { id in sheet = .editTV(id) },
                onClose: close
            )
                .presentationDetents([.height(592)])
        case .addTV:
            AddTVSheet(store: store, onClose: close)
                .presentationDetents([.height(628), .large])
                .interactiveDismissDisabled()
        case .editTV(let id):
            EditTVSheet(store: store, tvID: id, onClose: close)
                .presentationDetents([.height(548), .large])
        case .navigate:
            NavigateSheet(store: store, onClose: close)
                .presentationDetents([.large])
        case .allApps:
            AllAppsSheet(store: store, onClose: close)
                .presentationDetents([.large])
        case .soundOut:
            SoundOutSheet(store: store, onClose: close)
                .presentationDetents([.height(468), .large])
        case .sleep:
            SleepTimerSheet(
                endsAt: store.selected.sleepEndsAt,
                canUndo: store.undoSleep?.id == store.selectedID,
                onSet: store.setSleepTimer(minutes:),
                onUndo: store.undoSleepCancel,
                onClose: close
            )
            .presentationDetents([.height(498)])
        }
    }
}

/// Sound out and Sleep timer: an icon, a label and the current value.
struct ToolTile: View {
    let icon: Icon
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                IconView(icon, size: 24)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                    Text(value)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }
}

/// Shown while the selected TV is off: one big button to wake it, centered on the screen.
struct OffView: View {
    let tvName: String
    let onTurnOn: () -> Void

    var body: some View {
        Button(action: onTurnOn) {
            IconView(.power, size: 60)
                .frame(width: 168, height: 168)
                .background(Theme.card, in: Circle())
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityLabel("Turn on \(tvName)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
