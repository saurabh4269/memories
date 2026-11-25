from memories.render import (PROFILES, build_concat_cmd, build_join_cmd, build_photo_segment_cmd,
                             build_video_segment_cmd, profile_from, redact, xfade_offsets)

P = PROFILES["preview"]


def test_video_cmd_input_seeking_before_input():
    cmd = build_video_segment_cmd("https://x/api/assets/1/original", "o.mp4", P, 12.5, 3.0, None,
                                  headers={"x-api-key": "SECRET"})
    i = cmd.index("-i")
    assert cmd.index("-ss") < i and cmd.index("-t") < i
    assert cmd[cmd.index("-ss") + 1] == "12.500"
    assert "SECRET" not in redact(cmd)
    fc = cmd[cmd.index("-filter_complex") + 1]
    assert f"scale={P.w}:{P.h}" in fc and "tpad" in fc
    assert cmd[cmd.index("-r") + 1] == str(P.fps)


def test_photo_cmd_frames_and_caption():
    cmd = build_photo_segment_cmd("c.jpg", "o.mp4", P, 2.5, "cap.png")
    assert cmd[cmd.index("-frames:v") + 1] == str(round(2.5 * P.fps))
    fc = cmd[cmd.index("-filter_complex") + 1]
    assert "zoompan" in fc and "overlay" in fc and f"s={P.w}x{P.h}" in fc


def test_xfade_offsets():
    assert xfade_offsets([2.35, 2.35, 2.0], 0.35) == [2.0, 4.0]


def test_join_cmd_total_and_music():
    cmd = build_join_cmd(["a.mp4", "b.mp4", "c.mp4"], [2.35, 2.35, 2.0], "out.mp4", P, "m.mp3", 0.2, t=0.35, encoder="libx264")
    assert cmd[cmd.index("-t") + 1] == "6.000"
    fc = cmd[cmd.index("-filter_complex") + 1]
    assert fc.count("xfade") == 2 and "afade=t=out" in fc
    assert "+faststart" in cmd and "libx264" in cmd


def test_single_segment_join():
    cmd = build_join_cmd(["a.mp4"], [3.0], "out.mp4", P, None, encoder="libx264")
    assert "xfade" not in cmd[cmd.index("-filter_complex") + 1]


def test_concat_copy():
    cmd = build_concat_cmd("l.txt", 20.0, "o.mp4", P, "m.mp3")
    assert cmd[cmd.index("-c:v") + 1] == "copy" and "concat" in cmd


def test_profile_overrides():
    p = profile_from("final", {"final": {"w": 720, "h": 1280}, "transitions": "cut"})
    assert (p.w, p.h, p.transitions) == (720, 1280, "cut")
