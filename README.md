# ios-android-simulator-testing — let Claude test your mobile app itself

English · [Türkçe](README.tr.md)

When Claude Code changes a screen, it usually asks you to "take a look, does it work?". With this
skill it checks for itself: it boots the simulator, goes to the screen, taps the buttons, takes a
screenshot and looks at it, and if something is wrong it fixes it and looks again. You get to see
finished work.

Works with the iOS Simulator and the Android emulator, for Expo, React Native, Flutter or native apps.
Needs **macOS + Xcode** (plus Android Studio for Android).

## Install (once, ~2 min)

```bash
npx skills add bartwo21/ios-android-simulator-testing -g -a claude-code -y && ~/.claude/skills/ios-android-simulator-testing/sim.sh setup
```

Android needs nothing extra; `adb` comes with Android Studio. You just need an emulator (AVD).
Update later with `npx skills update`.

## Hook it up to your project

Nothing to configure: on the first run the skill reads your bundle id from `app.json`, the Xcode
project or Android gradle, writes `.sim/config` and adds `.sim/` to `.gitignore` (screenshots go there).

**Project card:** on first use Claude asks how to start the app, how to sign in and which deeplinks
exist, then writes the answers to `.claude/skills/<app>-run/SKILL.md` itself. Next time it reads the
card and goes straight to the right screen. A card looks like this:

```markdown
---
name: myapp-run
description: Use when myapp must be run, screenshotted or tapped through on the simulator.
---
Generic tool: the ios-android-simulator-testing skill.

## Start
`npx expo start` in the background, then `npx expo run:ios`. Rebuild after adding a native package.

## Sign in
The login screen has a "Demo" button (__DEV__ only). Account: demo / Demo123!

## Deeplinks
| screen  | url                  |
|---------|----------------------|
| profile | myapp://profile      |
| product | myapp://product/<id> |

## Known traps
- (Let Claude add to this whenever it gets stuck.)
```

Two things make testing much easier:
1. **Deeplinks** — Claude jumps straight to a screen instead of tapping its way there. The most reliable path.
2. **A dev sign-in** — Apple/Google sign-in can't be automated. Add a demo-account button or an
   automatic sign-in under `__DEV__`.

## Usage

Just ask: *"fix the profile screen and check it on the simulator"*, *"how does it look on Android,
take a screenshot"*, *"try the login → cart → checkout flow"*. Claude opens the skill by itself.

You can drive it by hand too:

```bash
S=~/.claude/skills/ios-android-simulator-testing/sim.sh   # Android: $S -a <command>
$S open "myapp://profile"   # go to a screen
$S shot profile             # screenshot → .sim/shots/profile.png
$S tree                     # buttons/text on screen + their coordinates
$S tap "Save"               # tap by label
$S type "hello"             # type
$S rec start / $S rec stop  # video → frames + one contact sheet Claude can look at
$S dark                     # dark mode
$S help                     # everything
```

## Good to know

- If you touch the simulator while Claude is using it, you'll get in each other's way; watch while it works.
- Don't run iOS and Android at the same time — the Mac slows to a crawl. Finish one, then the other.
- Don't let Claude test deleting or purchasing on a simulator signed into your real account; use a demo account.
- When it gets stuck on something, tell Claude "add this to the project card as a trap" — it won't get stuck there again.

## How it works

`sim.sh` wraps `xcrun simctl` + [idb](https://fbidb.io) on iOS and `adb` on Android behind the same
commands. Coordinates are always screenshot pixels on both platforms. Recordings are turned into
frames and a contact sheet with AVFoundation (no ffmpeg), so Claude can check animations and transitions. `tree` lists only on-screen
elements and `tap` refuses off-screen coordinates, so a stale coordinate can't hit a hidden
"Delete account" button.

MIT License.
