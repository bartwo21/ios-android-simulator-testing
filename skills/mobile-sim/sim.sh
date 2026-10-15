#!/usr/bin/env bash
# mobile-sim — iOS simülatörünü ve Android emülatörünü AYNI komutlarla sürer.
#   iOS:     xcrun simctl (her Mac'te var) + fb-idb (gerçek dokunuş/jest)
#   Android: adb (+ emulator)
#
#   sim.sh <komut> ...      → iOS
#   sim.sh -a <komut> ...   → Android
#
# Kurallar:
#  · Koordinat HER ZAMAN ekran görüntüsü PİKSELİDİR. iOS'ta idb nokta (point)
#    ister; dönüşümü script yapar. Android zaten pikseldir.
#  · `tree` yalnız EKRANDAKİ öğeleri basar; `tap` ekran dışına dokunmayı reddeder.
#    (Ekran dışı bir koordinat bir keresinde "hesabı sil"e denk geldi.)
#  · Proje ayarı .sim/config'ten gelir (BUNDLE_ID, DEVICE, AVD, ANDROID_ID).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="${SIM_DIR:-.sim}"
SHOTS="$SIM_DIR/shots"
[ -f "$SIM_DIR/config" ] && . "$SIM_DIR/config"
DEVICE="${DEVICE:-iPhone 17 Pro}"
AVD="${AVD:-}"
ANDROID_ID="${ANDROID_ID:-${BUNDLE_ID:-}}"   # Android paket adı farklıysa config'te ver
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

PLATFORM=ios
[ "${1:-}" = "-a" ] && { PLATFORM=android; shift; }

die() { echo "sim: $*" >&2; exit 1; }
need_bundle() { [ -n "${BUNDLE_ID:-}" ] || die "BUNDLE_ID yok — .sim/config yaz (bkz. sim.sh help)"; }
is_num() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ════════════════════════════ iOS ════════════════════════════

IDB="$HERE/venv/bin/idb"
[ -x "$IDB" ] || IDB="$(command -v idb || true)"

idb_() {
  [ -n "$IDB" ] || die "idb yok — bir kez çalıştır: sim.sh setup"
  # Simülatör yeniden başlayınca idb eski companion soketine bağlanmaya çalışır
  # ("Failed to connect to companion"). idb kill durumu sıfırlar; bir kez dene.
  local out
  if out=$("$IDB" "$@" --udid "$UDID" 2>&1); then printf '%s' "$out"; return; fi
  if [[ "$out" == *"Failed to connect to companion"* ]]; then
    "$IDB" kill >/dev/null 2>&1 || true
    "$IDB" "$@" --udid "$UDID"; return
  fi
  printf '%s\n' "$out" >&2; return 1
}

resolve_udid() {
  [ -n "${IDB_UDID:-}" ] && { echo "$IDB_UDID"; return; }
  xcrun simctl list devices booted -j | DEVICE="$DEVICE" python3 -c '
import json, os, sys
booted = [x for rt in json.load(sys.stdin)["devices"].values() for x in rt]
if not booted: sys.exit("sim: açık simülatör yok — önce: sim.sh boot")
if len(booted) == 1: print(booted[0]["udid"]); raise SystemExit
hit = [x for x in booted if x["name"] == os.environ["DEVICE"]]
if not hit: sys.exit("sim: birden çok simülatör açık (%s), DEVICE=%s yok" % (", ".join(x["name"] for x in booted), os.environ["DEVICE"]))
print(hit[0]["udid"])'
}

# "genişlik yükseklik yoğunluk" (piksel). idb describe tek gerçek kaynak.
ios_screen() {
  idb_ describe --json | python3 -c 'import json,sys; s=json.load(sys.stdin)["screen_dimensions"]; print(s["width"], s["height"], s["density"])'
}

# iOS "Open in <app>?" onayı: her deeplink'te çıkar ve SpringBoard'a ait olduğu
# için tree'de görünmez. Expo CLI'nin yaptığı gibi şemayı önceden onayla.
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

ios_exe() {  # uygulamanın süreç adı (log filtresi için)
  local app; app=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" 2>/dev/null) || die "$BUNDLE_ID kurulu değil"
  /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Info.plist"
}

