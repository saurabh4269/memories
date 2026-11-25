"""Upload data/samples/* to Immich and create a test album (times spread over one evening)."""
import asyncio
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from memories.immich import ImmichClient


async def main(name: str):
    c = ImmichClient()
    files = sorted(p for p in (Path(__file__).resolve().parents[1] / "data/samples").iterdir() if p.suffix in (".jpg", ".webm", ".mp4"))
    base = datetime(2026, 11, 8, 18, 30, tzinfo=timezone(timedelta(hours=5, minutes=30)))
    ids = []
    for i, f in enumerate(files):
        r = await c.upload(str(f), created=base + timedelta(minutes=7 * i))
        ids.append(r["id"])
        print(f.name, r.get("status"))
    alb = await c.create_album(name, ids, description="Diwali night at home with the family: rangoli, diyas, Lakshmi puja aarti, sweets, phuljhadi.")
    print("ALBUM", alb["id"])
    await c.aclose()

asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "Diwali 2026 test"))
