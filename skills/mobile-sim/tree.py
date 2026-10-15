# sim.sh tree'nin ayrıştırıcısı. stdin: iOS'ta idb describe-all JSON'u, Android'de
# uiautomator XML'i. Çıktı: "x,y<TAB>tip<TAB>etiket" — merkez, PİKSEL, yalnız ekrandakiler.
import json, os, re, sys
import xml.etree.ElementTree as ET

w, h, d = (float(v) for v in os.environ["S"].split())
needle = os.environ.get("F", "").lower()
raw = sys.stdin.read().strip()
if not raw:
    sys.exit("sim: ekran ağacı boş — uygulama önde mi? (iOS sistem diyalogları ağaçta görünmez)")

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
        sys.exit("sim: dump alınamadı — ekranda animasyon sürüyor olabilir, tekrar dene")
    for n in root.iter("node"):
        label = (n.get("text") or n.get("content-desc") or "").replace("\n", " ").strip()
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
        if label and m:
            x1, y1, x2, y2 = map(int, m.groups())
            rows.append(((x1 + x2) / 2, (y1 + y2) / 2, n.get("class", "?").split(".")[-1], label))

for x, y, kind, label in rows:
    if not (0 <= x <= w and 0 <= y <= h):
        continue  # ekran dışı / arka sekme — dokunulamaz
    if needle and needle not in label.lower():
        continue
    print("%d,%d\t%s\t%s" % (x, y, kind, label))
