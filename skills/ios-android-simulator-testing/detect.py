# Finds the app id in a project (run by sim.sh when .sim/config is missing).
# Prints config lines: BUNDLE_ID=... and, if the Android package differs, ANDROID_ID=...
import glob, json, os, re

root = os.environ["ROOT"]
ios = android = None

try:  # Expo
    expo = json.load(open(os.path.join(root, "app.json"))).get("expo", {})
    ios = (expo.get("ios") or {}).get("bundleIdentifier")
    android = (expo.get("android") or {}).get("package")
except (OSError, ValueError):
    pass

if not ios:  # Xcode project (native, React Native, Flutter): the shortest plain id is the app
    ids = set()
    for p in glob.glob(os.path.join(root, "ios", "*.xcodeproj", "project.pbxproj")) + glob.glob(os.path.join(root, "*.xcodeproj", "project.pbxproj")):
        ids |= set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([\w.-]+)\"?;", open(p, errors="ignore").read()))
    ids = [i for i in ids if "test" not in i.lower()]
    ios = min(ids, key=len) if ids else None

if not android:  # Android gradle (Groovy or Kotlin DSL)
    for p in glob.glob(os.path.join(root, "android", "app", "build.gradle*")) + glob.glob(os.path.join(root, "app", "build.gradle*")):
        m = re.search(r"applicationId\s*=?\s*[\"']([\w.]+)[\"']", open(p, errors="ignore").read())
        if m:
            android = m.group(1); break

bundle = ios or android
if bundle:
    print("BUNDLE_ID=" + bundle)
    if android and android != bundle:
        print("ANDROID_ID=" + android)
