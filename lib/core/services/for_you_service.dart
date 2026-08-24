import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/models/models.dart';
import '../../services/skin_scan_firestore_service.dart';
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
      final vitals = await VitalsFirestoreService.instance.fetchScans();
      final latestBpm = vitals.isNotEmpty ? vitals.first.bpm : null;
      final bpmTrend = _describeBpmTrend(vitals);
      final skinTrend = await _describeSkinTrend();

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
      if (bpmTrend != null) context.writeln(bpmTrend);
      if (skinTrend != null) context.writeln(skinTrend);
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
          "wellness filler. If a week-over-week trend (heart rate or skin) "
          "is given, prefer building the tip around that real trend over "
          "static facts like conditions/medications. Ground it in the "
          "actual context given; never invent conditions, symptoms, or "
          "numbers not present in it. "
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

  /// Compares this week's average heart rate against the week before —
  /// this is the kind of real, data-backed observation ("your resting
  /// heart rate has been trending up") that makes "For you" feel like it
  /// actually looked at something, instead of generic wellness copy.
  static String? _describeBpmTrend(List<VitalsRecord> vitals) {
    if (vitals.length < 2) return null;
    final now = DateTime.now();
    final thisWeek = vitals.where((r) => now.difference(r.date).inDays <= 7).toList();
    final lastWeek = vitals
        .where((r) =>
    now.difference(r.date).inDays > 7 && now.difference(r.date).inDays <= 14)
        .toList();
    if (thisWeek.isEmpty || lastWeek.isEmpty) return null;

    final avgThis = thisWeek.map((r) => r.bpm).reduce((a, b) => a + b) / thisWeek.length;
    final avgLast = lastWeek.map((r) => r.bpm).reduce((a, b) => a + b) / lastWeek.length;
    final diff = avgThis - avgLast;
    if (diff.abs() < 3) return null; // not a meaningful change — don't manufacture a trend

    final direction = diff > 0 ? 'up' : 'down';
    return 'Average resting heart rate this week (${avgThis.round()} BPM) is '
        '$direction ${diff.abs().round()} BPM versus last week (${avgLast.round()} BPM).';
  }

  /// Same idea for skin-scan metrics: compares the most recent scan to the
  /// oldest one in the last 30 days, per metric, and surfaces whichever
  /// metric moved the most.
  static Future<String?> _describeSkinTrend() async {
    try {
      final scans = await SkinScanFirestoreService.instance.fetchScans();
      if (scans.length < 2) return null;
      final now = DateTime.now();
      final recent = scans.where((s) => now.difference(s.date).inDays <= 30).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (recent.length < 2) return null;

      final earliest = recent.first;
      final latest = recent.last;
      String? biggestMetric;
      double biggestDelta = 0;
      for (final label in latest.metrics.keys) {
        final before = earliest.metrics[label];
        final after = latest.metrics[label];
        if (before == null || after == null) continue;
        final delta = after - before;
        if (delta.abs() > biggestDelta.abs()) {
          biggestDelta = delta;
          biggestMetric = label;
        }
      }
      if (biggestMetric == null || biggestDelta.abs() < 0.05) return null; // <5% — noise, not a trend

      final direction = biggestDelta > 0 ? 'improved' : 'changed';
      return 'Skin scan "$biggestMetric" score has $direction by '
          '${(biggestDelta.abs() * 100).round()}% over the last 30 days.';
    } catch (e) {
      debugPrint('[ForYouService] _describeSkinTrend: error — $e');
      return null;
    }
  }
}