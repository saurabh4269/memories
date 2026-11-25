#!/usr/bin/env python3
"""Download CC0 / public-domain group photos from Wikimedia Commons (thumbnails, 1600px wide).
Usage: python3 fetch_photos.py <out_dir> [max]   Writes <out_dir>/ATTRIBUTION.tsv."""
import json, os, sys, time, urllib.parse, urllib.request
out = sys.argv[1]; maxn = int(sys.argv[2]) if len(sys.argv) > 2 else 40
os.makedirs(out, exist_ok=True)
UA = {"User-Agent": "memories-hackathon-demo/0.1 (CC0 test photos)"}
queries = ['"group photo" filetype:bitmap cc0', '"family" "group" filetype:bitmap cc0', 'diwali filetype:bitmap cc0']
seen, rows = set(), []
for q in queries:
    params = {"action": "query", "format": "json", "generator": "search", "gsrnamespace": "6", "gsrsearch": q,
              "gsrlimit": "50", "prop": "imageinfo", "iiprop": "url|size|extmetadata", "iiurlwidth": "1600",
              "iiextmetadatafilter": "LicenseShortName"}
    req = urllib.request.Request("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params), headers=UA)
    pages = json.load(urllib.request.urlopen(req, timeout=30)).get("query", {}).get("pages", {})
    for p in pages.values():
        ii = (p.get("imageinfo") or [{}])[0]
        lic = ii.get("extmetadata", {}).get("LicenseShortName", {}).get("value", "")
        url = ii.get("thumburl") or ii.get("url")
        if lic not in ("CC0", "Public domain") or not url or p["title"] in seen: continue
        if not url.lower().split("?")[0].endswith((".jpg", ".jpeg")): continue
        seen.add(p["title"])
        fn = os.path.join(out, f"cc0_{len(rows):03d}.jpg")
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except Exception as e:
            print("skip", p["title"], e); continue
        open(fn, "wb").write(data); rows.append((os.path.basename(fn), lic, p["title"], ii.get("descriptionurl", "")))
        print(len(rows), p["title"]); time.sleep(0.3)
        if len(rows) >= maxn: break
    if len(rows) >= maxn: break
with open(os.path.join(out, "ATTRIBUTION.tsv"), "w") as f:
    for r in rows: f.write("\t".join(r) + "\n")
print("downloaded", len(rows))
