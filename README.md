# Remote

A native iPhone remote for LG webOS, Samsung Smart TVs and Vizio SmartCast TVs: switch between TVs, turn them on and off, set the volume, pick the sound output, wind up a sleep timer, and open favorite apps.

The design comes from the HTML prototype in [`prototype/lg-remote.html`](prototype/lg-remote.html). Open it in a browser to see the intended look and motion. The technical and delivery plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Status

Phase 0: trying it on real TVs. The app builds and runs, and TVKit's tests pass. It hasn't been used with a real TV yet.

| Part | State |
|---|---|
| Remote screen, TV and Sound out pickers, sleep dial, favorites | Built in SwiftUI. Shows three example TVs (`MockTV`) until a real one is added. |
| Adding a TV by IP address | Built: **Your TVs › Add a TV**. Pairs, saves the key in the Keychain, reconnects on launch and on return to the app. Long-press a TV to remove it. |
| TVKit: connection, pairing, volume, power, apps, sound output | Written against LG's SSAP protocol. Not yet tried on a real TV. |
| Samsung (Tizen, 2016 and later) | `TVKit/Samsung`: remote socket on 8002 (8001 on older sets) for buttons, apps and power; UPnP RenderingControl on 9197 for exact volume and mute, falling back to volume keys. No sound output choice (the tile is hidden) and no "Watching …" status: Samsung's local API offers neither. Power on: a set in network standby is woken with its power key (reconnecting with the saved token), one in deep standby with Wake-on-LAN; both need **Power On with Mobile** (Settings › General › Network › Expert Settings). Apps: 2020 and later sets ignore the installed-apps request, so the app checks a catalog of known Samsung app IDs (`SamsungApps.swift`) over the TV's HTTP API, and verifies each launch. To stop the TV asking for permission on every connection, set Settings › General › External Device Manager › Device Connection Manager › Access Notification to **First Time Only**. Volume, buttons and power off tested on 2020–2021 sets; the wake and app changes not yet. |
| Vizio (SmartCast) | `TVKit/Vizio`: HTTPS API on 7345 (9000 on older firmware), paths and key codes from pyvizio. Pairs by typing the PIN the TV shows. Exact volume through the audio settings, falling back to volume keys; inputs, the app on screen, and power by key (needs Quick Start power mode to turn on). Vizio can't list installed apps, so All apps offers well-known ones. No sound output choice. Not yet tried on a real TV. |
| Discovery (SSDP) and Wake-on-LAN | Built: **Add a TV** lists LG, Samsung and Vizio TVs found on the Wi-Fi, with IP entry as a fallback. The power button wakes a TV by Wake-on-LAN. Not yet tried on a real TV. |
| Navigate | Built: **Navigate** on the main screen works like an Apple TV remote: swipe to move the highlight, tap for OK, Back and Home underneath. Sensitivity is set by the constants at the top of `SwipePad` in `NavigateSheet.swift`. TVs paired before this existed must be paired again; the sheet offers that. |
| All apps and pinned favorites | Built: **Favorites › All apps** lists every app on the TV, with search, and the TV's inputs (HDMI, Live TV) in their own row at the top. Icons come from the TV over HTTPS on 3001, trusting its pinned certificate (port 3000 is closed on recent firmware). Tap to open, tap the pin to add or remove it from Favorites. Long-press a favorite to unpin it. Pins are kept per TV; a new TV starts with the defaults it has installed. |
| Sound out | Built: webOS can't list a TV's outputs, so the app learns them per TV: TV speakers plus every output the TV has reported or accepted. Others are under **Try another output**; one the TV refuses is hidden for that TV. |
| First-run onboarding, error states, settings | Not started. |
| Sleep timer that runs while the app is closed | Not started; see the plan, section 4. Today the app turns the TV off itself, only while it's open. |

## TestFlight

Raise `CURRENT_PROJECT_VERSION` in `project.yml`, run `xcodegen`, then archive and upload (Xcode › Product › Archive › Distribute App › TestFlight, or `xcodebuild archive` plus `-exportArchive` with `destination: upload`). Xcode must be signed in to an account on team HSZZQ94DM7, and the app must exist in App Store Connect.

## Run it

You need a Mac with Xcode 15 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen                      # creates RemoteControl.xcodeproj from project.yml
open RemoteControl.xcodeproj
```

Pick an iPhone simulator, or your connected iPhone, and run. Signing uses team `HSZZQ94DM7` with automatic provisioning; change `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to sign with another account.

TVKit's tests run on their own:

```sh
cd Packages/TVKit && swift test
```

## Layout

```
App/
  RemoteControlApp.swift   app entry, uses example TVs for now
  State/                   RemoteStore (app state and actions), favorite apps
  Features/                remote screen, volume card, favorites, sheets, sleep dial
  DesignSystem/            theme, the bulging capsule, the ring, picker rows
  Assets.xcassets          app icon, accent color, app logos
Packages/TVKit/            talking to the TV: SSAP client, pairing store, discovery, Wake-on-LAN, MockTV
prototype/                 the HTML prototype this is built from
docs/PLAN.md               technical plan and phases
project.yml                XcodeGen spec
```

## Before it works with a real TV

1. **Multicast entitlement** (`com.apple.developer.networking.multicast`): granted by Apple on 2026-10-30 and declared in `project.yml` (XcodeGen writes `Config/RemoteControl.entitlements`). If signing fails, open the App ID in the developer portal and check that Multicast Networking is turned on under Additional Capabilities.
2. **Run phase 0** from the plan on your TVs: pair, set the volume, change the sound output, wake from off, and check the app IDs in `FavoriteApp.swift` against what the TV lists.
3. **Turn on "Turn on via Wi-Fi"** (sometimes "Mobile TV On") on each TV so it can be woken.

## Third-party logos

The app logos in `App/Assets.xcassets` come from [Simple Icons](https://simpleicons.org) (CC0). The logos themselves are trademarks of their owners. They are placeholders: once paired, the app should show the icons the TV provides for each installed app (`LaunchPoint.iconURL`).

## Icons and appearance

Icons are from [Central Icons](https://centralicons.com) (licensed; round, 2px radius, 2px stroke), stored as vector PDFs in `App/Assets.xcassets/Icons` and listed in `App/DesignSystem/Icon.swift`. Central has no power icon, so power stays the SF Symbol. To add one: render it from the licensed `@central-icons-react/round-outlined-radius-2-stroke-2` package, unwrap its mask (the shapes are drawn through an SVG mask, which Xcode and Chrome rasterize), print it to PDF, and add an imageset with "Preserve Vector Data" and template rendering.

Colors in `Theme` have light and dark values. The accent is white in dark mode and near-black in light mode. **Your TVs › Appearance** picks System, Light or Dark.

