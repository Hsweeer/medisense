/// Builds the `searchIndex` array stored on each user document, used by
/// [CaregiverService.searchUsers] for the "Add caregiver contact" search.
/// Every token (name, each name part, phone digits, email) is expanded
/// into all of its leading prefixes so a search becomes a real
/// type-ahead: typing even a single matching character returns a hit,
/// not just a full-word match.
class UserSearchIndex {
  static List<String> build({
    required String name,
    String phone = '',
    String email = '',
  }) {
    final tokens = <String>{};

    final nameLower = name.trim().toLowerCase();
    if (nameLower.isNotEmpty) {
      _addWithPrefixes(tokens, nameLower);
      for (final part in nameLower.split(' ')) {
        if (part.isNotEmpty) _addWithPrefixes(tokens, part);
      }
    }

    final phoneDigits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phoneDigits.isNotEmpty) _addWithPrefixes(tokens, phoneDigits);

    final emailLower = email.trim().toLowerCase();
    if (emailLower.isNotEmpty) _addWithPrefixes(tokens, emailLower);

    return tokens.toList();
  }

  /// Adds [token] itself plus every leading prefix of it (1 char, 2 chars,
  /// …) so a single-character search hit works the same as a full-word
  /// one — Firestore's `arrayContains` only matches an exact array entry,
  /// so the prefixes have to be pre-computed and stored at write time.
  static void _addWithPrefixes(Set<String> tokens, String token) {
    for (var i = 1; i <= token.length; i++) {
      tokens.add(token.substring(0, i));
    }
  }
}
