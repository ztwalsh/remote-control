# Remote

A native iPhone remote for LG webOS TVs: switch between TVs, turn them on and off, set the volume, pick the sound output, wind up a sleep timer, and open favorite apps.

The design comes from the HTML prototype in [`prototype/lg-remote.html`](prototype/lg-remote.html). Open it in a browser to see the intended look and motion. The technical and delivery plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Status

This is the start of phase 1. Nothing here has been compiled yet: it was written without a Mac, so expect a few build fixes the first time.

| Part | State |
|---|---|
| Remote screen, TV and Sound out pickers, sleep dial, favorites | Built in SwiftUI. Runs against three example TVs (`MockTV`). |
| TVKit: connection, pairing, volume, power, apps, sound output | Written against LG's SSAP protocol. Not yet tried on a real TV. |
| Discovery (SSDP) and Wake-on-LAN | Written. Needs Apple's multicast entitlement to work on an iPhone. |
| Pairing screens, error states, settings | Not started. |
| Sleep timer that runs while the app is closed | Not started; see the plan, section 4. Today the app turns the TV off itself, only while it's open. |

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

1. **Request the multicast entitlement** from Apple (`com.apple.developer.networking.multicast`). Discovery and Wake-on-LAN both need it on a device. Once granted, add an entitlements file with that key and point the target at it in `project.yml`. Don't add it before approval or signing will fail.
2. **Run phase 0** from the plan on your TVs: pair, set the volume, change the sound output, wake from off, and check the app IDs in `FavoriteApp.swift` against what the TV lists.
3. **Turn on "Turn on via Wi-Fi"** (sometimes "Mobile TV On") on each TV so it can be woken.

## Third-party logos

The app logos in `App/Assets.xcassets` come from [Simple Icons](https://simpleicons.org) (CC0). The logos themselves are trademarks of their owners. They are placeholders: once paired, the app should show the icons the TV provides for each installed app (`LaunchPoint.iconURL`).
