"""EDL (editor_api.build_edl output) -> OpenTimelineIO timeline (JSON string)."""
from __future__ import annotations

import opentimelineio as otio

RATE = 30.0


def _rt(seconds: float) -> otio.opentime.RationalTime:
    return otio.opentime.RationalTime(round(float(seconds) * RATE), RATE)


def _range(start_s: float, dur_s: float) -> otio.opentime.TimeRange:
    return otio.opentime.TimeRange(_rt(start_s), _rt(dur_s))


def build_timeline(edl: dict, name: str = "memories") -> otio.schema.Timeline:
    tl = otio.schema.Timeline(name=name)
    tl.global_start_time = _rt(0)
    tl.metadata["memories"] = {"cut": edl.get("cut"), "title": edl.get("title"), "duration_s": edl.get("duration_s"),
                               "transitions": edl.get("transitions")}
    video = otio.schema.Track(name="Video", kind=otio.schema.TrackKind.Video)
    for i, c in enumerate(edl.get("clips", [])):
        is_video = c.get("type") == "video"
        src_start = float(c.get("in_s") or 0.0) if is_video else 0.0
        ref = otio.schema.ExternalReference(target_url=c["media_url"])
        if is_video and c.get("source_duration_s"):
            ref.available_range = _range(0, float(c["source_duration_s"]))
        clip = otio.schema.Clip(name=f"{i + 1:02d} {c['asset_id'][:8]}", media_reference=ref,
                                source_range=_range(src_start, float(c.get("visible_s") or c["duration_s"])))
        clip.metadata["memories"] = {k: c.get(k) for k in ("asset_id", "type", "poster_url", "caption", "kenburns",
                                                            "start_s", "hold_s", "in_s", "out_s")}
        video.append(clip)
    for cap in edl.get("captions", []):
        if not cap.get("text"):
            continue
        video.markers.append(otio.schema.Marker(
            name=cap["text"], marked_range=_range(cap["start_s"], cap["duration_s"]),
            color=otio.schema.MarkerColor.YELLOW, metadata={"memories": {"kind": "caption"}}))
    # xfade overlaps are not modelled as otio Transitions: each clip keeps its visible length so clip k starts
    # exactly at start_s and the track length equals duration_s (transition info is in timeline metadata)
    tl.tracks.append(video)
    music = edl.get("music") or {}
    if music.get("url"):
        audio = otio.schema.Track(name="Music", kind=otio.schema.TrackKind.Audio)
        ac = otio.schema.Clip(name=music.get("title") or "music",
                              media_reference=otio.schema.ExternalReference(target_url=music["url"]),
                              source_range=_range(float(music.get("start_s") or 0.0), float(edl.get("duration_s") or 0.0)))
        ac.metadata["memories"] = {"bpm": music.get("bpm"), "attribution": music.get("attribution")}
        audio.append(ac)
        tl.tracks.append(audio)
    return tl


def to_otio_json(edl: dict, name: str = "memories") -> str:
    s = otio.adapters.write_to_string(build_timeline(edl, name), "otio_json")
    otio.adapters.read_from_string(s, "otio_json")  # validate it loads
    return s
