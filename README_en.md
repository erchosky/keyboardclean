# Kyboardclean

Kyboardclean is a native macOS utility for physically cleaning a Mac keyboard and trackpad. During Cleaning Mode it blocks compatible keyboard and mouse events with the real limitations imposed by macOS.

The official name is **Kyboardclean**. It should not be corrected to Keyboardclean.

## What It Does

- Shows a compact SwiftUI control window.
- Shows a full-screen cleaning overlay on all AppKit-detected displays.
- Uses `CGEventTap` to discard compatible keyboard and mouse events while Cleaning Mode is active.
- Blocks clicks, drags, mouse movement and scroll by default so events do not pass through the overlay.
- Provides its own redundant exits: timer, Control + Option + Command + Escape, Escape 5 times, and a hard 30-minute safety limit. Command + Option + Escape is allowed through to open macOS Force Quit; it does not stop Kyboardclean directly.
- Includes Settings for sound, language and appearance, plus Accessibility and Secure Event Input status.
- Can optionally remain available in the menu bar, with quick durations and access to the main window and Settings.
- Provides a configurable, disableable global shortcut, optional local reminders, and local session history with basic statistics.
- Includes real Spanish and English localization through `es.lproj/Localizable.strings` and `en.lproj/Localizable.strings`.
- Includes an app icon in `Assets.xcassets/AppIcon.appiconset`, generated from `Resources/AppIconSource.png`.

## What It Does Not Do

- It does not connect to the internet.
- It does not include analytics, tracking, telemetry, crash reporting, login, databases or auto-updates.
- It does not store keys, keycodes, text or input history.
- Cleaning history stores only date, duration and outcome; it remains in `UserDefaults` and can be cleared from Settings.
- It does not convert keys to text.
- It does not call `CGEventKeyboardGetUnicodeString`.
- It does not try to block hardware or system safety controls such as Touch ID or the physical power button.
- It does not block Command + Option + Escape, the macOS Force Quit shortcut.
- It cannot guarantee blocking every multitouch gesture handled by macOS outside normal application events.

## Compatibility

Kyboardclean targets macOS 14 Sonoma or later and builds with Xcode 16 or later (Swift 6).

Expected compatibility:

- MacBook Air.
- MacBook Pro.
- MacBook Neo.
- iMac.
- Mac mini with external display.
- Mac Studio with external display.
- Retina displays.
- External displays.
- Multiple displays.
- Small and large resolutions.
- Light Mode and Dark Mode.

The app is primarily intended for Apple Silicon. The project does not force a single architecture and uses standard Xcode macOS settings; Release builds can be produced as Universal Binary for Apple Silicon and Intel compatible with macOS 14+, when the local Xcode environment supports it.

There are no external dependencies.

## Language And Settings

Open **Settings** from the gear button in the main window or from **Kyboardclean > Settings...**.

Available options:

- Sound effects on/off.
- Language: Automatic from system, Spanish or English.
- Appearance: System, Light or Dark.
- Accessibility and Secure Event Input status.
- Optional menu bar icon.
- Configurable, disableable global shortcut.
- Reminders: never, weekly, every two weeks or every 30 days.
- Local activity: cleaning count, total time, last cleaning, average and clearable history.

Preferences, the shortcut and history are stored locally in `UserDefaults`. The language preference applies immediately to the SwiftUI interface, overlay and custom menu commands. Automatic selects Spanish or English from the effective macOS localization and falls back to English for unsupported languages. No data is sent anywhere. Reminders use `UserNotifications` and request permission only after selecting a frequency other than Never.

History keeps the 500 most recent sessions and removes the oldest first. This bounds `UserDefaults` size and startup work; it covers more than one year of daily use or almost ten years of weekly use. A session is recorded only after the overlay and EventTap have both been confirmed active.

Reminders use one pending request with a stable identifier. Changing language or frequency replaces that request. Selecting Never clears the frequency; losing authorization or failing to schedule cancels the effective request but keeps the chosen frequency so it can recover later. Every 30 days uses a repeating interval independent of the current time zone.

Standard elements owned by AppKit or macOS, such as Edit, Window and the About panel chrome, follow the system language. `InfoPlist.strings` localizes the app-owned About content in Spanish and English. Changing the macOS language while Kyboardclean is open may require relaunching the app to refresh those standard elements; switching the in-app Spanish/English/Automatic preference does not restart a session.

