#!/usr/bin/env bash
# ios-android-simulator-testing — drive the iOS Simulator and the Android emulator
# with the SAME commands.
#   iOS:     xcrun simctl (ships with Xcode) + fb-idb (real taps, swipes, typing)
#   Android: adb (+ emulator)
#
#   sim.sh <command> ...      → iOS
#   sim.sh -a <command> ...   → Android
#
# Rules:
#  · Coordinates are ALWAYS screenshot PIXELS. idb wants points on iOS; the
#    script converts. Android is already in pixels.
#  · `tree` prints only elements that are ON SCREEN; `tap` refuses off-screen
#    coordinates. (An off-screen coordinate once landed on "Delete account".)
#  · Project settings come from .sim/config (BUNDLE_ID, DEVICE, AVD, ANDROID_ID).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SIM_DIR="${SIM_DIR:-$ROOT/.sim}"
SHOTS="$SIM_DIR/shots"

# No .sim/config yet → read the bundle id from the project itself (Expo app.json,
# the Xcode project, Android gradle), write the config and gitignore .sim/.
if [ ! -f "$SIM_DIR/config" ] && [[ "${1:-}" != help && "${1:-}" != setup ]]; then
  conf=$(ROOT="$ROOT" python3 "$HERE/detect.py" || true)
  if [ -n "$conf" ]; then
    mkdir -p "$SIM_DIR" && printf '%s\n' "$conf" >"$SIM_DIR/config"
    echo "sim: wrote $SIM_DIR/config ($(echo "$conf" | tr '\n' ' '))" >&2
    if git -C "$ROOT" rev-parse >/dev/null 2>&1 && ! git -C "$ROOT" check-ignore -q "$SIM_DIR/config"; then
      gi="$ROOT/.gitignore"; [ -s "$gi" ] && [ -n "$(tail -c1 "$gi")" ] && echo >>"$gi"
      echo ".sim/" >>"$gi"; echo "sim: added .sim/ to .gitignore" >&2
    fi
  fi
fi
[ -f "$SIM_DIR/config" ] && . "$SIM_DIR/config"
DEVICE="${DEVICE:-iPhone 17 Pro}"
AVD="${AVD:-}"
ANDROID_ID="${ANDROID_ID:-${BUNDLE_ID:-}}"   # set in config if the Android package differs
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

PLATFORM=ios
[ "${1:-}" = "-a" ] && { PLATFORM=android; shift; }

die() { echo "sim: $*" >&2; exit 1; }
need_bundle() { [ -n "${BUNDLE_ID:-}" ] || die "no BUNDLE_ID found in the project — write it to $SIM_DIR/config (see: sim.sh help)"; }
is_num() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ════════════════════════════ iOS ════════════════════════════

IDB="$HERE/venv/bin/idb"
[ -x "$IDB" ] || IDB="$(command -v idb || true)"

idb_() {
  [ -n "$IDB" ] || die "idb not installed — run once: sim.sh setup"
  # After a simulator restart idb holds a stale companion connection ("Failed to
  # connect to companion", "Mach port invalid"). `idb kill` resets it; retry once.
  "$IDB" "$@" --udid "$UDID" 2>/dev/null && return
  "$IDB" kill >/dev/null 2>&1 || true
  "$IDB" "$@" --udid "$UDID"
}

resolve_udid() {
  [ -n "${IDB_UDID:-}" ] && { echo "$IDB_UDID"; return; }
  xcrun simctl list devices booted -j | DEVICE="$DEVICE" python3 -c '
import json, os, sys
booted = [x for rt in json.load(sys.stdin)["devices"].values() for x in rt]
if not booted: sys.exit("sim: no simulator is running — first: sim.sh boot")
if len(booted) == 1: print(booted[0]["udid"]); raise SystemExit
hit = [x for x in booted if x["name"] == os.environ["DEVICE"]]
if not hit: sys.exit("sim: several simulators running (%s), none is DEVICE=%s" % (", ".join(x["name"] for x in booted), os.environ["DEVICE"]))
print(hit[0]["udid"])'
}

# "width height density" (pixels). idb describe is the source of truth.
ios_screen() {
  idb_ describe --json | python3 -c 'import json,sys; s=json.load(sys.stdin)["screen_dimensions"]; print(s["width"], s["height"], s["density"])'
}

