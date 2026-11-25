from memories.coach import HACKATHON_SHOTS, hackathon_matches


def row(i, act="", cap="", tf=0, t="2026-11-25T12:00:00", **an):
    return {"id": i, "time": t, "team_faces": tf, "analysis": {"activity": act, "caption": cap, **an}}


def test_hackathon_coverage_rules():
    rows = [
        row("talk", "stage_talk", "A speaker on stage", tf=0),            # someone else's talk: not our demo
        row("demo", "stage_talk", "Team presenting their demo on stage", tf=0),
        row("booth", "booth_or_sponsor", "Team at the Flagsmith booth", tf=1),
        row("booth2", "booth_or_sponsor", "Visitors at the Oracle booth", tf=1),
        row("code_day", "coding_closeup", "Code on a screen", t="2026-11-25T15:00:00"),
        row("code_night", "team_working_at_laptops", "Team coding", t="2026-11-25T23:30:00"),
    ]
    m = hackathon_matches(rows, ["flagsmith", "nudgebee", "sarvam"])
    assert set(m) == {s[0] for s in HACKATHON_SHOTS}
    assert m["demo_stage"] == ["demo"]
    assert m["sponsor_booth"] == ["booth"]
    assert m["late_night"] == ["code_night"]
    assert m["team_group"] == []


def test_group_photo_needs_pose_or_team():
    rows = [row("a", "team_group_pose"), row("b", "other", "Friends posing for a group photo", tf=2),
            row("c", "audience", "Crowd posing", tf=0)]
    assert hackathon_matches(rows, [])["team_group"] == ["a", "b"]
