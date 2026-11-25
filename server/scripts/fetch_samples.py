"""Download CC-licensed Diwali photos/videos from Wikimedia Commons into data/samples (+ credits.json)."""
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data/samples"
UA = {"User-Agent": "memories-hackathon-sample-fetch/0.1"}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()


def search(q, ns_filetype, n):
    params = {"action": "query", "format": "json", "generator": "search", "gsrsearch": q, "gsrnamespace": "6",
              "gsrlimit": str(n), "prop": "imageinfo", "iiprop": "url|extmetadata|mime|size", "iiurlwidth": "1600"}
    d = json.loads(get("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)))
    return list((d.get("query") or {}).get("pages", {}).values())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    credits = []
    want_photos, want_videos = int(sys.argv[1]) if len(sys.argv) > 1 else 22, 2
    pages = search("Diwali family filetype:bitmap", "bitmap", 50) + search("Diwali diya rangoli filetype:bitmap", "bitmap", 40)
    vids = search("Diwali fireworks filetype:video", "video", 15)
    seen = set()
    n_p = n_v = 0
    for p in pages + vids:
        ii = (p.get("imageinfo") or [{}])[0]
        meta = ii.get("extmetadata") or {}
        lic = (meta.get("LicenseShortName") or {}).get("value", "")
        if not any(k in lic for k in ("CC0", "CC BY", "Public domain", "CC-BY")) or p["title"] in seen:
            continue
        seen.add(p["title"])
        mime = ii.get("mime", "")
        is_video = mime.startswith("video/")
        if is_video:
            if n_v >= want_videos or ii.get("size", 0) > 40e6:
                continue
            url, ext = ii["url"], "." + ii["url"].rsplit(".", 1)[-1]
        else:
            if n_p >= want_photos or mime not in ("image/jpeg",):
                continue
            url, ext = ii.get("thumburl") or ii["url"], ".jpg"
        name = f"{'v' if is_video else 'p'}{(n_v if is_video else n_p) + 1:02d}{ext}"
        try:
            (OUT / name).write_bytes(get(url))
        except Exception as e:
            print("fail", p["title"], e)
            continue
        if is_video:
            n_v += 1
        else:
            n_p += 1
        credits.append({"file": name, "title": p["title"], "licence": lic,
                        "artist": (meta.get("Artist") or {}).get("value", "")[:200],
                        "source": ii.get("descriptionurl")})
        print(name, lic, p["title"][:60])
    (OUT / "credits.json").write_text(json.dumps(credits, indent=2))


main()
