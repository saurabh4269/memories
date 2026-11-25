/// Languages offered on the join form, labelled in their own script.
class MemoriesLanguage {
  final String code;
  final String nativeName;
  final String englishName;

  const MemoriesLanguage(this.code, this.nativeName, this.englishName);
}

const List<MemoriesLanguage> kMemoriesLanguages = [
  MemoriesLanguage('hi', 'हिंदी', 'Hindi'),
  MemoriesLanguage('en', 'English', 'English'),
  MemoriesLanguage('ta', 'தமிழ்', 'Tamil'),
  MemoriesLanguage('bn', 'বাংলা', 'Bengali'),
  MemoriesLanguage('mr', 'मराठी', 'Marathi'),
  MemoriesLanguage('te', 'తెలుగు', 'Telugu'),
  MemoriesLanguage('kn', 'ಕನ್ನಡ', 'Kannada'),
  MemoriesLanguage('gu', 'ગુજરાતી', 'Gujarati'),
  MemoriesLanguage('ml', 'മലയാളം', 'Malayalam'),
  MemoriesLanguage('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
];

MemoriesLanguage? languageByCode(String? code) {
  if (code == null) {
    return null;
  }
  final base = code.toLowerCase().split(RegExp('[-_]')).first;
  for (final l in kMemoriesLanguages) {
    if (l.code == base) {
      return l;
    }
  }
  return null;
}

/// Who is joining; drives elder mode defaults.
enum MemberRole {
  kid('kid', 'Kid', '🧒'),
  adult('adult', 'Adult', '🧑'),
  elder('elder', 'Elder', '👵');

  final String wire;
  final String label;
  final String emoji;

  const MemberRole(this.wire, this.label, this.emoji);

  static MemberRole fromWire(String? value) =>
      MemberRole.values.firstWhere((r) => r.wire == value?.toLowerCase(), orElse: () => MemberRole.adult);
}
