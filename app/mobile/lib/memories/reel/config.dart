// Configuration for the Memories reel features (voice prompt, live preview, editor).

/// Public base URL of the Memories director API.
const String kMemoriesDirectorBaseUrl = 'https://memories-3870f5.centralindia.cloudapp.azure.com/director';

/// Default language for prompts, captions and spoken confirmations.
const String kReelDefaultLanguage = 'hi-IN';

/// Longest voice prompt we record before stopping automatically.
const Duration kVoicePromptMaxDuration = Duration(seconds: 25);

/// Recordings shorter than this are treated as accidental taps.
const Duration kVoicePromptMinDuration = Duration(milliseconds: 700);

/// How far ahead of a video clip's start the preview initialises its player.
const double kPreviewPreloadAheadS = 1.5;

/// Fade length used when the EDL asks for a fade but does not say how long.
const double kDefaultFadeS = 0.35;

/// Drift between the music clock and a video clip that triggers a re-seek.
const double kVideoResyncThresholdS = 0.25;

/// Ordinary JSON calls.
const Duration kReelHttpTimeout = Duration(seconds: 20);

/// Calls that may render or transcribe on the server (voice prompt, edit, final render).
const Duration kReelSlowHttpTimeout = Duration(seconds: 90);

/// Music moods the director understands (see server director.py MOODS).
const List<String> kReelMusicMoods = ['joyful', 'emotional', 'calm', 'festive', 'candid', 'funny', 'formal'];