The two bundled effects come from SND01 "sine", designed by Yasuhiro Tsuchiya and published at [snd.dev](https://snd.dev/). `button.wav` confirms activation and `notification.wav` marks a normal timer completion. SND's terms permit use inside personal and commercial applications but prohibit redistributing the raw files by themselves; provenance and terms are recorded in `Kyboardclean/Resources/Sounds/NOTICE.txt`.

## Open The Project In Xcode

1. Open `Kyboardclean.xcodeproj`.
2. Select the shared `Kyboardclean` scheme.
3. Select the `Kyboardclean` target.
4. Build with Xcode 16 or later (Swift 6) on macOS 14 or later.

The project does not require XcodeGen, Swift Package Manager packages or downloaded dependencies.

## Optional Sounds

The two sound effects are **not included in the repository**: their license (SND) allows using them inside apps but not redistributing the raw files on their own. Without them the app works the same, just silently.

To add them, download the SND01 "sine" pack from [snd.dev](https://snd.dev/), copy `button.wav` to `Kyboardclean/Resources/Sounds/activation.wav` and `notification.wav` to `Kyboardclean/Resources/Sounds/success.wav`, then rebuild. Git ignores them.

## Build From Terminal

Debug:

```sh
xcodebuild -project Kyboardclean.xcodeproj -scheme Kyboardclean -configuration Debug build
```

Release:

```sh
xcodebuild -project Kyboardclean.xcodeproj -scheme Kyboardclean -configuration Release build
```

Tests (99 unit tests):

```sh
xcodebuild -project Kyboardclean.xcodeproj -scheme Kyboardclean -destination 'platform=macOS' test
```

`DEVELOPMENT_TEAM` is intentionally empty so a local build can use "Sign to Run Locally" without requiring an Apple Developer account.

## Distribution Outside The App Store

Kyboardclean is intended for personal distribution outside the App Store. It uses a normal macOS target with empty entitlements and without App Sandbox because low-level input blocking with `CGEventTap` does not fit the usual App Store sandbox model.

For personal use or sharing with trusted people:

1. Generate the app with `Scripts/build_release.sh`.
2. Distribute `dist/Kyboardclean.dmg` or `dist/Kyboardclean.app.zip`.
3. On another Mac, drag `Kyboardclean.app` to Applications.
4. If Gatekeeper blocks launch, use right-click > Open and confirm.

Without notarization, macOS can show Gatekeeper warnings. For real public distribution, you need an Apple Developer account, a Developer ID Application certificate, hardened runtime signing and Apple notarization. Local/ad-hoc signing is only for personal use or private testing.

Use the DMG or ZIP as the distribution artifact. Do not share `dist/Kyboardclean.app` directly: Finder can add metadata to the bundle after signing. The packaging scripts clean and verify the app while generating the packages.

`Scripts/build_release.sh` does not use `codesign --deep` to verify the final app. If future versions add frameworks or helper tools, they must be signed and verified explicitly.

## Distribution Scripts

Build the Release app in `dist/`:

```sh
Scripts/build_release.sh
```

Generate DMG:

```sh
Scripts/build_dmg.sh
```

Generate compiled app ZIP:

```sh
Scripts/build_zip.sh
```

Generate clean source ZIP:

```sh
Scripts/build_source_zip.sh
```

Expected output:

```text
dist/
├── Kyboardclean.app
├── Kyboardclean.dmg
├── Kyboardclean.app.zip
└── Kyboardclean_Source.zip
```

## Accessibility Permission

Kyboardclean needs Accessibility permission so macOS allows it to install a `CGEventTap` capable of discarding keyboard events during Cleaning Mode.

If the permission is missing:

- The app does not crash.
- Start is disabled.
- The UI explains that Accessibility is required.
- The Open Accessibility button opens Privacy & Security > Accessibility.
- You may need to quit and reopen Kyboardclean after granting permission.

To revoke permission, open System Settings > Privacy & Security > Accessibility, disable Kyboardclean or remove it from the list. Then quit and reopen the app to confirm the state.

## Input Monitoring

Kyboardclean does not explicitly request Input Monitoring and does not use APIs to convert or read typed text. Accessibility is the permission needed for the `CGEventTap` behavior implemented here. macOS privacy prompts may vary by system version and local policy; if macOS shows an additional Input Monitoring prompt, grant it only if you trust the locally built app.

## Secure Event Input

macOS can enable Secure Event Input when password fields or sensitive apps are active. When Secure Event Input is active, macOS may stop delivering keys to `CGEventTap`.

Kyboardclean checks `IsSecureEventInputEnabled()` before starting and during Cleaning Mode. If Secure Event Input is active, Cleaning Mode does not start or stops immediately because safe blocking cannot be guaranteed.

During a session, a supervisor independent from the UI thread checks Secure Event Input and Accessibility and can disarm the event tap directly. Window and display validation uses AppKit and must run on the main thread; the monotonic hard limit remains independent if that thread stalls.

## What Gets Blocked

| Item | Blocked? | Note |
|---|---|---|
| Normal keys | Yes | `keyDown` and `keyUp` are discarded through `CGEventTap`. |
| Modifiers | Yes | `flagsChanged` is discarded. |
| Media/brightness keys | Best effort | The mask includes the raw `systemDefined` bit when macOS delivers those keys as CGEvents; some hardware/system routes can bypass normal delivery. |
| Command + Option + Escape | No | Explicitly allowed so macOS Force Quit remains available. |
| Clicks | Yes | `leftMouseDown`, `leftMouseUp`, right click and other clicks are discarded through `CGEventTap`. There is no mouse route to Stop during Cleaning Mode. |
| Mouse movement | Yes | `mouseMoved` is discarded through `CGEventTap`. |
| Drags | Yes | `leftMouseDragged`, `rightMouseDragged` and `otherMouseDragged` are discarded. |
| Scroll | Yes | `scrollWheel` is discarded. |
| Trackpad gestures | Partial / not guaranteed | Some gestures are higher-level system behavior and may not exist as blockable CGEvents. |
| Touch ID | No | Hardware/system security route. |
| Power button | No | Hardware/system route. |
| Secure Event Input | No | Cleaning Mode does not start or stops because macOS may not deliver keys to `CGEventTap`. |

## Why Kyboardclean Is Not A Keylogger

Kyboardclean uses `CGEventTap` to discard events during Cleaning Mode. The callback checks only the minimum state needed for emergency exits: Escape, modifiers for Control + Option + Command + Escape, and short timestamps for the Escape x5 sequence.

Kyboardclean does not store keycodes, does not store typed text, does not call `CGEventKeyboardGetUnicodeString`, does not write keyboard logs and does not print keyboard events to console. The source code also contains no networking APIs such as `URLSession`, `Network`, `NWConnection`, `NSURLConnection`, `CFNetwork`, sockets or HTTP calls, so there is no code path for sending input anywhere.

`UserDefaults` is used only for harmless preferences, shortcut and reminder configuration, and the local session history described above. It never contains keys or input events.

## First Safe Test

1. Build and open Kyboardclean.
2. Grant Accessibility permission.
3. Quit and reopen the app if the permission state does not update.
4. Choose 30 seconds.
5. Start Cleaning Mode.
6. Confirm the overlay appears.
7. Confirm typing does not affect other apps.
8. Let the timer finish before trying longer sessions.

Do not start the first test with Manual mode or a long session.

## How To Exit If Something Goes Wrong

- Press Control + Option + Command + Escape.
- Press Escape 5 times in 3 seconds.
- Press Command + Option + Escape to open macOS Force Quit.
- Wait for the timer or the hard 30-minute limit.
- Quit the app from macOS if possible; when the process exits, macOS removes the event tap.
- Use hardware or system controls such as the power button or Touch ID if needed. Kyboardclean does not block them.

## Manual Test Plan

1. Open the app without Accessibility permission. Expected: no crash, Start is disabled and explanation is shown.
2. Grant Accessibility. Expected: Refresh shows permission granted; relaunching the app also works.
3. Start a 30-second session. Expected: overlay appears, keyboard is blocked and timer finishes by itself.
4. Start a 60-second session. Expected: countdown starts at 60 seconds and finishes by itself.
5. Test Control + Option + Command + Escape. Expected: session ends immediately.
6. Test Escape x5 in 3 seconds. Expected: session ends immediately.
7. Test Manual mode. Expected: no normal countdown and the hard limit counts from 30 minutes.
8. Press many keys at once. Expected: no text or actions reach other apps; emergency shortcut remains available when macOS delivers it.
9. Test an external or Bluetooth keyboard if available. Expected: keyboard events delivered to the event tap are discarded.
10. Test two displays if available. Expected: overlay appears on all connected displays.
11. Quit the app during Cleaning Mode. Expected: Cleaning Mode stops and the event tap is removed with the process.
12. Sleep or lock the Mac during Cleaning Mode. Expected: the app attempts to stop cleanly through system notifications.
13. Confirm privacy. Expected: no networking APIs, telemetry, keyboard logs or key history.
14. Activate a password field or app that enables Secure Event Input. Expected: Cleaning Mode does not start or stops if already active.

## Real Assumptions And Limitations

- The app is distributed outside the App Store and is not sandboxed.
- Accessibility is the required permission for this behavior with `CGEventTap`.
- Clicks are blocked fail-closed. There is no mouse Stop button during Cleaning Mode because the `CGEventTap` does not calculate a secure SwiftUI rectangle to allow only that area.
- Kyboardclean uses `cgSessionEventTap` instead of `cghidEventTap` to limit scope to the user session. Some system keys, gestures or hardware routes may not be delivered as blockable CGEvents.
- The mask includes the raw `systemDefined` bit because CoreGraphics does not expose a stable Swift case for that event in every SDK. It is best-effort coverage for media/brightness keys when macOS delivers them through that route.
- Connecting, disconnecting or reconfiguring displays during Cleaning Mode stops the session for safety. Kyboardclean does not try to rebuild overlays while the EventTap is active.
- Media keys, brightness keys, Secure Event Input and some gestures are documented as limited because macOS or hardware can manage them outside normal event delivery.
- The hard safety limit is exactly 30 minutes, including Manual mode.
- If the app is not notarized, Gatekeeper can show warnings on another Mac.

## License

Kyboardclean is released under the MIT License. See `LICENSE`.
