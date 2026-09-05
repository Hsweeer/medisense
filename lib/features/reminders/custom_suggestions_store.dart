import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_form_helpers.dart';

/// Persists the user's own custom suggestion chips (added via the "+"
/// button next to each form's suggestion list) so "Cricket" typed once
/// under Activities, for example, shows up as a tappable chip again next
/// time — on top of the app's built-in presets, never replacing them.
class CustomSuggestionsStore {
  CustomSuggestionsStore._();
  static final instance = CustomSuggestionsStore._();

  static const _prefixKey = 'custom_suggestions_';

  String _keyFor(ReminderCategory category) => '$_prefixKey${category.name}';

  Future<List<String>> load(ReminderCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyFor(category)) ?? const [];
  }

  /// Adds [value] to this category's custom list (case-insensitive
  /// de-duplication against both the custom list and the app's built-in
  /// suggestions) and returns the updated custom list.
  Future<List<String>> add(ReminderCategory category, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return load(category);

    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(category);
    final existing = prefs.getStringList(key) ?? <String>[];

    final alreadyKnown = [
      ...existing,
      ...category.suggestions,
    ].any((s) => s.toLowerCase() == trimmed.toLowerCase());
    if (!alreadyKnown) {
      existing.add(trimmed);
      await prefs.setStringList(key, existing);
    }
    return existing;
  }
}
