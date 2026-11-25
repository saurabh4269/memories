"""End-to-end CLI: python -m memories.demo --album <id> --prompt "..." --dest wa_status [--final]"""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import time

from . import flags, pipeline
from .immich import ImmichClient
from .sarvam import SarvamClient


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--album", required=True)
    ap.add_argument("--prompt", default="")
    ap.add_argument("--dest", default="wa_status", choices=["wa_status", "insta_reel", "insta_story"])
    ap.add_argument("--member", default=None)
    ap.add_argument("--language", default=None)
    ap.add_argument("--audio", default=None, help="optional voice prompt file")
    ap.add_argument("--final", action="store_true", help="also render both finals (1080x1920)")
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    logging.basicConfig(level=logging.INFO if a.v else logging.WARNING, format="%(asctime)s %(name)s: %(message)s")
    immich, sarvam = ImmichClient(), SarvamClient()
    audio = None
    if a.audio:
        audio = (open(a.audio, "rb").read(), "audio/" + a.audio.rsplit(".", 1)[-1], a.audio.rsplit("/", 1)[-1])
    t0 = time.perf_counter()
    reel = await pipeline.create_reel(immich, sarvam, album_id=a.album, prompt=a.prompt, destination=a.dest,
                                      member_name=a.member, language=a.language, audio=audio, speculative_final=False)
    t_prev = time.perf_counter() - t0
    out = pipeline.public_reel(reel)
    print(json.dumps({k: out[k] for k in ("reel_id", "strategy", "label", "mode")}, indent=2))
    for i, c in enumerate(out["cuts"]):
        print(f"\n[cut {i}] {c['title']} ({c['source']}, {c['total_s']} s, {len(c['clips'])} clips, music: {c['music']['title']})")
        print(f"  why: {c['why']}\n  preview: {c['preview_url']}")
        r = reel["cuts"][i].get("preview") or {}
        print(f"  local: {r.get('path')}")
    print("\nstages (ms):", json.dumps(reel["timings"]["stages_ms"]))
    print("sarvam calls:", ", ".join(f"{c['kind']}:{c['model']} {c['ms']}ms{'' if c['ok'] else ' FAIL'}" for c in reel["timings"]["sarvam_calls"]))
    print("preview render:", json.dumps(reel["timings"]["render"]))
    print(f"preview path total: {t_prev:.1f} s")
    if a.plan_notes if hasattr(a, "plan_notes") else False:
        pass
    if reel.get("plan_info", {}).get("notes"):
        print("plan notes:", reel["plan_info"]["notes"][:10])
    if a.final:
        for i in range(len(reel["cuts"])):
            t1 = time.perf_counter()
            res = await pipeline.render_final(immich, reel, i)
            print(f"final cut {i}: {time.perf_counter() - t1:.1f} s -> {res.get('path')} {json.dumps(res.get('timings'))}")
    flags.close()
    await immich.aclose()
    await sarvam.aclose()


if __name__ == "__main__":
    asyncio.run(main())
