# Memories: join / elder / post — integration notes

All code lives in `lib/memories/{join,elder,post}/` and tests in `test/memories/{join,elder,post}/`.
No routes are registered (no codegen needed): pages open with `Navigator`/`pushNativeRoute`, sheets with `showModalBottomSheet`.

## pubspec.yaml

```yaml
  mobile_scanner: ^7.5.0   # already added by integration
```
Everything else is already a dependency: `http`, `share_plus` (10.x `Share.share/shareXFiles`), `url_launcher`,
`path_provider`, `hooks_riverpod`. No `app_links` (Flutter's built-in deep linking + auto_route `deepLinkBuilder`
handles `memories://join` at cold start and on resume). No Flagsmith SDK (flags come from the director).

## AndroidManifest.xml (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="false" />

<!-- inside the MainActivity <activity> -->
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="memories" android:host="join" />
</intent-filter>
```
(Flutter ≥ 3.27 enables `flutter_deeplinking_enabled` by default; nothing else needed.)

## iOS (`ios/Runner/Info.plist`), if building iOS

Add `<string>memories</string>` to the `CFBundleURLSchemes` array that contains `immich`.
`NSCameraUsageDescription` already exists (consider wording: "Scan the QR code to join your family's event").

## One-line hooks in existing files

| File | Hook |
|---|---|
| `lib/main.dart` `_deepLinkBuilder`, right after `isColdStart` | `if (JoinDeepLinkHandler.canHandle(deepLink.uri)) return JoinDeepLinkHandler.handle(deepLink, ref, isColdStart: isColdStart);` |
| `lib/main.dart` `MaterialApp.router(builder:)` | wrap the router child: `ElderModeScope(child: child!)` |
| Login page (e.g. `lib/pages/login/login.page.dart`, below the form) | `TextButton(onPressed: () => JoinEventPage.open(context), child: const Text('Join a family event'))` |
| Album page app bar / menu (host) | `IconButton(icon: const Icon(Icons.qr_code_2_rounded), onPressed: () => showInviteSheet(context, album.id))` |
| Reel result / editor screen | `showPostToSocialsSheet(context, reelId: reelId, cut: cutIndex, caption: cut.title, finalUrl: cut.finalUrl)` |
| Anywhere elder-aware (voice-first UI) | `final elder = ref.watch(elderSettingsProvider); // .textScale .voiceFirst .language .ttsSpeaker` |

Imports:
```dart
import 'package:immich_mobile/memories/join/join_deep_link_handler.dart';
import 'package:immich_mobile/memories/join/join_event_page.dart';
import 'package:immich_mobile/memories/join/invite_sheet.dart';
import 'package:immich_mobile/memories/elder/elder_mode_scope.dart';
import 'package:immich_mobile/memories/elder/elder_mode_controller.dart';
import 'package:immich_mobile/memories/post/post_to_socials_sheet.dart';
```

## Join flow (what happens)

1. `JoinEventPage` → "Scan the QR" (`QrScanPage`, mobile_scanner) or typed code → `JoinLink.tryParse`
   (accepts `memories://join?code=&server=`, the https `web_url` with `?code=` or `/join/<code>`, or a bare code).
2. Name + language chips + kid/adult/elder → `JoinService.join`:
   `POST {server or kDirectorBaseUrl}/v1/join/redeem` (falls back to the default director if the QR's server 404s/unreachable)
   → logout if someone is signed in → `authProvider.validateServerUrl(server_url)` → `serverInfoProvider.getServerInfo()`
   → `authProvider.login(email, password)` → save `MemberProfile` (JSON file in app support dir)
   → gallery permission → websocket connect → `syncRemote()` (≤45 s) → `remoteAlbumService.get(album_id)`.
3. Navigates `replaceAll([TabShellRoute()])` then `push(RemoteAlbumRoute(album))` (album omitted if sync didn't finish).
