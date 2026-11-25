from memories import director
from memories.director import DESTINATIONS, clip_len, fallback_plan, snap, validate_edl


def rows(n=14, video_every=5):
    out = []
    for i in range(n):
        is_v = i % video_every == 4
        out.append({
            "id": f"id{i}", "alias": f"A{i + 1}", "type": "VIDEO" if is_v else "IMAGE",
            "time": f"2026-11-08T19:{i * 3:02d}:00", "duration": 12.0 if is_v else 0.0, "people": [],
            "analysis": {"caption": f"shot number {i} of something unique {i * 7}", "quality": 7, "blurry": False,
                         "mood": "joyful", "is_group": i % 3 == 0},
        })
    return out


BEAT = 0.6


def test_snap():
    assert snap(2.5, 0.6, 1.2, 4.5) == 2.4
    assert snap(10, 0.6, 1.2, 4.5) <= 4.5
    assert snap(0.1, 0.6, 1.2, 4.5) == 1.2


def test_unknown_ids_blurry_and_lowq_dropped():
    r = rows()
    r[1]["analysis"]["blurry"] = True
    r[2]["analysis"]["quality"] = 2
    edl = {"cuts": [{"title": "t", "why": "w", "music_mood": "emotional", "cover_asset_id": "A1",
                     "clips": [{"asset_id": a, "hold_s": 2.4} for a in ["A1", "A2", "A3", "ZZ9", "A4", "A6", "A7", "A8", "A9"]]}]}
    cuts, notes = validate_edl(edl, r, "wa_status", BEAT)
    ids = [c["asset_id"] for c in cuts[0]["clips"]]
    assert "id1" not in ids and "id2" not in ids
    assert any("unknown" in n for n in notes)
    assert len(cuts) == 2  # second filled from fallback
    assert cuts[1]["source"] == "auto"


def test_video_times_clamped():
    r = rows()
    edl = {"cuts": [{"title": "t", "why": "w", "music_mood": "joyful", "cover_asset_id": "A1",
                     "clips": [{"asset_id": "A5", "in_s": 11.5, "out_s": 40}, {"asset_id": "A1"}, {"asset_id": "A2"},
                               {"asset_id": "A3"}, {"asset_id": "A4"}]}]}
    cuts, _ = validate_edl(edl, r, "wa_status", BEAT)
    v = next(c for c in cuts[0]["clips"] if c["asset_id"] == "id4")
    assert 0 <= v["in_s"] < v["out_s"] <= 12.0
    assert v["out_s"] - v["in_s"] >= 1.2 - 1e-6


def test_length_fits_destination():
    r = rows(30)
    clips = [{"asset_id": f"A{i}", "hold_s": 4.5} for i in range(1, 25)]
    edl = {"cuts": [{"title": "a", "why": "", "music_mood": "joyful", "cover_asset_id": "A1", "clips": clips},
                    {"title": "b", "why": "", "music_mood": "joyful", "cover_asset_id": "A3", "clips": clips[::-1]}]}
    for dest in DESTINATIONS:
        cuts, _ = validate_edl(edl, r, dest, BEAT)
        for c in cuts:
            total = sum(clip_len(x) for x in c["clips"])
            assert DESTINATIONS[dest]["min"] - 0.01 <= total <= DESTINATIONS[dest]["max"] + 0.01, (dest, total)


def test_short_cut_extended():
    r = rows(30)
    edl = {"cuts": [{"title": "a", "why": "", "music_mood": "joyful", "cover_asset_id": "A1",
                     "clips": [{"asset_id": f"A{i}", "hold_s": 1.2} for i in (1, 2, 3)]}]}
    cuts, _ = validate_edl(edl, r, "insta_reel", BEAT)
    assert sum(clip_len(x) for x in cuts[0]["clips"]) >= 15


def test_holds_on_beat():
    r = rows()
    edl = {"cuts": [{"title": "a", "why": "", "music_mood": "joyful", "cover_asset_id": "A1",
                     "clips": [{"asset_id": f"A{i}", "hold_s": 2.0 + i * 0.13} for i in (1, 2, 3, 4, 6, 7, 8, 9)]}]}
    cuts, _ = validate_edl(edl, r, "wa_status", BEAT)
    for c in cuts[0]["clips"]:
        if c["kind"] == "photo":
            k = c["hold_s"] / BEAT
            assert abs(k - round(k)) < 1e-6


def test_near_duplicates_dropped():
    r = rows()
    r[2]["time"] = r[1]["time"]
    r[2]["analysis"]["caption"] = r[1]["analysis"]["caption"] + "!"
    edl = {"cuts": [{"title": "a", "why": "", "music_mood": "joyful", "cover_asset_id": "A1",
                     "clips": [{"asset_id": f"A{i}"} for i in (1, 2, 3, 4, 6, 7)]}]}
    cuts, notes = validate_edl(edl, r, "wa_status", BEAT)
    assert any("near-duplicate" in n for n in notes)


