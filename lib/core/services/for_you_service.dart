import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/models/models.dart';
import '../../services/vitals_firestore_service.dart';
import 'groq_service.dart';

/// Builds the home screen's "For you" card: one short, personalized piece
/// of advice grounded in the user's actual health profile and whatever
/// MedAI has picked up from chat — not a generic rotating tip.
class ForYouService {
  ForYouService._();

  /// Regenerate at most this often — personalized advice doesn't need to
  /// be re-derived every time the home screen rebuilds, just kept fresh.
  static const refreshInterval = Duration(hours: 12);

  static bool isStale(ForYouTip? tip) {
    if (tip == null) return true;
    return DateTime.now().difference(tip.generatedAt) > refreshInterval;
  }

  static Future<ForYouTip?> generate({
    required HealthProfile profile,
    required List<AiInsight> insights,
  }) async {
    try {
      final latestBpm = await VitalsFirestoreService.instance.fetchScans()
          .then((list) => list.isNotEmpty ? list.first.bpm : null);

      final context = StringBuffer();
      if (profile.conditions.isNotEmpty) {
        context.writeln('Conditions: ${profile.conditions.join(', ')}');
      }
      if (profile.allergies.isNotEmpty) {
        context.writeln('Allergies: ${profile.allergies.join(', ')}');
      }
      if (profile.medications.isNotEmpty) {
        context.writeln('Medications: ${profile.medications.join(', ')}');
      }
      if (latestBpm != null) {
        context.writeln('Most recent heart-rate scan: ${latestBpm.round()} BPM');
      }
      final recentInsights = insights.take(6).map((i) => '- (${i.type.name}) ${i.text}');
      if (recentInsights.isNotEmpty) {
        context.writeln('Recently noted from chats:');
        context.writeln(recentInsights.join('\n'));
      }

      // Nothing to personalize on yet — don't force a generic tip that
      // would just look like the same rotating advice this replaces.
      if (context.isEmpty) return null;

      const systemPrompt =
          "You are MedAI's 'For you' card generator for a health app home "
          "screen. Given a user's health context, write ONE short, "
          "specific, actionable piece of advice — the kind a thoughtful "
          "clinician would flag as relevant right now, not generic "
          "wellness filler. Ground it in the actual context given; never "
          "invent conditions, symptoms, or numbers not present in it. "
          "Never give a diagnosis or tell them to stop/start a medication "
          "unilaterally — frame anything medication-related as a "
          "conversation to have with their doctor. "
          "Respond with ONLY raw JSON, no markdown fences, no preamble, "
          "in exactly this shape: "
          '{"title": "under 6 words", "body": "1-2 short sentences, under 30 words"}';

      final raw = await GroqService.chat(
        systemPrompt: systemPrompt,
        history: [
          {'role': 'user', 'content': context.toString()},
        ],
      );

      final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      final title = (map['title'] as String?)?.trim() ?? '';
      final body = (map['body'] as String?)?.trim() ?? '';
      if (title.isEmpty || body.isEmpty) return null;

      return ForYouTip(title: title, body: body, generatedAt: DateTime.now());
    } catch (e) {
      debugPrint('[ForYouService] generate: error — $e');
      return null;
    }
  }
}