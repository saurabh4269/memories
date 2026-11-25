/// Tiny, self-contained string table for the Memories camera so it can follow the
/// *member's* language (which may differ from the app locale). Falls back to English.
class CameraStrings {
  const CameraStrings._(this._t);

  final Map<String, String> _t;

  factory CameraStrings.of(String language) {
    final code = _normalize(language);
    return CameraStrings._(_tables[code] ?? _en);
  }

  static String _normalize(String language) {
    final l = language.trim().toLowerCase();
    if (l.startsWith('hi') || l == 'hindi' || l == 'हिन्दी' || l == 'हिंदी') {
      return 'hi';
    }
    return l.split(RegExp('[-_]')).first;
  }

  String _get(String key) => _t[key] ?? _en[key]!;

  String get tapHoldHint => _get('tapHoldHint');
  String get recording => _get('recording');
  String get holdStraight => _get('holdStraight');
  String get uploading => _get('uploading');
  String get uploaded => _get('uploaded');
  String get uploadFailed => _get('uploadFailed');
  String get cameraUnavailable => _get('cameraUnavailable');
  String get permissionNeeded => _get('permissionNeeded');
  String get openSettings => _get('openSettings');
  String get shotIdeas => _get('shotIdeas');
  String get flip => _get('flip');
  String get flash => _get('flash');
  String get grid => _get('grid');
  String get timer => _get('timer');
  String get close => _get('close');
  String get missing => _get('missing');

  String moments(int moments, int people) =>
      _get('moments').replaceAll('{n}', '$moments').replaceAll('{m}', '$people');

  String uploadingCount(int n) => _get('uploadingCount').replaceAll('{n}', '$n');

  static const Map<String, String> _en = {
    'tapHoldHint': 'Tap for photo · Hold for video',
    'recording': 'Recording',
    'holdStraight': 'Hold the phone straight',
    'uploading': 'Uploading',
    'uploadingCount': 'Uploading {n}',
    'uploaded': 'Added to album',
    'uploadFailed': 'Upload failed · tap to retry',
    'cameraUnavailable': 'Camera is not available',
    'permissionNeeded': 'Please allow camera access to take photos',
    'openSettings': 'Open settings',
    'shotIdeas': 'Shot ideas',
    'flip': 'Flip camera',
    'flash': 'Flash',
    'grid': 'Grid',
    'timer': 'Timer',
    'close': 'Close',
    'missing': 'Missing',
    'moments': '{n} moments from {m} people',
  };

  static const Map<String, String> _hi = {
    'tapHoldHint': 'फ़ोटो के लिए दबाएँ · वीडियो के लिए दबाए रखें',
    'recording': 'रिकॉर्डिंग',
    'holdStraight': 'फ़ोन सीधा पकड़ें',
    'uploading': 'अपलोड हो रहा है',
    'uploadingCount': '{n} अपलोड हो रहे हैं',
    'uploaded': 'एल्बम में जुड़ गया',
    'uploadFailed': 'अपलोड नहीं हुआ · फिर से दबाएँ',
    'cameraUnavailable': 'कैमरा उपलब्ध नहीं है',
    'permissionNeeded': 'फ़ोटो लेने के लिए कैमरा की अनुमति दें',
    'openSettings': 'सेटिंग्स खोलें',
    'shotIdeas': 'फ़ोटो के सुझाव',
    'flip': 'कैमरा बदलें',
    'flash': 'फ़्लैश',
    'grid': 'ग्रिड',
    'timer': 'टाइमर',
    'close': 'बंद करें',
    'missing': 'छूट गया',
    'moments': '{m} लोगों के {n} पल',
  };

  static const Map<String, Map<String, String>> _tables = {'en': _en, 'hi': _hi};
}
