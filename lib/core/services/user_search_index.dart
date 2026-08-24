class UserSearchIndex {
  static List<String> build({
    required String name,
    String phone = '',
    String email = '',
  }) {
    final tokens = <String>{};

    final nameLower = name.trim().toLowerCase();
    if (nameLower.isNotEmpty) {
      tokens.add(nameLower);
      for (final part in nameLower.split(' ')) {
        if (part.isNotEmpty) tokens.add(part);
      }
    }

    final phoneDigits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phoneDigits.isNotEmpty) tokens.add(phoneDigits);

    final emailLower = email.trim().toLowerCase();
    if (emailLower.isNotEmpty) tokens.add(emailLower);

    return tokens.toList();
  }
}
