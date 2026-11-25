# Edit rubric: scoring a vertical event reel

Use this to score one reel (10-30 s, 9:16) from:
- a **frame contact sheet**: one frame per shot at its midpoint, plus frames at 0.0 s, 0.5 s, 1.0 s, 1.5 s and the last frame, with the safe-area box (x 60..950, y 250..1540) drawn as an overlay;
- **metadata**: the EDL (shot list with in/out times, asset ids, people per shot, shot size, photo/video, Ken Burns params, crop mode crop/blur-fill, transitions), the track (BPM, beat times, section markers), the caption list (text, time, bbox, font px), the loudness report, and the album inventory (people and moments available).

Rule numbers (§x.y) refer to [EDIT-GRAMMAR.md](./EDIT-GRAMMAR.md).

**Scoring:** 10 criteria, each scored 0-10, for a total of /100. Anchors are given for 3, 7 and 10. Interpolate between them. **Hard fails** cap the total at 40 no matter what else scores well: a black or blank first frame; text cut off or over a face in the hook; a duplicate shot directly adjacent; audio clipping; wrong aspect ratio or black letterbox bars.

Ship threshold for the demo: **≥ 70 total, and no criterion below 5.**

---

### 1. Hook strength (first 2 s), §2
Check: frames at 0.0, 0.5, 1.0 and 1.5 s, the first shot's type and score, title timing, and the first cut time.
- **3:** Opens on a static, generic or dark frame (an empty room, a blurry wide shot) or a fade from black. No text until 1.5 s or later, or no text at all. First cut after 3 s.
- **7:** Opens on a good people or detail shot with some motion or a Ken Burns punch. Title appears by 0.5 s. First cut by 2 s. But this isn't the single best moment in the album.
- **10:** Frame 0 is the album's peak visual (a firework burst, a laughing face, a diya lighting) with motion. Title of 2-5 words is readable by 0.3 s. First cut at 1.5 s or earlier, on a downbeat. You'd stop scrolling for it with the sound off.

### 2. Pacing and beat sync, §3
Check: the shot durations list, cut times against beat times, and the duration variance.
- **3:** Uniform durations (every shot the same length) or random lengths that ignore the music. More than 20% of cuts are off-beat by more than 2 frames. Shots hold 4 s or more with nothing happening.
- **7:** At least 90% of cuts are on beats (±1 frame). Durations vary in 2-3 lengths that suit the energy. There is a build, but the peak isn't clearly the fastest or most held section.
- **10:** Every cut is on a beat. Section changes land on downbeats. Video motion peaks land on beats. There is a visible energy curve: settle, then build, then the fastest run, then the peak held 4-8 beats, then the outro. Holds and skipped beats feel deliberate. The average shot length suits the mood (hype ~1.1 s, warm ~1.8 s, emotional ~2.8 s).

### 3. Variety and no duplicates, §4.1-4.3, §4.7
Check: adjacent contact-sheet frames, the shot-size sequence, and the photo/video ratio.
- **3:** Visible near-duplicates (burst frames, the same pose, the same moment from two phones). Three or more shots of the same size in a row. Jump cuts. All stills, or all one kind of shot.
- **7:** No duplicates. Shot sizes mostly alternate. One weak repeat (the same location or angle twice, not adjacent). At least 20% video when video exists.
- **10:** Every shot is distinct and adds information. Wide, medium, close and detail sizes rotate. No same-subject cuts within 30°. Video covers 30% or more and is placed at the high-energy points. Assets come from several contributors.

### 4. Framing and crop quality, §8.1-8.5, §6
Check: each frame against its face boxes, the crop mode, the upscale factor, and the Ken Burns direction.
- **3:** Heads or chins cut, faces at the frame edge, a group with people sliced off. Stretched or soft upscaled images (more than 1.5x). Ken Burns drifts away from faces or zooms into empty space. Black bars.
- **7:** Faces are well placed in most shots. Blur-fill is used for wide groups. One or two slightly tight crops. Ken Burns is gentle (≤10%) and mostly aimed at faces.
- **10:** Every shot has its subject placed intentionally (main face about 1/3 from the top, with headroom). Blur-fill is used only where a crop would lose people, in 30% or fewer of shots. No visible upscale softness. Ken Burns moves toward faces, alternates direction, and never stutters at cuts.

### 5. Caption legibility and safe area, §8.6, §9
Check: caption bboxes against the safe box and face boxes, font px, words per caption, duration, and contrast.
- **3:** Text overlaps the platform UI zones (bottom 380 px, right 130 px, top 250 px) or a face. Font smaller than 48 px. Too many words to read in the time on screen. Low contrast. Mixed scripts or typos.
- **7:** All text inside the safe box, at 56 px or more, with stroke or shadow, and readable in time. Title is good. One label is slightly long or poorly timed, entering off the beat.
- **10:** Sparse, purposeful text: a title plus 0-3 labels, each 4 words or fewer, in the requested language and script (natural Hinglish). Every caption enters on a beat, stays for its reading time, and never covers a face. It reads at a glance on a phone at arm's length.

