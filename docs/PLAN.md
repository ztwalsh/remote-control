# Plan: native iPhone remote for LG TVs

Written from what open-source LG remotes do, not yet checked against a real TV. Phase 0 exists to test the uncertain parts first.

## 1. How the app talks to the TV

LG's webOS TVs have a local control channel ("SSAP") used by LG's own phone app and by open-source remotes such as Home Assistant's LG integration. It's a WebSocket on your home Wi-Fi; no cloud or server.

| Need | How it works | Confidence |
|---|---|---|
| Find TVs | SSDP broadcast. LG TVs answer to `urn:lge-com:service:webos-second-screen:1`. | High |
| Connect | WebSocket on port 3001 with a self-signed certificate. Recent firmware dropped the plain port 3000. | High |
| Pairing | The TV asks "Allow this device?" once, then issues a key the app stores. | High |
| Volume | Get, set, step and mute. Subscribing keeps the screen in sync with the physical remote. | High |
| Turn off | A turn-off command. | High |
| Turn on | Wake-on-LAN to the TV's MAC address, read once while connected. Needs "Turn on via Wi-Fi" enabled. | High |
| Favorite apps | The TV lists installed apps with icons, launches by ID, and reports the app on screen. | High |
| Sound output | Read and change: TV speakers, HDMI ARC, optical, Bluetooth. Names vary by model year. | Medium |
| Sleep timer | No documented command. See section 4. | Low |

Using the TV's own app icons avoids shipping other companies' logos.

## 2. iOS requirements

- **Multicast entitlement** (`com.apple.developer.networking.multicast`), requested from Apple. Discovery and Wake-on-LAN both need it. Request it on day one; until it arrives, enter the TV's IP by hand.
- **Local network permission**: a usage description, and `NSAllowsLocalNetworking`.
- **Self-signed certificate**: trust it on first pairing, store its fingerprint, refuse any other.
- **Background limits**: iOS pauses sockets when the app isn't on screen. Reconnect and refresh on every return.

## 3. Architecture

Swift and SwiftUI, iOS 17+. Apple frameworks only: `URLSessionWebSocketTask`, `Network.framework`, Keychain.

| Part | Contents |
|---|---|
| `Packages/TVKit` | Discovery, pairing, the SSAP client, Wake-on-LAN, models, `MockTV`. No UI; unit-tested. |
| `App/DesignSystem` | Theme, the bulging capsule, the dial ring, picker rows. |
| `App/Features` | Remote screen, pickers, sleep timer. Later: onboarding. |
| `App/State` | `RemoteStore`: state and actions. Updates the screen at once, then the TV; corrects from the TV's updates. |

Volume drags send at most 20 updates a second, always the latest value. Echoes from the TV are ignored briefly so the bar doesn't jump.

Motion maps to native tools: spring-animated shapes for the bar and dial, `.contentTransition(.numericText())` for rolling numbers, `.sensoryFeedback` for haptics, system sheets.

## 4. Sleep timer

The phone can't run it, because iOS won't keep the app awake. Options, in order:

1. **The TV's own sleep timer** through its settings service. Undocumented and may vary by year; test in phase 0.
2. **A HomeKit timer**: most 2019+ LG TVs support HomeKit. A one-time automation turns the TV off at the set time, running on a home hub (Apple TV or HomePod). Needs a hub and the TV in the Home app.
3. **No timer**: show the countdown and explain what's needed.

A Live Activity can show the countdown on the Lock Screen and in the Dynamic Island.

## 5. Screens still to design

- First run: permissions, finding TVs, "Accept on your TV"
- Errors: TV unreachable, different Wi-Fi, pairing rejected, firmware too old
- Volume the TV can't control (for example over optical)
- Settings: rename or remove TVs, reorder favorites

## 6. Phases

One experienced iOS engineer; a designer part-time for the missing screens.

| Phase | Time | Work | Done when |
|---|---|---|---|
| 0. Spikes | Week 1 | Request the entitlement. On real TVs: pair, volume, sound output, Wake-on-LAN, sleep timer options. | Every row in section 1 confirmed or replaced |
| 1. TVKit | Weeks 2–3 | Discovery, pairing with stored keys, reconnecting, subscriptions, Wake-on-LAN, a simulated TV | Tests pass against simulated and real TVs |
| 2. Core UI | Weeks 4–6 | Remote screen, volume with haptics, pickers, favorites with the TV's icons, power with Undo | Daily use works |
| 3. Sleep timer | Weeks 7–8 | The dial, the chosen mechanism, a Live Activity | Turns the TV off with the phone locked |
| 4. Hardening | Weeks 9–10 | Onboarding, errors, VoiceOver, Dynamic Type, reduced motion | All error cases handled |
| 5. Launch | Weeks 11–12 | TestFlight, testing across model years, privacy manifest, App Store review | Approved, or installed on your devices |

About 10–12 weeks; 6–7 for personal use only. Later: Control Center controls, Lock Screen widgets, Siri and Shortcuts, Apple Watch.

## 7. Testing

- TVKit unit tests against a scriptable simulated TV; snapshot tests for the custom controls; UI tests for pickers and power.
- Real TVs from webOS 4–5 (2018–2020), 6 or 22 (2021–2022) and 23–25 (2023+), with a soundbar on HDMI ARC, Bluetooth headphones and optical out.

## 8. Risks

| Risk | Mitigation |
|---|---|
| No usable sleep timer command | HomeKit timer, decided in week 1 |
| Multicast entitlement delayed or denied | Manual IP entry |
| Firmware updates change the API | Check capabilities on connect; hide what's unsupported |
| Sound output names vary | Show only what the TV reports |
| App Store trademark issues | "Remote for LG TVs"; no LG logo; TV-provided app icons |
| Pairing relies on undocumented behavior | Review LG's developer terms; follow maintained open-source libraries |
