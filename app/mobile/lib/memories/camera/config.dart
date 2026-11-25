/// Configuration constants for the Memories in-app camera and shot coach.
library;

/// Base URL of the Memories "director" service (see docs/API-CONTRACT.md).
const String kMemoriesDirectorBaseUrl = 'https://memories-3870f5.centralindia.cloudapp.azure.com/director';

/// How often the shot coach is refreshed while the camera is open.
const Duration kCoachPollInterval = Duration(seconds: 30);

/// The shot coach is also refreshed after this many captures.
const int kCoachRefreshEveryCaptures = 5;

/// Network timeout for director requests.
const Duration kDirectorTimeout = Duration(seconds: 8);

/// Maximum length of a hold-to-record video.
const Duration kMaxVideoDuration = Duration(seconds: 30);

/// The coach endpoint returns at most this many cards; we show at most this many.
const int kMaxCoachCards = 3;

/// Key used when tagging uploaded assets via the Immich asset metadata API.
const String kMemoriesMetadataKey = 'memories';