### 6. Story arc, §5
Check: the shot order against the event's slot template (Diwali, conference or wedding) and the timeline of capture times.
- **3:** A random order with no beginning, middle or end. Rituals out of order in a way that confuses (fireworks, then diya lighting, then fireworks again). Ends mid-action.
- **7:** Recognizable hook → setting → activity → people → close. Most key slots are filled. One slot is missing or out of place, or the peak is weak.
- **10:** Hook teases the peak, then the event unfolds in order, hitting its signature moments (for Diwali: rangoli, diyas, aarti, sweets, fireworks, family photo). The peak comes at about 60-85% of the runtime. The close resolves emotionally. A stranger could tell what the event was and how it felt.

### 7. People coverage, §4.4-4.6
Check: people per shot, member list, appearance counts, and the people/detail ratio.
- **3:** One or two people dominate, and key family members (grandparents, kids) or the requested subject are missing. Mostly decor with few faces, or faces too small to recognize.
- **7:** Most named members appear. The people/detail mix is about 60/40. One person is over-represented, or an important person appears only in a group shot.
- **10:** Everyone with usable footage appears at least once, with faces readable. The requested subject ("Dadi with the kids") is featured as asked. No one takes more than 35% of people shots unless they are the subject. Candids and the group photo are balanced. Several contributors' footage is used.

### 8. Music fit, §10
Check: track BPM and mood against the request, the start offset, the section alignment, fades, ducking and loudness.
- **3:** Mood mismatch (a party track for an "emotional" request). Music starts mid-phrase or cuts abruptly. Clip audio clashes with the music. No ducking under speech.
- **7:** Mood and tempo fit. The track starts cleanly. The fade-out is acceptable. The peak roughly meets the chorus. Ducking is present but a bit pumpy, or clip ambience is missing.
- **10:** Track energy follows the edit (the drop or chorus hits the peak shot). Start and end land on phrase boundaries or cadences. Speech moments are ducked cleanly (10-18 dB). Loudness is about −14 LUFS with true peak ≤ −1 dBTP. It feels scored, not laid under.

### 9. Ending, §11
Check: the last 3 shots, the last frame, text at the end, the audio tail, and the loop or card mode.
- **3:** Ends on a random or weak shot, or mid-motion, or with an abrupt audio cut. Stray text lingers, or the ending fades into a long black.
- **7:** Ends on a good group or emotional shot held at least 2 s, with a clean fade. It doesn't loop or close particularly well.
- **10:** The last shot is the emotional anchor (a family or team photo, or a quiet portrait) on a downbeat or cadence. In loop mode, it flows back into the hook with no text tail. In card mode, the title is held 2 s or more, then 0.5 s to black, in sync with the music end.

### 10. Technical quality, §7, §12
Check: blur and exposure per frame, colour consistency, transitions, speed ramps, the encode, and the audio peaks.
- **3:** Blurry, shaky or dark shots. Wildly different colours from different phones. Gimmick transitions (spins, page curls). Choppy slow-mo. Banding, washed-out HDR, or audio clipping.
- **7:** Clean shots. Mostly consistent colour. Hard cuts with 1-2 tasteful crossfades. Minor issues, such as one slightly soft shot or slight banding at night.
- **10:** Every shot is sharp and well exposed. Colour is matched into one cohesive look. More than 90% hard cuts. Crossfades only at time or mood shifts. At most 2 flashes or whips, at most 2 ramps, all on high-fps sources. Correct HDR tone-mapping, steady 30 fps, no banding, no clipping.

---

## Score sheet (copy per reel)

| # | Criterion | Score | Evidence (frame / time / metadata) |
|---|---|---|---|
| 1 | Hook strength | | |
| 2 | Pacing & beat sync | | |
| 3 | Variety, no duplicates | | |
| 4 | Framing & crop | | |
| 5 | Captions & safe area | | |
| 6 | Story arc | | |
| 7 | People coverage | | |
| 8 | Music fit | | |
| 9 | Ending | | |
| 10 | Technical quality | | |
| | **Total /100** | | Hard fail? Y/N |

**Automatable checks** (the renderer can compute these before a human or LLM reviewer looks): cut-to-beat error, duration histogram, adjacent-pair CLIP or pHash similarity, shot-size run length, caption bbox against the safe box and face boxes, font px, characters per second, upscale factor, per-person appearance share, loudness and true peak, black-frame and freeze detection. The reviewer then judges the subjective parts: hook appeal, story, mood fit and the ending.
