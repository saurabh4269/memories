# Memories: final demo video script (about 2 min 30 s)

Rules for this script: every claim on screen is something that runs today. Anything staged or sped up is labelled on screen. Plain words, no hype.

## 0:00 – 0:15 · The feeling

**Visual:** Real footage from today's hackathon floor at BIEC: people heads-down at laptops, a laugh at a table, hands on keyboards. Then a phone gallery scrolling fast, a group chat full of unopened photos.
**Audio:** The developer-vibe track starts low.

**VO:**
"We never notice how fast a day is slipping away while we are still inside it. We shoot everything. The people, the chaos, the moments we will want back. Then it all sits in ten phones and one group chat, and nobody ever edits it."

## 0:15 – 0:30 · The idea

**Visual:** App icon "Memories". The album page with the real "Festive Hacks 2026" album and its cover photo.
**On screen:** "Memories: a personal cinematographer for your people"

**VO:**
"So we built Memories. Everyone at the event shoots into one shared album, and an AI director turns it into reels made for you. We built it for festivals and family nights. Today we had no Diwali. We had this hackathon. So we tested it on ourselves."

## 0:30 – 0:50 · Join and capture

**Visual:**
1. The host taps the QR button on the album page. Invite sheet with the QR code.
2. A second phone scans it, types a name, picks हिंदी, picks "elder". The app logs in by itself and opens the album. (Elder mode: larger text, from Flagsmith.)
3. The Memories camera: tap for a photo, hold for a video. A coach card slides up: "अभी बाकी: आपकी team की group photo".

**VO:**
"Family members join with a QR code. No server address, no sign-up form. Shoot in the Memories camera, or keep using your own camera app and it backs up into the album. While you shoot, the coach tells you what is still missing. In your language."

## 0:50 – 1:20 · Ask in your own words

**Visual:** Make-a-reel screen. Tap the big mic. Say in Hinglish: "Hackathon ki yaadein, team ke saath, building wali." The transcript chip appears. The progress story runs: reading the album, finding your people, cutting to the beat. Two vertical cuts appear side by side, each with a title and one line on why. Play one.
**On screen (small):** "Real footage. 104 photos and videos from today."

**VO:**
"Nobody here writes prompts. You just say it. Sarvam's Dictate understands Hinglish and the names of your people. The director looks at every photo and video, knows who your team is from the faces that keep coming back, drops the blurry and repeated shots, and gives you two different cuts. Each one tells you why it chose what it chose."

## 1:20 – 1:35 · Finish and share

**Visual:** Tap a cut. Instant preview plays on the phone. Tap Edit: long-press to reorder a clip, tap one to swap it with a suggestion, Update. Tap Share: Android share sheet, WhatsApp. Then "Post" to the Telegram channel; cut to the post landing in t.me/memories_family_demo_4336.

**VO:**
"The preview plays instantly on the phone, the way Google Photos plays memories. Change a shot if you want. The final video is already rendering while you watch, so sharing to WhatsApp takes one tap. It can post straight to your family channel too."

## 1:35 – 2:15 · Under the hood (for developers)

**Visual:** The architecture diagram from `docs/architecture/`. Then quick cuts:
1. **Sarvam:** Token Factory logs with sarvam-105b and Gemma 4 rows; Document AI reading a Hindi invitation card into names, ceremonies and times.
2. **Flagsmith:** the `director_strategy` experiment (agentic director vs single-shot, metric `reel_shared`); the `elders_hindi` segment; flip `shot_coach` and the camera card appears or disappears.
3. **NudgeBee:** NuBi answering a real question about the Immich ML service with evidence from today's import. Then the rehearsal: OOM event, root cause, the human clicks **approve**, Flagsmith turns on `ml_lite_mode`, Feature Health marks the shot coach unhealthy, and the app keeps working.
**On screen during the rehearsal:** "Rehearsal: we lowered the memory limit on purpose. Investigation sped up."

**VO:**
"Under the hood, Memories stands on open source. Immich stores the media and groups faces. Facet scores photo quality. Sarvam is the director's eyes, ears and voice: it reads every shot, plans the edit with tool calls over the album, and understands Indian languages end to end. Flagsmith is the control plane. We A/B test the director itself, turn on elder mode by segment, and roll new features out slowly. NudgeBee watches the cluster. When a festival-night upload surge breaks the machine-learning service, it finds the real cause, a human approves the fix, and Flagsmith switches the app to lite mode. Nothing changes without a person saying yes."

## 2:15 – 2:30 · Back to people

**Visual:** The finished hackathon reel plays full screen, our team building. Cut to the GitHub repo and README for one second. Title card: "Memories. Keep the people, not just the photos."
**Audio:** The track resolves.

**VO:**
"Festivals end. Hackathons end. The people in them are what we want to keep. Memories makes sure everyone walks away with their own story of the day. The code is open, and the setup is in the README."

---

## Shot list (record these first)

| # | What | Where |
|---|---|---|
| 1 | 6 to 8 real clips of people building | Your hackathon footage |
| 2 | Album page with cover + QR invite sheet | App on emulator |
| 3 | Join flow on a second device or emulator, elder mode | App |
| 4 | Camera with coach card in Hindi (use member `nani-demo`) | App |
| 5 | Mic prompt to two cuts, progress story, play one | App, live director |
| 6 | Preview, edit swap, share sheet, Telegram post landing | App + t.me channel |
| 7 | Architecture diagram | `docs/architecture/` |
| 8 | Sarvam: Token Factory logs, Document AI invite | indus.sarvam.ai |
| 9 | Flagsmith: experiment, segment, `shot_coach` toggle | app.flagsmith.com |
| 10 | NudgeBee: NuBi answer, event, root cause, approve, outputs | app.nudgebee.com (trigger `AUTO_APPROVE=0 RESTORE=0 deploy/surge/run.sh` 5 minutes before) |
| 11 | Final hackathon reel full screen | best reel URL |
| 12 | GitHub repo README | github.com |

## Honesty notes to keep on screen or in the README
- The NudgeBee incident is a rehearsal with a deliberately low memory limit; the investigation is sped up.
- Experiment traffic is small; read the direction, not the size.
- The background music is AI-generated (ElevenLabs), if that version is used.
- Gemma 4 runs on Sarvam's Token Factory; it is an open model, not trained by Sarvam.
- AI coding assistants wrote much of the code; we designed, reviewed and can explain it.
