import SwiftUI

/// The main screen: which TV, its power, and the tools for it.
struct RemoteScreen: View {
    let store: RemoteStore

    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case tvs, soundOut, sleep
        var id: String { rawValue }
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
            } else {
                OffView(
                    tvName: tv.name,
                    canUndo: store.undoPowerOffID == tv.id,
                    onTurnOn: { store.setPower(true, for: tv.id) },
                    onUndo: store.undoPowerOff
                )
                .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .animation(Theme.settle, value: tv.isOn)
        .animation(Theme.settle, value: tv.id)
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { kind in
            sheetContent(kind)
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
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
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
                Button { store.setPower(false, for: tv.id, offerUndo: true) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 54, height: 54)
                        .background(Theme.blue, in: Circle())
                        .foregroundStyle(.white)
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
                ToolTile(systemImage: "hifispeaker", label: "Sound out", value: tv.soundOutput.displayName) {
                    sheet = .soundOut
                }
                ToolTile(
                    systemImage: "moon",
                    label: "Sleep timer",
                    value: tv.sleepEndsAt.map { RemoteStore.duration(minutes: max(1, Int(($0.timeIntervalSinceNow / 60).rounded(.up)))) + " left" } ?? "Off"
                ) {
                    sheet = .sleep
                }
            }
            FavoritesCard(apps: store.favorites, currentAppID: tv.foregroundAppID, onOpen: store.launch)
        }
    }

    @ViewBuilder
    private func sheetContent(_ kind: Sheet) -> some View {
        let close = { sheet = nil }
        switch kind {
        case .tvs:
            TVPickerSheet(store: store, onClose: close)
                .presentationDetents([.height(360)])
        case .soundOut:
            SoundOutSheet(store: store, onClose: close)
                .presentationDetents([.height(400)])
        case .sleep:
            SleepTimerSheet(
                endsAt: store.selected.sleepEndsAt,
                canUndo: store.undoSleep?.id == store.selectedID,
                onSet: store.setSleepTimer(minutes:),
                onUndo: store.undoSleepCancel,
                onClose: close
            )
            .presentationDetents([.height(470)])
        }
    }
}

/// Sound out and Sleep timer: an icon, a label and the current value.
struct ToolTile: View {
    let systemImage: String
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.blue)
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
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }
}

/// Shown while the selected TV is off: one big button to wake it, and Undo right after turning it off.
struct OffView: View {
    let tvName: String
    let canUndo: Bool
    let onTurnOn: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Button(action: onTurnOn) {
                Image(systemName: "power")
                    .font(.system(size: 48, weight: .regular))
                    .frame(width: 168, height: 168)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.5))
                    .foregroundStyle(Theme.blue)
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))
            .accessibilityLabel("Turn on \(tvName)")
            ZStack {
                if canUndo {
                    PillButton(title: "Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                }
            }
            .frame(height: 38)
            .animation(Theme.bounce, value: canUndo)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
