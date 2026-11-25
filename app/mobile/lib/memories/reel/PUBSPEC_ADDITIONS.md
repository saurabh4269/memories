# Reel module: dependencies and wiring

## pubspec.yaml

These were already present when this module was written (added by the integration agent):

```yaml
  video_player: ^2.14.1   # live preview: music clock, video clips, mp4 fallback, confirmation audio
  record: ^7.2.0          # VoicePromptButton (AAC-LC .m4a, 16 kHz mono)
```

Also used, already in the app: `hooks_riverpod`, `http`, `logging`, `path_provider`, `share_plus` (10.x API: `Share.shareXFiles`).

There's no `just_audio`. Music plays through `video_player`, which handles audio-only URLs on iOS (AVPlayer) and Android (ExoPlayer). Every player is created with `mixWithOthers: true`, so the music and the muted video clips don't interrupt each other. To switch the music to `just_audio`, re-implement `services/reel_clock.dart`. Nothing else depends on the player.

## Platform

- Android: `RECORD_AUDIO` and `INTERNET` are already in the manifest.
- iOS: `NSMicrophoneUsageDescription` exists, but its text is about video. For the voice prompt, it should say something like "Memories uses the microphone so you can ask for a reel by voice."

## Public API

```dart
import 'package:immich_mobile/memories/reel/reel.dart';

// 1. Voice prompt
VoicePromptButton(
  onIntent: (VoiceIntent i) { /* i.transcript, i.request, i.destination, i.people, i.mood */ },
  familyNames: ['Dadi', 'Rahul'],
  language: 'hi-IN',            // also picks Hindi/English UI text
  size: 132,                    // optional
  onError: (msg) {},            // optional; the error is already shown under the button
  onStateChanged: (VoicePromptState s) {}, // optional
);

final speaker = ConfirmationSpeaker(ref.read(memoriesReelApiProvider));
unawaited(speaker.prefetch(language: 'hi-IN', name: 'Dadi')); // while the reel renders
await speaker.speak(language: 'hi-IN', name: 'Dadi');          // when POST /v1/reels returns
speaker.dispose();

// 2. Live preview of one cut (no server render needed)
LiveReelPreview(
  reelId: reelId,
  cut: 0,                       // cut index
  previewUrl: cut.previewUrl,   // mp4 fallback if the EDL fetch fails
  controller: LiveReelPreviewController(), // optional: play/pause/toggle/reload
  autoplay: true, loop: true, language: 'hi-IN',
);

// 3. Editor page (plain widget; wrap in a route)
ReelEditorPage(
  reelId: reelId,
  cut: 0,
  language: 'hi-IN',
  memberName: 'Dadi',          // sent with POST /shared
  previewUrl: cut.previewUrl,  // optional
  finalUrl: cut.finalUrl,      // optional; otherwise Share calls POST /final/{cut}
  onUpdated: (ReelCutResult r) {},
  onShared: (String target) {},
);
```

All widgets get `ReelApi` from `memoriesReelApiProvider` (Riverpod) unless you pass `api:`. The base URL is `kMemoriesDirectorBaseUrl` in `config.dart`. The barrel `reel.dart` hides that name because `camera/config.dart` defines the same one.
