import 'package:immich_mobile/memories/reel/services/reel_api.dart';

/// User-facing text for the reel features, in Hindi (default) and English.
///
/// Kept local (instead of easy_localization keys) so this module stays
/// self-contained; [of] picks Hindi for any `hi*` language code.
class ReelStrings {
  const ReelStrings._({
    required this.previewLabel,
    required this.previewFailed,
    required this.tryAgain,
    required this.play,
    required this.tapToSpeak,
    required this.listening,
    required this.understanding,
    required this.tapToStop,
    required this.micDenied,
    required this.tooShort,
    required this.couldNotHear,
    required this.offline,
    required this.timeout,
    required this.genericError,
    required this.editTitle,
    required this.updateReel,
    required this.updating,
    required this.updated,
    required this.share,
    required this.preparingVideo,
    required this.exportOtio,
    required this.exportReady,
    required this.remove,
    required this.swap,
    required this.noAlternatives,
    required this.caption,
    required this.captionHint,
    required this.music,
    required this.moods,
    required this.clip,
    required this.undo,
    required this.removed,
    required this.cantRemoveLast,
    required this.reorderHint,
    required this.discardTitle,
    required this.discardBody,
    required this.discard,
    required this.keepEditing,
    required this.video,
    required this.reelReady,
  });

  static ReelStrings of(String language) => language.toLowerCase().startsWith('hi') ? hi : en;

  final String previewLabel;
  final String previewFailed;
  final String tryAgain;
  final String play;
  final String tapToSpeak;
  final String listening;
  final String understanding;
  final String tapToStop;
  final String micDenied;
  final String tooShort;
  final String couldNotHear;
  final String offline;
  final String timeout;
  final String genericError;
  final String editTitle;
  final String updateReel;
  final String updating;
  final String updated;
  final String share;
  final String preparingVideo;
  final String exportOtio;
  final String exportReady;
  final String remove;
  final String swap;
  final String noAlternatives;
  final String caption;
  final String captionHint;
  final String music;
  final Map<String, String> moods;
  final String clip;
  final String undo;
  final String removed;
  final String cantRemoveLast;
  final String reorderHint;
  final String discardTitle;
  final String discardBody;
  final String discard;
  final String keepEditing;
  final String video;
  final String reelReady;

  String mood(String key) => moods[key] ?? key;

  /// A kind, specific message for a failed director call.
  String error(Object e) {
    if (e is ReelApiException) {
      return switch (e.kind) {
        ReelApiErrorKind.offline => offline,
        ReelApiErrorKind.timeout => timeout,
        _ => genericError,
      };
    }
    return genericError;
  }

  static const hi = ReelStrings._(
    previewLabel: 'रील का प्रीव्यू। चलाने या रोकने के लिए टैप करें',
    previewFailed: 'अभी रील नहीं दिखा पा रहे',
    tryAgain: 'फिर से कोशिश करें',
    play: 'चलाएँ',
    tapToSpeak: 'बोलने के लिए टैप करें',
    listening: 'सुन रहे हैं…',
    understanding: 'समझ रहे हैं…',
    tapToStop: 'रुकने के लिए फिर टैप करें',
    micDenied: 'बोलने के लिए माइक की अनुमति दीजिए',
    tooShort: 'बटन दबाकर बोलिए, फिर छोड़ दीजिए',
    couldNotHear: 'ठीक से सुनाई नहीं दिया। एक बार फिर बोलिए',
    offline: 'इंटरनेट नहीं मिल रहा। थोड़ी देर बाद कोशिश करें',
    timeout: 'जवाब आने में देर हो रही है। फिर से कोशिश करें',
    genericError: 'कुछ गड़बड़ हो गई। फिर से कोशिश करें',
    editTitle: 'रील बदलें',
    updateReel: 'रील अपडेट करें',
    updating: 'रील बन रही है…',
    updated: 'रील अपडेट हो गई',
    share: 'शेयर करें',
    preparingVideo: 'वीडियो तैयार हो रहा है…',
    exportOtio: 'एडिटर के लिए भेजें (.otio)',
    exportReady: 'एडिटर फ़ाइल तैयार है',
    remove: 'हटाएँ',
    swap: 'दूसरी फ़ोटो',
    noAlternatives: 'इसकी जगह कोई और फ़ोटो नहीं मिली',
    caption: 'कैप्शन',
    captionHint: 'यहाँ लिखें (हिंदी या English)',
    music: 'संगीत',
    moods: {
      'joyful': 'खुशनुमा',
      'emotional': 'भावुक',
      'calm': 'शांत',
      'festive': 'त्योहार',
      'candid': 'सहज',
      'funny': 'मज़ेदार',
      'formal': 'औपचारिक',
    },
    clip: 'क्लिप',
    undo: 'वापस लाएँ',
    removed: 'क्लिप हटा दी',
    cantRemoveLast: 'रील में कम से कम एक क्लिप चाहिए',
    reorderHint: 'क्रम बदलने के लिए दबाकर खिसकाएँ',
    discardTitle: 'बदलाव छोड़ दें?',
    discardBody: 'आपके बदलाव अभी रील में नहीं जुड़े हैं।',
    discard: 'छोड़ दें',
    keepEditing: 'बदलते रहें',
    video: 'वीडियो',
    reelReady: 'आपकी रील तैयार है',
  );

  static const en = ReelStrings._(
    previewLabel: 'Reel preview. Tap to play or pause',
    previewFailed: "We can't show this reel right now",
    tryAgain: 'Try again',
    play: 'Play',
    tapToSpeak: 'Tap to speak',
    listening: 'Listening…',
    understanding: 'Understanding…',
    tapToStop: 'Tap again to stop',
    micDenied: 'Please allow the microphone to speak',
    tooShort: 'Hold the button while you speak',
    couldNotHear: "We didn't catch that. Please say it once more",
    offline: "No internet right now. Please try again in a moment",
    timeout: 'This is taking a while. Please try again',
    genericError: 'Something went wrong. Please try again',
    editTitle: 'Edit reel',
    updateReel: 'Update reel',
    updating: 'Making your reel…',
    updated: 'Reel updated',
    share: 'Share',
    preparingVideo: 'Preparing the video…',
    exportOtio: 'Export for editors (.otio)',
    exportReady: 'Editor file ready',
    remove: 'Remove',
    swap: 'Swap photo',
    noAlternatives: 'No other photos fit here',
    caption: 'Caption',
    captionHint: 'Type here (Hindi or English)',
    music: 'Music',
    moods: {
      'joyful': 'Joyful',
      'emotional': 'Emotional',
      'calm': 'Calm',
      'festive': 'Festive',
      'candid': 'Candid',
      'funny': 'Funny',
      'formal': 'Formal',
    },
    clip: 'Clip',
    undo: 'Undo',
    removed: 'Clip removed',
    cantRemoveLast: 'A reel needs at least one clip',
    reorderHint: 'Press and hold to reorder',
    discardTitle: 'Discard changes?',
    discardBody: "Your changes haven't been applied to the reel yet.",
    discard: 'Discard',
    keepEditing: 'Keep editing',
    video: 'Video',
    reelReady: 'Your reel is ready',
  );
}