# iOS shows "Open in <app>?" on every deeplink, and the dialog belongs to
# SpringBoard so it never appears in `tree`. Pre-approve the scheme, as Expo CLI does.
ios_approve_scheme() {
  local scheme="${1%%:*}"
  [ -n "${BUNDLE_ID:-}" ] && [ "$scheme" != "$1" ] || return 0
  P="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Preferences/com.apple.launchservices.schemeapproval.plist" \
  K="com.apple.CoreSimulator.CoreSimulatorBridge-->$scheme" V="$BUNDLE_ID" python3 -c '
import os, plistlib
p, k, v = os.environ["P"], os.environ["K"], os.environ["V"]
d = plistlib.load(open(p, "rb")) if os.path.exists(p) else {}
if d.get(k) != v:
    d[k] = v; plistlib.dump(d, open(p, "wb"), fmt=plistlib.FMT_BINARY)'
}

ios_exe() {  # the app's process name (for the log filter)
  local app; app=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" 2>/dev/null) || die "$BUNDLE_ID is not installed"
  /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Info.plist"
}

# ═════════════════════════ Android ═══════════════════════════

android_screen() {  # "width height 1"
  adb shell wm size | awk -F'[ x]' '/Physical/{w=$(NF-1); h=$NF} /Override/{ow=$(NF-1); oh=$NF} END{print (ow?ow:w), (oh?oh:h), 1}'
}

android_tree_raw() {
  # Delete the old dump first: uiautomator fails while something animates and
  # `cat` would return the PREVIOUS screen. Retry a few times.
  local i out
  for i in 1 2 3 4; do
    adb shell rm -f /sdcard/ui.xml
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
    out=$(adb exec-out cat /sdcard/ui.xml 2>/dev/null || true)
    [[ "$out" == "<?xml"* ]] && { printf '%s' "$out"; return; }
    sleep 1
  done
}

# ═════════════════════════ shared ════════════════════════════

screen() { if [ "$PLATFORM" = ios ]; then ios_screen; else android_screen; fi; }

# On-screen elements: "x,y<TAB>type<TAB>label" (pixels, centre). Off-screen ones are skipped.
tree() {
  local needle="${1:-}" scr; scr=$(screen)
  if [ "$PLATFORM" = ios ]; then
    idb_ ui describe-all --json | FMT=ios S="$scr" F="$needle" python3 "$HERE/tree.py"
  else
    android_tree_raw | FMT=android S="$scr" F="$needle" python3 "$HERE/tree.py"
  fi
}

# Tap by label: exact match first, else substring. Several → the first (nth: tap "X" #2).
find_label() {
  local label="$1" nth="${2:-1}" rows
  rows=$(tree "$label" | L="$label" python3 -c '
import os, sys
l = os.environ["L"].lower(); rows = [r.rstrip("\n") for r in sys.stdin if r.strip()]
exact = [r for r in rows if r.split("\t")[2].lower() == l]
seen, out = set(), []
for r in exact or rows:  # a Button and its own text sit at the same spot: one candidate
    k = tuple(int(v) // 40 for v in r.split("\t")[0].split(","))
    if k not in seen: seen.add(k); out.append(r)
print("\n".join(out))')
  [ -n "$rows" ] || die "\"$label\" is not on screen — check with: sim.sh tree"
  local n; n=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
  [ "$n" -gt 1 ] && printf '%s\n' "$rows" | sed 's/^/  candidate: /' >&2
  printf '%s\n' "$rows" | sed -n "${nth}p" | cut -f1 | tr ',' ' '
}

cmd="${1:-help}"; shift || true
[ "$PLATFORM" = ios ] && [[ "$cmd" != boot && "$cmd" != help && "$cmd" != setup ]] && UDID=$(resolve_udid)

case "$PLATFORM:$cmd" in

*:setup)
  # idb for iOS taps: the companion from Homebrew, the client into a venv next to this script.
  command -v idb_companion >/dev/null || { echo "→ brew tap facebook/fb && brew install idb-companion"; brew tap facebook/fb && brew install idb-companion; }
  # A moved/copied venv keeps absolute paths and breaks — rebuild it if idb won't start.
  "$HERE/venv/bin/idb" --help >/dev/null 2>&1 || { rm -rf "$HERE/venv"; /usr/bin/python3 -m venv "$HERE/venv" && "$HERE/venv/bin/pip" install -q fb-idb; }
  "$HERE/venv/bin/idb" --help >/dev/null && echo "ready: idb installed"
  command -v adb >/dev/null && echo "ready: adb found (Android)" || echo "for Android: install Android Studio (adb comes with it)" ;;

ios:boot)
  name="${1:-$DEVICE}"
  udid=$(xcrun simctl list devices available -j | NAME="$name" python3 -c '
import json, os, sys
hit = [x for rt in json.load(sys.stdin)["devices"].values() for x in rt if x["name"] == os.environ["NAME"]]
if not hit: sys.exit("sim: no simulator named \"%s\" (xcrun simctl list devices)" % os.environ["NAME"])
print(sorted(hit, key=lambda x: x["udid"])[-1]["udid"])')
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a Simulator
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  echo "$udid" ;;
android:boot)
  adb get-state >/dev/null 2>&1 && { echo "emulator already running"; exit 0; }
  avd="${1:-$AVD}"; [ -n "$avd" ] || avd=$(emulator -list-avds | head -1)
  [ -n "$avd" ] || die "no AVD — create one in Android Studio › Device Manager"
  mkdir -p "$SIM_DIR"
  nohup emulator -avd "$avd" -no-snapshot-save >"$SIM_DIR/emulator.log" 2>&1 &
  adb wait-for-device
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
  echo "booted: $avd" ;;

