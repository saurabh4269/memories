# Memories camera: dependency & permission needs

## pubspec.yaml (`dependencies:`)

```yaml
  camera: ^0.12.2        # resolves camera_android_camerax 0.7.6+2, camera_avfoundation 0.11.1
  sensors_plus: ^7.1.1   # tilt/level warning (optional at runtime; hidden if no sensor)
```

Both are already present in `pubspec.yaml` (added by the integration agent).
Also used, and already dependencies: `photo_manager`, `http`, `path`, `path_provider`,
`permission_handler`, `hooks_riverpod`, `logging`, `openapi`.

## Android: `android/app/src/main/AndroidManifest.xml`

Already present:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

Saving to the gallery goes through photo_manager, which uses the media permissions Immich already declares.

## iOS: `ios/Runner/Info.plist`

Already present: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`.
Not needed: `NSMotionUsageDescription` (raw accelerometer access via sensors_plus does not require it).