# ═════════════════════════ Android ═══════════════════════════

android_screen() {  # "genişlik yükseklik 1"
  adb shell wm size | awk -F'[ x]' '/Physical/{w=$(NF-1); h=$NF} /Override/{ow=$(NF-1); oh=$NF} END{print (ow?ow:w), (oh?oh:h), 1}'
}

android_tree_raw() {
  # Eski dump'ı sil: animasyon varken dump başarısız olur ve cat ÖNCEKİ dosyayı döndürür.
  local i out
  for i in 1 2 3 4; do
    adb shell rm -f /sdcard/ui.xml
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
    out=$(adb exec-out cat /sdcard/ui.xml 2>/dev/null || true)
    [[ "$out" == "<?xml"* ]] && { printf '%s' "$out"; return; }
    sleep 1
  done
}

# ═════════════════════════ ortak ═════════════════════════════

screen() { if [ "$PLATFORM" = ios ]; then ios_screen; else android_screen; fi; }

# Ekrandaki öğeler: "x,y<TAB>tip<TAB>etiket" (piksel, merkez). Ekran dışındakiler atlanır.
tree() {
  local needle="${1:-}" scr; scr=$(screen)
  if [ "$PLATFORM" = ios ]; then
    idb_ ui describe-all --json 2>/dev/null | FMT=ios S="$scr" F="$needle" python3 "$HERE/tree.py"
  else
    android_tree_raw | FMT=android S="$scr" F="$needle" python3 "$HERE/tree.py"
  fi
}

# Etikete dokun: önce tam eşleşme, yoksa içeren. Birden çoksa ilki (n. için: tap "X" #2).
find_label() {
  local label="$1" nth="${2:-1}" rows
  rows=$(tree "$label" | L="$label" python3 -c '
import os, sys
l = os.environ["L"].lower(); rows = [r.rstrip("\n") for r in sys.stdin if r.strip()]
exact = [r for r in rows if r.split("\t")[2].lower() == l]
seen, out = set(), []
for r in exact or rows:  # Button ve içindeki yazı aynı yerde: tek aday
    k = tuple(int(v) // 40 for v in r.split("\t")[0].split(","))
    if k not in seen: seen.add(k); out.append(r)
print("\n".join(out))')
  [ -n "$rows" ] || die "ekranda \"$label\" yok — sim.sh tree ile bak"
  local n; n=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
  [ "$n" -gt 1 ] && printf '%s\n' "$rows" | sed 's/^/  aday: /' >&2
  printf '%s\n' "$rows" | sed -n "${nth}p" | cut -f1 | tr ',' ' '
}

cmd="${1:-help}"; shift || true
[ "$PLATFORM" = ios ] && [[ "$cmd" != boot && "$cmd" != help && "$cmd" != setup ]] && UDID=$(resolve_udid)

case "$PLATFORM:$cmd" in

*:setup)
  # iOS dokunuşu için idb: companion brew'dan, istemci bu klasördeki venv'e.
  command -v idb_companion >/dev/null || { echo "→ brew tap facebook/fb && brew install idb-companion"; brew tap facebook/fb && brew install idb-companion; }
  [ -x "$HERE/venv/bin/idb" ] || { /usr/bin/python3 -m venv "$HERE/venv" && "$HERE/venv/bin/pip" install -q fb-idb; }
  "$HERE/venv/bin/idb" --help >/dev/null && echo "hazır: idb kurulu"
  command -v adb >/dev/null && echo "hazır: adb bulundu (Android)" || echo "Android için: Android Studio kur (adb onunla gelir)" ;;

ios:boot)
  name="${1:-$DEVICE}"
  udid=$(xcrun simctl list devices available -j | NAME="$name" python3 -c '
import json, os, sys
hit = [x for rt in json.load(sys.stdin)["devices"].values() for x in rt if x["name"] == os.environ["NAME"]]
if not hit: sys.exit("sim: \"%s\" adlı simülatör yok (xcrun simctl list devices)" % os.environ["NAME"])
print(sorted(hit, key=lambda x: x["udid"])[-1]["udid"])')
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a Simulator
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  echo "$udid" ;;
android:boot)
  adb get-state >/dev/null 2>&1 && { echo "emülatör zaten açık"; exit 0; }
  avd="${1:-$AVD}"; [ -n "$avd" ] || avd=$(emulator -list-avds | head -1)
  [ -n "$avd" ] || die "AVD yok — Android Studio › Device Manager'dan bir tane oluştur"
  mkdir -p "$SIM_DIR"
  nohup emulator -avd "$avd" -no-snapshot-save >"$SIM_DIR/emulator.log" 2>&1 &
  adb wait-for-device
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
  echo "açıldı: $avd" ;;