ios:install)     xcrun simctl install "$UDID" "${1:?usage: sim.sh install <App.app>}"; echo "installed" ;;
android:install) adb install -r "${1:?usage: sim.sh -a install <app.apk>}" ;;

ios:launch)
  need_bundle
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" ;;
android:launch)
  need_bundle
  adb shell am force-stop "$ANDROID_ID"
  adb reverse tcp:"${METRO_PORT:-8081}" tcp:"${METRO_PORT:-8081}" >/dev/null 2>&1 || true  # let the emulator reach Metro
  act=$(adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$ANDROID_ID" | tail -1 | tr -d '\r')
  [[ "$act" == */* ]] || die "$ANDROID_ID is not installed"
  adb shell am start -n "$act" >/dev/null
  echo "launched: $ANDROID_ID" ;;

ios:kill)     need_bundle; xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true ;;
android:kill) need_bundle; adb shell am force-stop "$ANDROID_ID" ;;

ios:open)
  url="${1:?usage: sim.sh open <scheme://path>}"
  ios_approve_scheme "$url"
  xcrun simctl openurl "$UDID" "$url"; echo "opened: $url" ;;
android:open)
  url="${1:?usage: sim.sh -a open <scheme://path>}"
  adb shell am start -a android.intent.action.VIEW -d "'$url'" >/dev/null 2>&1; echo "opened: $url" ;;

*:shot)
  mkdir -p "$SHOTS"
  out="$SHOTS/${1:-$(date +%H%M%S)}$([ "$PLATFORM" = android ] && echo -android || true).png"
  if [ "$PLATFORM" = ios ]; then xcrun simctl io "$UDID" screenshot --type=png "$out" >/dev/null 2>&1
  else adb exec-out screencap -p >"$out"; fi
  echo "$out  ($(sips -g pixelWidth "$out" | awk '/pixelWidth/{print $2}')px wide — coordinates use these pixels)" ;;

*:tree) tree "${1:-}" ;;

*:tap)
  [ $# -ge 1 ] || die "usage: sim.sh tap <x> <y>  |  sim.sh tap \"Label\" [#n]"
  if is_num "$1" && is_num "${2:-}"; then x=$1; y=$2
  else nth="${2:-#1}"; xy=$(find_label "$1" "${nth#\#}"); read -r x y <<<"$xy"; fi
  read -r w h d < <(screen)
  { [ "$x" -le "$w" ] && [ "$y" -le "$h" ]; } || die "($x,$y) is off screen (${w}x${h}) — scroll first, then tree"
  if [ "$PLATFORM" = ios ]; then
    # A zero-length tap does not flip a Switch; 0.15 s behaves like a finger.
    idb_ ui tap --duration 0.15 "$(python3 -c "print(round($x/$d))")" "$(python3 -c "print(round($y/$d))")" >/dev/null
  else adb shell input tap "$x" "$y"; fi
  echo "tapped: ${x},${y}px" ;;

*:swipe)
  [ $# -ge 4 ] || die "usage: sim.sh swipe <x1> <y1> <x2> <y2> [seconds]"
  if [ "$PLATFORM" = ios ]; then
    read -r _ _ d < <(screen)
    pts=$(python3 -c "print(*[round(v/$d) for v in ($1,$2,$3,$4)])")
    # shellcheck disable=SC2086
    idb_ ui swipe ${5:+--duration "$5"} $pts >/dev/null
  else adb shell input swipe "$1" "$2" "$3" "$4" "$(python3 -c "print(int(${5:-0.3}*1000))")"; fi
  echo "swiped" ;;

ios:type)     idb_ ui text "${1:?usage: sim.sh type \"text\"}" ;;
android:type) adb shell input text "'$(printf '%s' "${1:?usage: sim.sh -a type \"text\"}" | sed 's/ /%s/g')'" ;;

*:key)
  k="${1:?usage: sim.sh key enter|delete|back|<code>}"
  if [ "$PLATFORM" = ios ]; then
    case "$k" in enter) k=40;; delete) k=42;; back|esc) k=41;; esac
    idb_ ui key "$k"
  else
    case "$k" in enter) k=66;; delete) k=67;; back|esc) k=4;; esac
    adb shell input keyevent "$k"
  fi ;;

ios:dark|ios:light)         xcrun simctl ui "$UDID" appearance "$cmd" ;;
android:dark|android:light) adb shell cmd uimode night "$([ "$cmd" = dark ] && echo yes || echo no)" ;;

*:rec)
  # rec start [name] → recording; rec stop [frames] → the mp4 plus frames and a contact
  # sheet. Transitions and animations are verified on video, not on screenshots.
  mkdir -p "$SHOTS"
  case "${1:-}" in
  start|başla)
    out="$SHOTS/${2:-rec-$(date +%H%M%S)}.mp4"; echo "$out" >"$SIM_DIR/rec.path"
    if [ "$PLATFORM" = ios ]; then
      nohup xcrun simctl io "$UDID" recordVideo --force "$out" >/dev/null 2>&1 &
    else
      nohup adb shell screenrecord /sdcard/rec.mp4 >/dev/null 2>&1 &
    fi
    echo $! >"$SIM_DIR/rec.pid"; sleep 1; echo "recording → $out" ;;
  stop|dur)
    [ -f "$SIM_DIR/rec.pid" ] || die "no recording in progress"
    [ "$PLATFORM" = android ] && adb shell pkill -INT screenrecord
    kill -INT "$(cat "$SIM_DIR/rec.pid")" 2>/dev/null || true; sleep 2
    out=$(cat "$SIM_DIR/rec.path")
    [ "$PLATFORM" = android ] && adb pull /sdcard/rec.mp4 "$out" >/dev/null
    rm -f "$SIM_DIR/rec.pid" "$SIM_DIR/rec.path"
    echo "video: $out"
    # Models read images, not video: frames + one contact sheet to open with Read.
    swift -suppress-warnings "$HERE/frames.swift" "$out" "${out%.mp4}-frames" "${2:-12}" ;;
  *) die "usage: sim.sh rec start [name] | sim.sh rec stop [frames=12]" ;;
  esac ;;

ios:log)
  need_bundle
  xcrun simctl spawn "$UDID" log show --last 2m --style compact \
    --predicate "process == \"$(ios_exe)\"" 2>/dev/null | tail -n "${1:-80}" ;;
android:log)
  need_bundle
  pid=$(adb shell pidof "$ANDROID_ID" | tr -d '\r'); [ -n "$pid" ] || die "$ANDROID_ID is not running"
  adb logcat -d --pid="$pid" | tail -n "${1:-80}" ;;

*)
  cat <<'EOF'
sim.sh — drives the iOS Simulator / Android emulator. Coordinates are ALWAYS screenshot pixels.
For Android put -a before any command:   sim.sh -a shot login

  setup                     one-time install (idb)
  boot [device|avd]         boot (iOS: "iPhone 17 Pro"; Android: first AVD)
  install <App.app|apk>     install
  launch | kill             (re)launch | quit
  open <scheme://path>      deeplink — go STRAIGHT to a screen
  shot [name]               screenshot → .sim/shots/name.png  (then open it with Read)
  tree [filter]             on-screen elements: "x,y  type  label"
  tap <x> <y> | tap "Label" [#n]
  swipe <x1> <y1> <x2> <y2> [s]
  type "text"               type (tap the field first)
  key enter|delete|back     key press
  dark | light              appearance
  rec start [name] | rec stop [n]   video → n frames + one contact sheet (sheet.png) to read
  log [lines]               app logs

Project settings in <project>/.sim/config (written automatically from the project on first run):
  BUNDLE_ID=com.company.app   # if the Android package differs: ANDROID_ID=...
  DEVICE="iPhone 17 Pro"      # AVD=Pixel_8_API_36
EOF
  ;;
esac