def test_garbage_gives_two_auto_cuts():
    cuts, _ = validate_edl("not json", rows(), "insta_story", BEAT)
    assert len(cuts) == 2 and all(c["source"] == "auto" for c in cuts)
    assert [c["asset_id"] for c in cuts[0]["clips"]] != [c["asset_id"] for c in cuts[1]["clips"]]


def test_fallback_deterministic():
    a = fallback_plan(rows(), "wa_status", BEAT)
    b = fallback_plan(rows(), "wa_status", BEAT)
    assert a == b


def test_detect_language():
    assert director.detect_language("WA status ke liye family wali, thoda emotional") == "hinglish"
    assert director.detect_language("दिवाली की रील") == "hi"
    assert director.detect_language("a fun reel of the night") == "en"


# ---- EDIT-GRAMMAR validators (qa.py / grammar.py)
from memories import grammar, qa  # noqa: E402


def test_length_window_defaults_and_prompt_override():
    assert qa.length_window("wa_status") == (15.0, 20.0, 17.5)
    assert qa.length_window("insta_story")[1] == 15.0
    lo, hi, _ = qa.length_window("wa_status", "30 sec ka status banao")
    assert hi == 30.0 and lo < hi


def test_caption_safe_area_and_face_overlap():
    assert qa.rect_inside([100, 300, 900, 400])
    assert not qa.rect_inside([0, 300, 900, 400])
    assert not qa.rect_inside([100, 1500, 900, 1700])
    assert qa.rect_overlap([0, 0, 10, 10], [5, 5, 15, 15]) == 0.25


def test_shot_value_penalises_corridor_and_empty():
    walk = {"type": "VIDEO", "analysis": {"quality": 7, "people_count": 5, "is_group": True, "mood": "joyful",
                                          "caption": "Friends walking across the red carpet", "moment_tag": "walking in"}}
    team = {"type": "IMAGE", "analysis": {"quality": 7, "people_count": 4, "is_group": True, "mood": "candid",
                                          "caption": "Teammates coding together", "moment_tag": "coding"}}
    empty = {"type": "IMAGE", "analysis": {"quality": 9, "people_count": 0, "caption": "A robot", "moment_tag": "robot"}}
    assert grammar.shot_value(team) > grammar.shot_value(walk)
    assert grammar.shot_value(team) > grammar.shot_value(empty)


def test_intent_and_title_claims():
    assert grammar.parse_intent("hackathon ki yaadein, team ke saath")["subject"] == "team"
    assert grammar.parse_intent("sirf stage aur talks")["exclusive"] == ["stage"]
    rows = [{"analysis": {"activity": "booth_or_sponsor"}, "team_score": 0}] * 4
    title, notes = grammar.check_title("Team Moments Best Hits", rows, "hinglish")
    assert title != "Team Moments Best Hits" and notes
    ok_rows = [{"analysis": {"activity": "team_working_at_laptops"}, "team_score": 5}] * 4
    assert grammar.check_title("Team ke saath", ok_rows, "hinglish")[0] == "Team ke saath"


def test_no_mixed_scripts():
    assert grammar.short_caption("Hackathon Ki Yaadें") == "Hackathon Ki"
    assert "ें" not in grammar.short_caption("Team ki यादें saath")


def test_team_people_needs_recurrence_and_team_activity():
    from memories import team
    rows = []
    for i in range(5):
        rows.append({"id": f"t{i}", "person_ids": ["me", "buddy"], "analysis": {"activity": "team_working_at_laptops", "team_work": True, "people_count": 2}})
    for i in range(4):
        rows.append({"id": f"s{i}", "person_ids": ["staff"], "analysis": {"activity": "organizer_or_staff", "people_count": 1}})
    rows.append({"id": "x", "person_ids": ["stranger"], "analysis": {"activity": "venue_or_corridor", "people_count": 3}})
    tp = team.score_rows(rows)
    assert set(tp) == {"me", "buddy"}
    assert rows[0]["team_score"] >= team.TEAM_THRESHOLD > rows[-1]["team_score"]


def test_judges_never_team_and_captions_off_by_default():
    from memories import team
    rows = [{"id": f"t{i}", "person_ids": ["me", "buddy"], "analysis": {"activity": "team_working_at_laptops", "team_work": True, "people_count": 2}} for i in range(4)]
    rows += [{"id": f"j{i}", "person_ids": ["judge"], "analysis": {"activity": "stage_talk", "people_count": 3,
              "caption": "Three judges standing, one with a mic"}} for i in range(4)]
    rows.append({"id": "j9", "person_ids": ["judge", "me"], "analysis": {"activity": "team_group_pose", "people_count": 3,
                 "caption": "man with a mic and two others standing"}})
    tp = team.score_rows(rows)
    assert "judge" not in tp
    assert not grammar.team_ok(rows[-1])
    assert not grammar.wants_captions("energetic hackathon recap")
    assert grammar.wants_captions("recap with captions in hinglish")
    assert grammar.parse_intent("team building intensely")["building"]