ios:install)    xcrun simctl install "$UDID" "${1:?kullanım: sim.sh install <App.app>}"; echo "kuruldu" ;;
android:install) adb install -r "${1:?kullanım: sim.sh -a install <app.apk>}" ;;

ios:launch)
  need_bundle
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" ;;
android:launch)
  need_bundle
  adb shell am force-stop "$ANDROID_ID"
  adb reverse tcp:"${METRO_PORT:-8081}" tcp:"${METRO_PORT:-8081}" >/dev/null 2>&1 || true  # emülatör Metro'yu görsün
  act=$(adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$ANDROID_ID" | tail -1 | tr -d '\r')
  [[ "$act" == */* ]] || die "$ANDROID_ID kurulu değil"
  adb shell am start -n "$act" >/dev/null
  echo "başlatıldı: $ANDROID_ID" ;;

ios:kill)     need_bundle; xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true ;;
android:kill) need_bundle; adb shell am force-stop "$ANDROID_ID" ;;

ios:open)
  url="${1:?kullanım: sim.sh open <scheme://yol>}"
  ios_approve_scheme "$url"
  xcrun simctl openurl "$UDID" "$url"; echo "açıldı: $url" ;;
android:open)
  url="${1:?kullanım: sim.sh -a open <scheme://yol>}"
  adb shell am start -a android.intent.action.VIEW -d "'$url'" >/dev/null 2>&1; echo "açıldı: $url" ;;

*:shot)
  mkdir -p "$SHOTS"
  out="$SHOTS/${1:-$(date +%H%M%S)}$([ "$PLATFORM" = android ] && echo -android || true).png"
  if [ "$PLATFORM" = ios ]; then xcrun simctl io "$UDID" screenshot --type=png "$out" >/dev/null 2>&1
  else adb exec-out screencap -p >"$out"; fi
  echo "$out  ($(sips -g pixelWidth "$out" | awk '/pixelWidth/{print $2}')px genişlik — koordinatlar bu piksellerle)" ;;

*:tree) tree "${1:-}" ;;

*:tap)
  [ $# -ge 1 ] || die "kullanım: sim.sh tap <x> <y>  |  sim.sh tap \"Etiket\" [#n]"
  if is_num "$1" && is_num "${2:-}"; then x=$1; y=$2
  else nth="${2:-#1}"; xy=$(find_label "$1" "${nth#\#}"); read -r x y <<<"$xy"; fi
  read -r w h d < <(screen)
  { [ "$x" -le "$w" ] && [ "$y" -le "$h" ]; } || die "($x,$y) ekran dışı (${w}x${h}) — önce kaydır, sonra tree"
  if [ "$PLATFORM" = ios ]; then
    # Sıfır süreli dokunuş Switch'i çevirmez; 0.15 sn gerçek parmak gibi.
    idb_ ui tap --duration 0.15 "$(python3 -c "print(round($x/$d))")" "$(python3 -c "print(round($y/$d))")" >/dev/null
  else adb shell input tap "$x" "$y"; fi
  echo "dokunuldu: ${x},${y}px" ;;

*:swipe)
  [ $# -ge 4 ] || die "kullanım: sim.sh swipe <x1> <y1> <x2> <y2> [saniye]"
  if [ "$PLATFORM" = ios ]; then
    read -r _ _ d < <(screen)
    pts=$(python3 -c "print(*[round(v/$d) for v in ($1,$2,$3,$4)])")
    # shellcheck disable=SC2086
    idb_ ui swipe ${5:+--duration "$5"} $pts >/dev/null
  else adb shell input swipe "$1" "$2" "$3" "$4" "$(python3 -c "print(int(${5:-0.3}*1000))")"; fi
  echo "kaydırıldı" ;;

ios:type)     idb_ ui text "${1:?kullanım: sim.sh type \"metin\"}" ;;
android:type) adb shell input text "'$(printf '%s' "${1:?kullanım: sim.sh -a type \"metin\"}" | sed 's/ /%s/g')'" ;;

*:key)
  k="${1:?kullanım: sim.sh key enter|delete|back|<kod>}"
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
  # rec başla [ad] → kayıt; rec dur → dosyayı yazar. Geçiş/animasyon ekran görüntüsüyle doğrulanmaz.
  mkdir -p "$SHOTS"
  case "${1:-}" in
  başla|start)
    out="$SHOTS/${2:-rec-$(date +%H%M%S)}.mp4"; echo "$out" >"$SIM_DIR/rec.path"
    if [ "$PLATFORM" = ios ]; then
      nohup xcrun simctl io "$UDID" recordVideo --force "$out" >/dev/null 2>&1 &
    else
      nohup adb shell screenrecord /sdcard/rec.mp4 >/dev/null 2>&1 &
    fi
    echo $! >"$SIM_DIR/rec.pid"; sleep 1; echo "kayıt başladı → $out" ;;
  dur|stop)
    [ -f "$SIM_DIR/rec.pid" ] || die "süren kayıt yok"
    [ "$PLATFORM" = android ] && adb shell pkill -INT screenrecord
    kill -INT "$(cat "$SIM_DIR/rec.pid")" 2>/dev/null || true; sleep 2
    out=$(cat "$SIM_DIR/rec.path")
    [ "$PLATFORM" = android ] && adb pull /sdcard/rec.mp4 "$out" >/dev/null
    rm -f "$SIM_DIR/rec.pid" "$SIM_DIR/rec.path"
    echo "$out"
    command -v ffmpeg >/dev/null && echo "kareler: ffmpeg -i $out -vf fps=10 $SHOTS/kare-%03d.png" ;;
  *) die "kullanım: sim.sh rec başla [ad] | sim.sh rec dur" ;;
  esac ;;

ios:log)
  need_bundle
  xcrun simctl spawn "$UDID" log show --last 2m --style compact \
    --predicate "process == \"$(ios_exe)\"" 2>/dev/null | tail -n "${1:-80}" ;;
android:log)
  need_bundle
  pid=$(adb shell pidof "$ANDROID_ID" | tr -d '\r'); [ -n "$pid" ] || die "$ANDROID_ID çalışmıyor"
  adb logcat -d --pid="$pid" | tail -n "${1:-80}" ;;

*)
  cat <<'EOF'
mobile-sim — simülatörü/emülatörü sürer. Koordinatlar HER ZAMAN ekran görüntüsü pikselidir.
Android için her komutun önüne -a:   sim.sh -a shot giris

  setup                     bir kerelik kurulum (idb)
  boot [cihaz|avd]          aç (iOS: "iPhone 17 Pro"; Android: ilk AVD)
  install <App.app|apk>     kur
  launch | kill             başlat/yeniden başlat | kapat
  open <scheme://yol>       deeplink — ekrana DOĞRUDAN git
  shot [ad]                 ekran görüntüsü → .sim/shots/ad.png  (sonra Read ile AÇ)
  tree [filtre]             ekrandaki öğeler: "x,y  tip  etiket"
  tap <x> <y> | tap "Etiket" [#n]
  swipe <x1> <y1> <x2> <y2> [sn]
  type "metin"              yaz (önce alana dokun)
  key enter|delete|back     tuş
  dark | light              görünüm
  rec başla [ad] | rec dur  video (geçiş/animasyon için)
  log [satır]               uygulama logları

Proje ayarı <proje>/.sim/config:
  BUNDLE_ID=com.firma.app   # Android paketi farklıysa: ANDROID_ID=...
  DEVICE="iPhone 17 Pro"    # AVD=Pixel_8_API_36
EOF
  ;;
esac
