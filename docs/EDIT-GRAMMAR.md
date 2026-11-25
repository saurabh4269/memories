# Edit grammar: short vertical event reels (10-30 s, 9:16)

A spec for the AI director (picks and orders shots, writes the EDL) and the renderer (motion, crop, captions, audio). Researched 2026-11-25.

**Confidence tags** (one on every rule):
- **[C] Consensus.** Several independent sources agree, or it is a platform's own guidance.
- **[P] Common practice.** Widely taught, but the exact number varies from source to source. Our number is a midpoint.
- **[O] Opinion / our default.** A single source, or our own choice made to get a codable number. Tune it with A/B tests and the rubric.

**About the sources:** almost no rigorous research covers this, and Meta publishes no official safe-zone spec. Most numbers come from editor and vendor guides, and those guides disagree. Treat every number as a default the code can change, not a law. Reddit threads did not show up in search, so community opinion here comes from forums (Creative COW, DV Info Net) and editor blogs.

Notation: `B` = one beat in seconds = 60 / BPM (90 BPM → 0.667 s, 110 → 0.545 s, 120 → 0.5 s, 130 → 0.462 s). `H` = frame height (1920), `W` = frame width (1080).

---

## 1. Global

1.1 **[P] Output:** 1080x1920, 30 fps, H.264 High, yuv420p, AAC 48 kHz. One master works for Reels, Shorts and WhatsApp Status. Source: [Hopper HQ: Reel size](https://www.hopperhq.com/blog/instagram-reel-size/), [vidIQ: Shorts dimensions](https://vidiq.com/blog/post/youtube-shorts-vertical-video).

1.2 **[P] Length targets:** `status` cut 12-20 s (default 15). `reel` cut 15-30 s (default 20-24). Shorter Reels with high retention beat longer ones with low retention. Keep a WhatsApp Status at 30 s or less, so it plays as one clip. Its limit has been reported at 60 s, which we have not verified. Source: [Buffer: Reels 2026](https://buffer.com/resources/instagram-reels-instructions-and-ideas-for-small-businesses/), [Opus: ideal Reels length](https://www.opus.pro/blog/ideal-instagram-reels-length), [Tella hype-reel skill](https://www.tella.com/skills/hype-reel) (8-30 s, default 12).

1.3 **[C] Every element must earn its place.** Trim anything that slows the start. Source: [Instagram via Social Media Today](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/).

## 2. Hook (0-2 s)

2.1 **[C] The first shot is the strongest visual in the set.** Use motion or a peak moment, never an establishing shot of an empty venue or a slow fade-in from black. The first few seconds "decide everything". Source: [Instagram via SMT](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/), [Opus: hook formulas](https://www.opus.pro/blog/instagram-reels-hook-formulas), [async: open on action](https://async.com/blog/how-to-edit-instagram-reels/).

2.2 **[P] Hook shot scoring:** prefer, in this order: (a) a video clip with high motion energy or a peak (fireworks burst, a laugh, a dance move, applause); (b) a close-up of a face with strong emotion; (c) a strong detail (diya flame, finished rangoli, stage lights). Never open with a blurry, dark or back-of-head frame. Source: [Instagram via SMT](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/) ("surprising visual"). The ordering is **[O]**.

2.3 **[P] Picture is on screen at frame 0.** No black lead-in. Music starts at frame 0, or on a pickup that resolves on the first downbeat by 1.0 s or earlier. Source: [Tella hype-reel](https://www.tella.com/skills/hype-reel) (first hit at 2.23 s after a riser, which is fine for a hype edit; we want it sooner).

2.4 **[P] Hook text:** an on-screen title of 2-5 words appears by 0.3 s at the latest and stays 1.5-2.5 s (for example "Diwali 2026 ✨", "Sharma ghar ki Diwali"). Many viewers watch muted, so the hook must work without sound. Source: [Opus: hook formulas](https://www.opus.pro/blog/instagram-reels-hook-formulas), [Instagram via SMT](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/).

2.5 **[O] First cut by 1.5 s or earlier** (2-3 beats at 90-130 BPM), so the viewer sees change before the ~3 s skip decision. Source: [Opus: Reels length](https://www.opus.pro/blog/ideal-instagram-reels-length), [Lilach Bullock: editing steps](https://www.lilachbullock.com/instagram-reels-editing-steps/).

2.6 **[O] Hook motion:** if the hook is a still, give it a punch-in from scale 1.12 to 1.00 over 0.3 s with ease-out, landing on the first downbeat. Source: [Tella hype-reel](https://www.tella.com/skills/hype-reel).

## 3. Pacing and beat grid

3.1 **[C] Cuts land on beats.** Snap every cut to the nearest beat. Allow up to 1 frame of error (33 ms at 30 fps). Source: [Instagram via SMT](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/) ("cut on the beat"), [Tella](https://www.tella.com/skills/hype-reel) (≤33 ms), [Google Photos templates match the beat](https://blog.google/products/photos/new-video-editor-templates-custom-text/).

3.2 **[C] Don't cut on every beat.** Vary hold lengths. Strict every-beat cutting gets predictable. Source: [LBB: music video editing](https://lbbonline.com/news/more-than-just-cutting-to-the-beat-the-nuance-of-editing-music-videos), [No Film School / Larry Jordan](https://nofilmschool.com/2014/09/larry-jordan-teaches-us-how-create-video-montage-set-music).

3.3 **[P] Shot durations in beats** (the renderer converts with B):

| Shot type | Hype (`energy≥0.7`) | Warm / family (`energy 0.4-0.7`) | Emotional (`energy<0.4`) |
|---|---|---|---|
| Still photo | 2 beats | 2-4 beats | 4 beats |
| Video clip | 2-4 beats | 4 beats | 4-8 beats |
| Hero / peak moment | 4 beats | 4-8 beats | 8 beats |
| Minimum ever | 1 beat (only in a build run) | 2 beats | 2 beats |

At 110 BPM, 2 beats = 1.09 s and 4 beats = 2.18 s. Resulting averages: hype 1.0-1.3 s per shot, warm 1.5-2.2 s, emotional 2.2-3.5 s. Source: [Tella](https://www.tella.com/skills/hype-reel) (1-2 beats per shot, heroes 2, 11-13 shots in 12 s at 105-120 BPM), [Lilach Bullock](https://www.lilachbullock.com/instagram-reels-editing-steps/) and [async](https://async.com/blog/how-to-edit-instagram-reels/) (cut every 1.5-3 s). The table's mapping is **[O]**.

3.4 **[P] Prefer cutting on downbeats** (beat 1 of a bar) for section changes and hero shots. Use offbeats only inside a fast run. On weak beat tracking (confidence <0.5), cut on downbeats only. Source: [Tella](https://www.tella.com/skills/hype-reel).

3.5 **[P] Let action land on the beat.** For video clips, choose the in-point so the clip's motion peak (a firework burst, a hug, a clap) falls on a beat, rather than only snapping the cut. Source: [Creative COW forum](https://creativecow.net/forums/thread/music-videos-edit-to-the-beat-or-lyrics-2/).

3.6 **[P] Energy curve of the cut:** medium-fast hook (0-2 s), then a slightly slower settle (2-6 s), a build where durations shrink, the fastest run of 1-2 beat cuts just before the peak, the peak held 4-8 beats, then a slower outro. Source: [Tella](https://www.tella.com/skills/hype-reel) (30 s variant: a middle of 2-beat shots, then a final 4-bar run of 1-beat cuts), [CapCut: montage rhythm](https://www.capcut.com/create/music-video-pacing-emotional-montage-rhythm).

3.7 **[O] Shot count budget:** `n_shots ≈ duration_s / avg_shot_s`. That gives 15 s warm ≈ 8-10 shots and 24 s warm ≈ 12-16 shots. Fill every shot slot. Never stretch a still beyond 8 beats.

3.8 **[O] Video clip trimming:** use only the best 1-4 s of a phone clip (the highest motion or face score) and drop shaky segments. Never play a clip where nothing changes for more than 3 s, unless something is developing in the shot (a speech line, a reveal). Source: [async](https://async.com/blog/how-to-edit-instagram-reels/) (single long shots work only "because something is actually developing").

## 4. Variety and duplicates

4.1 **[C] No near-duplicates.** Burst frames, the same pose a second apart, and two uploads of the same moment from different phones are one shot. Use perceptual hash or CLIP cosine similarity above 0.92 → keep the sharpest one with the best faces. Source: [Mynewsdesk: event highlights](https://www.mynewsdesk.com/uk/zoodikers/blog_posts/video-production-tips-shooting-event-highlights-video-34466) ("variety of shots that complement each other, don't linger"), [Apple Photos tech brief](https://apple.com/ph/ios/photos/pdf/Photos_Tech_Brief_Sept_2019.pdf) (ranks by sharpness, exposure, faces). The threshold is **[O]**.

4.2 **[P] Shot-size alternation:** never put 3 shots of the same size (wide / medium / close / detail) in a row. Prefer a size change on every cut. Source: [Mynewsdesk](https://www.mynewsdesk.com/uk/zoodikers/blog_posts/video-production-tips-shooting-event-highlights-video-34466), [CapCut: 30-degree rule](https://www.capcut.com/create/video-transitions-crossfade-hard-cut-jump-cut).

4.3 **[C] Avoid jump cuts:** don't cut between two shots of the same subject from nearly the same angle and size (less than ~30° change, less than 1 size step). Either insert a different shot between them or drop one. Source: [Arev et al., SIGGRAPH 2014, multi social cameras](https://studios.disneyresearch.com/wp-content/uploads/2019/03/Automatic-Editing-of-Footage-from-Multiple-Social-Cameras.pdf), [CapCut](https://www.capcut.com/create/video-transitions-crossfade-hard-cut-jump-cut).

4.4 **[O] People / detail mix:** about 60-70% people shots and 30-40% detail or atmosphere (decor, food, lights, venue). Never 3 detail shots in a row. Source: [Clipchamp: Diwali ideas](https://clipchamp.com/en/blog/diwali-video-ideas/), [Rainfocus: recap points](https://rainfocus.com/blog/15-points-of-a-great-recap-video/), [Flixier recap guide](https://flixier.com/blog/a-complete-guide-on-how-to-make-an-event-recap-video).

4.5 **[O] Person coverage:** every named member with 3 or more usable assets appears at least once. No one person (other than the requested subject) takes more than 35% of the people shots. The same person never appears in 3 consecutive shots unless they are the subject of the cut.

4.6 **[O] Contributor mix:** if several phones contributed, draw from at least 2 contributors when possible. This is our product's differentiator.

4.7 **[P] Photo/video mix:** if any videos exist, at least 30% of the timeline runs on video, since motion keeps retention up. Stills move with Ken Burns (section 6). Source: [Instagram via SMT](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/) (motion, energy). The 30% is **[O]**.

4.8 **[P] Quality gates:** reject assets with blur (variance of Laplacian below a threshold), heavy under-exposure, closed eyes on the main face, or a face cut by the frame edge. Source: [Apple Photos tech brief](https://apple.com/ph/ios/photos/pdf/Photos_Tech_Brief_Sept_2019.pdf).

## 5. Story structure

5.1 **[C] Hook first, then mostly chronological.** Open with the peak (or a teaser of it), then tell the event roughly in order, and end on the emotional close. Source: [Udemy wedding course (hook-first)](https://www.udemy.com/course/edit-cinematic-wedding-films/), [Roughcut: highlight structure](https://roughcut.com/blog/how-to-structure-wedding-highlight-film), [PremiumBeat: wedding highlights](https://www.premiumbeat.com/blog/5-tips-editing-cinematic-wedding-highlight-videos) (the highlight is not the full timeline, so weave the best moments).

5.2 **[P] Generic 5-beat arc** (as share of the runtime): Hook 0-10% → Arrival/Setting 10-25% → Rituals/Activity 25-55% → People & Peak 55-85% → Close 85-100%. Source: [Roughcut](https://roughcut.com/blog/how-to-structure-wedding-highlight-film), [Canon: event recap steps](https://cinemaeos.canon.ca/resources/five-steps-for-producing-engaging-event-recap-videos). The percentages are **[O]**.

5.3 **[O] Diwali slot template** (fill in order, skip a slot when the album has nothing for it):
1. Hook: fireworks or sparkler burst, or a lit diya close-up with a face.
2. Setting: the house lit up, fairy lights, door toran.
3. Rangoli: wide first, then a detail close-up. Source: [Bizzbuzz: Diwali photo prompts](https://www.bizzbuzz.news/technology/7-creative-prompts-to-capture-stunning-diwali-photos-with-fireworks-diyas-rangoli-and-family-1374024).
4. Diyas: lighting them, hands and flame.
5. Puja / aarti: the thali, the flame circling, faces lit warm.
6. Sweets / food: mithai box, feeding each other.
7. People: kids, grandparents, candids with laughter.
8. Fireworks / phuljhadi (peak): fastest cuts here.
9. Close: the whole-family group photo (held longest), optionally followed by a single diya.

Source: [Hindutone: Diwali reel ideas 2026](https://hindutone.com/festivals/diwali-2026/diwali-reel-ideas-2026-instagram-youtube-shorts/), [Clipchamp](https://clipchamp.com/en/blog/diwali-video-ideas/), [Asianet: 7 Diwali reel ideas](https://newsable.asianetnews.com/lifestyle/diwali-2025-make-these-7-instagram-reels-a-trend-with-the-festival-of-lights-meg-articleshow-owrnkqx).

5.4 **[O] Conference / hackathon slot template:**
1. Hook: crowd energy, applause, or the demo "it works" moment.
2. Venue: signage, badge, wide shot of the hall.
3. Keynote: speaker wide, then the speaker close, then the audience reaction.
4. Team: huddles, laptops, whiteboard (people at work).
5. Demo / build: screens, hands, a reveal.
6. Crowd / networking: candid conversations, laughter.
7. Peak: awards, stage moment.
8. Close: a team group photo, or the team walking out.

Source: [Rainfocus](https://rainfocus.com/blog/15-points-of-a-great-recap-video/), [Vimeo: event recap](https://vimeo.com/blog/post/event-recap-video), [Flixier](https://flixier.com/blog/a-complete-guide-on-how-to-make-an-event-recap-video), [Fame: conference videography](https://www.fame.so/post/conference-videography).

5.5 **[O] Wedding / family function template:** Hook (peak: varmala, a dance, a laugh) → venue/decor → getting ready → main ritual (pheras, haldi, mehndi) → family and friends → dance/party (peak) → couple or family close. Source: [Roughcut](https://roughcut.com/blog/how-to-structure-wedding-highlight-film), [PremiumBeat](https://www.premiumbeat.com/blog/5-tips-editing-cinematic-wedding-highlight-videos).

5.6 **[P] Emotional arc for the "emotional" cut:** higher-energy celebration in the middle, quiet close (a grandparent's smile, a hug, the last diya). Source: [Dev.to: wedding highlight without a videographer](https://dev.to/firstcutstudio/how-to-make-a-wedding-highlight-video-without-a-videographer-28a3), [Roughcut](https://roughcut.com/blog/how-to-structure-wedding-highlight-film) (the close is the most memorable part).

## 6. Ken Burns (stills)

6.1 **[C] Every still moves.** No static photo holds longer than 1 beat. Source: [Final Cut Pro guide: Ken Burns](https://support.apple.com/kb/PH12607?locale=en_US), [Animoto](https://animoto.com/blog/how-to-news/ken-burns-effect-zoom-video).

6.2 **[O] Zoom amount:** a slow push of 1.00 → 1.06 to 1.10 over the shot (≈3-5% per second). Hero stills may reach 1.15. A punch-in accent on a downbeat goes 1.12 → 1.00 in 0.3 s. Never exceed a total scale of 1.20, or the upscale softens. Source: [Tella](https://www.tella.com/skills/hype-reel) (1.0 → 1.06 push, 1.12 → 1.0 punch), [Cloudinary](https://cloudinary.com/blog/add-motion-to-your-pictures) (zoom needs resolution).

6.3 **[O] Direction:** zoom in toward the face box centroid (or the group's centroid). For groups, start tight and pull out to reveal everyone. Alternate in and out between consecutive stills, and never move the same way 3 times in a row. Pans follow the line of faces in a group (left to right). Source: [Wikipedia: Ken Burns effect](https://wikipedia.com/wiki/Filmograph) (crop to a detail and pan), [Final Cut Pro](https://support.apple.com/kb/PH12607?locale=en_US). Face targeting is our choice; no source gives one.

6.4 **[P] Easing:** linear (constant speed) for pushes that span a cut, so motion doesn't visibly stop at the edit. Ease-out for punch-ins. Final Cut's default eases in and out, which reads as "slideshow". Source: [Final Cut Pro](https://support.apple.com/kb/PH12607?locale=en_US), [Tella](https://www.tella.com/skills/hype-reel).

6.5 **[O] Keep faces in the crop** at the start and end keyframes. Faces stay inside the caption-safe area (section 8) for the whole move.

6.6 **[O] No Ken Burns on video clips,** except a punch-in of 1.00-1.08 to reframe or to hide shake.

## 7. Transitions and speed

7.1 **[C] Hard cut is the default** (≥90% of edits). Source: [Videomaker: transition effects](https://www.videomaker.com/article/15373-transition-effects), [CapCut: crossfade vs hard cut](https://www.capcut.com/create/video-transitions-crossfade-hard-cut-jump-cut), [Videomaker: the only transitions you'll need](https://www.videomaker.com/article/c10/17658-the-only-transitions-youll-ever-need/).

7.2 **[C] Crossfades only for time passing or a mood shift:** day to night, ritual to party, or into the quiet close. In a fast music edit, keep them short: 4-8 frames (0.13-0.27 s) in fast cuts, up to 0.5 s in the emotional cut. At most 2 per reel. Repeated 0.5 s crossfades make a short edit feel slow. Source: [CapCut](https://www.capcut.com/create/video-transitions-crossfade-hard-cut-jump-cut), [DV Info Net: cuts vs dissolves](https://www.dvinfo.net/forum/open-dv-discussion/500698-cuts-vs-dissolves-print.html?pp=40), [Tutkit](https://www.tutkit.com/en/magazine/1048-using-video-transitions-purposefully). The frame counts are **[P]**.

7.3 **[C] No gimmick transitions:** no page curl, cube, spin, star wipe or random glitch. Use a whip or flash at most 1-2 times, only on a big downbeat (a drop or the peak). Flash: white at 0.85 opacity, fading out over 0.2 s. Source: [Videomaker: page curl or cut?](https://www.videomaker.com/article/c3/12238-to-page-curl-or-to-cut/), [Tella](https://www.tella.com/skills/hype-reel), [PremiumBeat](https://www.premiumbeat.com/blog/5-tips-editing-cinematic-wedding-highlight-videos) (light leaks sparingly).

7.4 **[P] Fade to black only at the very end** (or not at all, for loop-friendly cuts, see 11.2). Source: [Videomaker](https://www.videomaker.com/article/15373-transition-effects).

7.5 **[O] Speed ramps:** at most 1 in a 15 s reel and at most 2 in a 30 s reel, only on a clip shot at 60 fps or more, or on motion that tolerates frame blending. Slow-mo of 0.4-0.5x for emotional peaks (a hug, a sparkler) is fine without a ramp if the source fps is high enough. Source: [Tella](https://www.tella.com/skills/hype-reel) (≤2 ramps, one per 4 bars, 0.45x ↔ 4x).

## 8. Framing for 9:16

8.1 **[P] Crop around faces by default.** Center the 9:16 crop window on the face box union. Weight: the main subject's face at about 1/3 from the top of the frame. Source: [Descript: horizontal to vertical](https://www.descript.com/blog/article/how-to-make-horizontal-video-vertical), [Obsbot](https://www.obsbot.com/blog/video-production/how-to-make-a-horizontal-video-vertical).

8.2 **[P] Blur-fill (pillarbox) when a crop would cut people:** if the face union is wider than 85% of the 9:16 crop width (wide group photos, a stage with several people) or the whole scene matters, fit the full image to width and fill the rest with a blurred, darkened, scaled copy (blur sigma ≈ 40, brightness 0.6). Never stretch. Source: [Descript](https://www.descript.com/blog/article/how-to-make-horizontal-video-vertical) ("crop if the subject is centered, background if the whole scene matters"). The thresholds are **[O]**.

8.3 **[O] Prefer native-vertical assets** when choosing between equally good shots. Use at most 30% blur-fill shots per reel, since they read as lower effort.

8.4 **[P] Don't crop too tight:** reframed crops tend to be too tight. Keep heads with headroom (≥ 0.05 H above the top face) and never cut chins or the group's edge faces. Check every keyframe, not just the first. Source: [PetaPixel 2026](https://petapixel.com/2026/08/13/vertical-video-is-driving-this-cameraman-insane/), [Programming Insider: AI reframing](https://programminginsider.com/video-cutter-ai-reframing-for-converting-landscape-youtube-videos-into-shorts/).

8.5 **[O] Upscale limit:** don't use an asset where the crop must upscale more than 1.5x to fill 1080x1920. Blur-fill it instead, or skip it.

8.6 **[P] Safe areas at 1080x1920** (these are the conservative union across platforms; sources vary by ±50 px):

| Zone | Instagram Reels | YouTube Shorts | WhatsApp Status (est.) | **Use (union)** |
|---|---|---|---|---|
| Top | 210 px | 120-288 px | ~160 px (progress bar, name) | **250 px** |
| Bottom | 310 px (worse with captions on) | 300-360 px | ~200 px (reply bar) | **380 px** |
| Right | 84-120 px (button stack) | 96-192 px | 0 | **130 px** |
| Left | 0-60 px | 48 px | 0 | **60 px** |

So the **caption/title box** = x 60..950, y 250..1540. Keep **faces** inside y 250..1540 when possible. Never put text in the bottom-right corner. Source: [Adaptly: safe zones 2026](https://adaptlypost.com/blog/social-media-safe-zones-2026-complete-guide), [Kapwing](https://www.kapwing.com/video-editor/instagram-reels/safe-zone), [Hopper HQ](https://www.hopperhq.com/blog/instagram-reel-size/), [vidIQ Shorts](https://vidiq.com/blog/post/youtube-shorts-vertical-video), [Trymypost](https://www.trymypost.com/blog/instagram-reels-safe-zones-text-placement-2026). The WhatsApp numbers are our estimate (no source).

## 9. Captions and on-screen text

9.1 **[C] Text must work muted.** Use text for the title and key moments. These are event reels, not talking heads, so text is sparse: a title, 0-3 moment labels, and an optional end line. Source: [Instagram via SMT](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/).

9.2 **[P] Size:** title cap-height ≥ 4.5% H (font size ≈ 96-140 px). Moment labels and subtitles: font size 56-72 px (≥ 48 px absolute minimum). Source: [Opus: Shorts captions](https://www.opus.pro/blog/youtube-shorts-caption-subtitle-best-practices) (≥48 px at 1080x1920), [Rev: open caption font sizes](https://www.rev.com/blog/best-open-caption-font-sizes-for-videos-on-social-media), [Trymypost](https://www.trymypost.com/blog/instagram-reels-safe-zones-text-placement-2026) (≥45 px), [Tella](https://www.tella.com/skills/hype-reel) (sub line ≥32 px; title 160-250 px).

9.3 **[P] Length:** title 2-5 words. Labels ≤ 4 words / ≤ 24 characters per line. At most 2 lines, never more than 32 characters per line. Source: [Opus: Facebook Reels captions](https://www.opus.pro/blog/facebook-reels-caption-subtitle-best-practices), [Kapwing captions guide](https://www.kapwing.com/resources/social-media-captions-styles-a-complete-guide/).

9.4 **[P] Timing:** on screen for at least `max(1.2 s, 0.2 s × words + 0.5 s)` and ≤ 3 s for a label. Reading speed ≤ 15 characters per second for Hinglish/Devanagari (slower than the 20 cps standard for English). Text enters on a beat and never straddles a hard cut unless it is the title. Source: [Syllaby: caption timing](https://syllaby.io/blog/subtitle-styling-burn-in-caption-timing-guide/), [Kineclip checklist](https://kineclip.com/blog/caption-readability-checklist-short-videos-2026/). The Hinglish rate is **[O]**.

9.5 **[P] Placement:** inside the safe box (8.6). Title in the upper third (y ≈ 300-600) or centered. Labels in the lower-middle (y ≈ 1250-1500), above the platform UI. Never over a face: move the text to the opposite half if a face box overlaps. Source: [CapCut: vertical subtitle placement](https://www.capcut.com/create/vertical-video-subtitles-placement-tips), [Opus: caption design placement](https://www.opus.pro/blog/video-caption-design-placement), [Tella](https://www.tella.com/skills/hype-reel) (9:16 title between 10% and 80% of H).

9.6 **[C] Legibility:** white or warm-white text, a 4-6 px dark stroke or a soft shadow (or a 60% black pill behind it). Contrast ≥ 4.5:1 against the local background. Bold sans (Devanagari: Noto Sans Devanagari Bold, or Mukta). Source: [Rev](https://www.rev.com/blog/best-open-caption-font-sizes-for-videos-on-social-media), [OpenClip: caption styling](https://openclip.app/guides/caption-styling-guide).

9.7 **[O] Language:** match the request's language. Hinglish in Latin script is the default for WhatsApp family audiences ("Ghar wali Diwali 🪔"). Use Devanagari only if the user wrote in Devanagari. Never mix scripts in one line. Emoji: at most 1 per text element. Render with HarfBuzz shaping (already in the plan).

9.8 **[O] Title content:** event + year, or event + family name ("Diwali 2026", "Gupta parivaar ki Diwali"). The end card may repeat it with the date.

## 10. Music

10.1 **[C] Match the mood and energy to the request:** `emotional` → 70-95 BPM, warm or acoustic. `family/warm` → 95-115 BPM. `hype/party/fireworks` → 115-130 BPM. Source: [Instagram via SMT](https://www.socialmediatoday.com/news/instagram-shares-tips-on-video-creation/827172/) ("match the energy of the track"), [Epidemic Sound: wedding edit](https://epidemicsound.com/blog/edit-wedding-video), [PremiumBeat](https://www.premiumbeat.com/blog/5-tips-editing-cinematic-wedding-highlight-videos). The BPM bands are **[O]**.

10.2 **[P] Pick the section of the track, not just the track.** Choose a start offset so the strongest section (the drop or chorus) aligns with the reel's peak (5.2). Use beat-grid metadata with section markers. Source: [Tella](https://www.tella.com/skills/hype-reel) (per-track drop and re-entry offsets).

10.3 **[P] Fades:** start at full level on frame 0 (or a 0.3 s micro fade-in). End with a 1.0-1.5 s fade-out, or end on a musical cadence or downbeat with no fade (preferred when it lines up). Never cut music mid-phrase without a fade. Source: [Tella](https://www.tella.com/skills/hype-reel) (1.2 s fade-out).

10.4 **[P] Ducking under speech:** when a clip has meaningful speech or a reaction ("Happy Diwali!", a laugh, a speech line), duck the music by 10-18 dB with a 150-300 ms attack and a 300-500 ms release. Otherwise mute the clip audio, or mix it at −20 dB for ambience (crackle of fireworks). Source: [Storyblocks: balancing audio](https://www.storyblocks.com/resources/tutorials/how-to-balance-audio-premiere-pro) (start at −18 dB duck), [Tella](https://www.tella.com/skills/hype-reel) (−8 dB under a line), [Adobe auto-ducking](https://www.adobe.com/learn/premiere-pro/web/automatic-audio-ducking). The range is **[P]**.

10.5 **[O] Loudness:** master at about −14 LUFS integrated, true peak ≤ −1 dBTP (the common streaming/social target). Source: [Tella](https://www.tella.com/skills/hype-reel) (audio level around −12 to −20 dBFS). The LUFS target is common practice; we did not find a platform spec to cite.

10.6 **[P] Licensed music only** (our curated CC0/Pixabay set). Source: [PremiumBeat](https://www.premiumbeat.com/blog/5-tips-editing-cinematic-wedding-highlight-videos).

## 11. Ending

11.1 **[P] The last shot is the emotional anchor:** the family or team group photo, or a quiet portrait, held 4-8 beats (≥ 2 s), with a gentle push of 1.00 → 1.05. Source: [Roughcut](https://roughcut.com/blog/how-to-structure-wedding-highlight-film) (the close shapes how viewers feel), [Dev.to](https://dev.to/firstcutstudio/how-to-make-a-wedding-highlight-video-without-a-videographer-28a3).

11.2 **[P] Loop-friendly option (`loop: true`, default for the Reels cut):** no fade to black. End on a downbeat. The last shot's colour and energy lead naturally back into the hook (for example, ending on a diya when the hook is a diya flame, or matching the hook's subject or framing). End text must not linger into the replay. Avoid a "finished pose" final beat. Source: [CapCut: seamless loops](https://www.capcut.com/create/seamless-loop-videos-continuity-techniques), [vidIQ: looping Shorts](https://vidiq.com/blog/post/double-youtube-watch-time-looping-shorts), [Virvid: looping structure](https://virvid.ai/blog/looping-structure-shorts-retention-2026).

11.3 **[O] Closing card option (`loop: false`, default for WhatsApp Status):** title or end line on the last full bar's downbeat, held ≥ 2 s, then 0.5 s to black, with the music cadence or fade ending together with the picture. Source: [Tella](https://www.tella.com/skills/hype-reel).

## 12. Technical quality

12.1 **[C] Colour-match shots from different phones:** normalize white balance and exposure (per-shot auto levels, then a light shared look). Avoid a heavy filter. Source: [PremiumBeat](https://www.premiumbeat.com/blog/5-tips-editing-cinematic-wedding-highlight-videos).

12.2 **[P] Stabilize or reject shaky clips.** Prefer a clip segment where gyro or optical-flow jitter is low. Source: [Apple Photos tech brief](https://apple.com/ph/ios/photos/pdf/Photos_Tech_Brief_Sept_2019.pdf) (quality signals).

12.3 **[P] Honour rotation, HDR and orientation metadata.** Tone-map HDR (HLG/PQ from iPhones) to SDR BT.709 so it doesn't look washed out. Constant 30 fps output, no dropped or duplicated frames at cuts.

12.4 **[O] Never upscale beyond 1.5x** (see 8.5). Never letterbox with black bars. Never ship visible encoder banding in night or diya shots: use bitrate ≥ 8 Mbps or CRF ≤ 20.

---

## Appendix: what the reference auto-editors do

- **Google Photos highlight videos** search by people, places and dates, pick the "best" pieces automatically, and add music. Templates "match the beat". "Beat Match" (found in a teardown, unreleased) changes how long each photo stays on screen based on tempo, which supports our beat-grid approach. Reviewers call the results "hit-or-miss". Sources: [Google blog](https://blog.google/products/photos/new-video-editor-templates-custom-text/), [Android Authority teardown](https://androidauthority.com/google-photos-highlight-videos-beat-match-apk-teardown-3712456), [TechRadar](https://techradar.com/computing/software/google-photos-can-now-make-automatic-highlights-videos-of-your-life-heres-how).
- **Apple Memories** uses on-device ML (faces, scenes, sharpness, exposure) to build themed films. A "key photo" opens it with the title. Duration presets are Short, Medium and Long. Music is chosen from the content and the user's tastes. Sources: [Apple Photos tech brief](https://apple.com/ph/ios/photos/pdf/Photos_Tech_Brief_Sept_2019.pdf), [Apple support: personalize memories](https://support.apple.com/guide/photos/pht69f4420d8/11.0/mac/26), [TechCrunch 2016](https://techcrunch.com/2016/06/13/apple-memories/).
- **Research:** Arev et al. (SIGGRAPH 2014) edit multi-person "social camera" footage by maximizing coverage of the important content while respecting the 180° rule and avoiding jump cuts. This is the closest academic analogue to our multi-phone album. Source: [paper PDF](https://studios.disneyresearch.com/wp-content/uploads/2019/03/Automatic-Editing-of-Footage-from-Multiple-Social-Cameras.pdf).
