# Parser behind `sim.sh tree`. stdin: idb describe-all JSON on iOS, uiautomator XML on
# Android. Output: "x,y<TAB>type<TAB>label" — centre, in PIXELS, on-screen elements only.
import json, os, re, sys
import xml.etree.ElementTree as ET

w, h, d = (float(v) for v in os.environ["S"].split())
needle = os.environ.get("F", "").lower()
raw = sys.stdin.read().strip()
if not raw:
    sys.exit("sim: empty element tree — is the app in front? (iOS system dialogs never show up here)")

rows = []
if os.environ["FMT"] == "ios":
    for el in json.loads(raw):
        f = el.get("frame") or {}
        label = str(el.get("AXLabel") or el.get("AXValue") or "").strip()
        if f and label:
            rows.append(((f["x"] + f["width"] / 2) * d, (f["y"] + f["height"] / 2) * d, el.get("type", "?"), label))
else:
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        sys.exit("sim: could not dump the screen — something may be animating, try again")
    for n in root.iter("node"):
        label = (n.get("text") or n.get("content-desc") or "").replace("\n", " ").strip()
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
        if label and m:
            x1, y1, x2, y2 = map(int, m.groups())
            rows.append(((x1 + x2) / 2, (y1 + y2) / 2, n.get("class", "?").split(".")[-1], label))

for x, y, kind, label in rows:
    if not (0 <= x <= w and 0 <= y <= h):
        continue  # off screen / a background tab — cannot be tapped
    if needle and needle not in label.lower():
        continue
    print("%d,%d\t%s\t%s" % (x, y, kind, label))
