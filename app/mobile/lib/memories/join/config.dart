/// Memories "director" backend configuration.
///
/// Public, non-secret values only. Flagsmith client (environment) keys are
/// public by design, but we read flags through the director so none is needed.
const String kDirectorBaseUrl = 'https://memories-3870f5.centralindia.cloudapp.azure.com/director';

/// Optional Flagsmith client-side environment key. Left empty on purpose: the
/// app reads flags through `GET /v1/members/flags` on the director instead.
const String kFlagsmithClientKey = '';

/// Custom URL scheme used by invite QR codes: `memories://join?code=..&server=..`.
const String kJoinScheme = 'memories';
const String kJoinHost = 'join';

/// Network timeout for director calls.
const Duration kDirectorTimeout = Duration(seconds: 20);
