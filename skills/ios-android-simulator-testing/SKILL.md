---
name: ios-android-simulator-testing
description: Use when a change to an iOS or Android app (Expo, React Native, Flutter, native Swift/Kotlin) needs to be SEEN working rather than reasoned about — "run it", "test it on the simulator", "take a screenshot", "does this look right", "how does it look on Android", "tap through the flow", after any UI edit, or when a bug only reproduces in the running app. Drives the iOS Simulator and the Android emulator on macOS — taps, typing, deeplinks, screenshots, screen recordings, logs.
---

# iOS + Android simulator testing

Verify a UI change yourself instead of asking the user to "check on the device". One tool, both platforms:

```bash
S=<this skill's directory>/sim.sh   # the "Base directory" given when the skill loads
$S <command>                        # iOS
$S -a <command>                     # same command, Android
$S help                             # every command
```

`idb not installed` → run `$S setup` once.

## Read the project card first

If `<project>/.claude/skills/*-run/SKILL.md` exists, read it FIRST: how to start the app, how to sign in,
the deeplink map. If there is none, ask the user for those three, then write them into such a card
(template in the README). `<project>/.sim/config` (`BUNDLE_ID`, `DEVICE`, `AVD`) is written automatically on the
first run from app.json / the Xcode project / Android gradle; edit it only if the guess is wrong.

## Loop

```
1. $S boot                       (no-op if already running)
2. start the app                 (command from the project card; JS changes reload through Metro)
3. $S open "scheme://screen"     go STRAIGHT to the screen
4. $S shot name                  → open the PNG with Read and LOOK at it
5. wrong? fix it, back to 3
```

- **Deeplink when you can, tap when you must.** Taps are for what a deeplink can't reach: buttons, sheets, forms, gestures.
- **`$S tree` before every tap.** Tap by label: `$S tap "Save"`. Raw pixels only when there is no label.
- **A screen you did not look at is not verified.** Don't just print the path — say what you saw.
- **Transitions and animations are not verified on screenshots:** `$S rec start` → action → `$S rec stop`; it prints a
  `sheet.png` (frames in time order, left→right, top→bottom) — open it with Read. More frames: `$S rec stop 24`.
- An app that ships on both platforms is done when it was seen on both — but **one at a time**:
  `xcrun simctl shutdown all` / `adb emu kill` in between; both together freeze the Mac.

## Traps

| Symptom | Cause / fix |
|---|---|
| `tree` is empty | App not in front, or a system dialog is up (iOS system dialogs are not in the tree) → `shot`, tap by pixel |
| iOS 26 tab bar items missing from `tree` (only "Tab Bar") | The system tab bar is not exposed → deeplink, or pixels from a screenshot |
| Screen changes without you touching it | The user is driving the simulator → stop tapping, only take screenshots |
| Login screen | Never automate it (Apple/Google sign-in can't be scripted). Use a `__DEV__` demo account / auto sign-in; remove temporary patches afterwards |
| No on-screen keyboard on iOS | `type` sends hardware key events; verify keyboard-dependent layout on a real device |
| Android `type` mangles non-ASCII | `adb input text` types ASCII only |
| Android doesn't pick up the change | `$S -a launch` (force-stops and restarts) |
| Crash on launch / "Symbol missing" after adding a native package | Rebuild (`npx expo run:ios` / `run:android`); a reload is not enough |
| Crashed, no idea why | `$S log`; iOS crash reports in `~/Library/Logs/DiagnosticReports/<App>-*.ips` |
| Emulator quits by itself, log says "hanging thread" | The Mac is out of memory → close the iOS simulator / other heavy apps, `$S -a boot` |
| Half-drawn screenshot on a map / heavy screen | Wait a few seconds before `shot` |

On a simulator signed into a real account, tap delete / sign out / purchase only when that is the task.
`tap` already refuses off-screen coordinates; `tree` lists on-screen elements only.

No Mac or no simulator → use a cloud simulator (e.g. EAS). Pure logic change with tests → skip the simulator.
