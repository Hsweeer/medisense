import 'package:flutter/material.dart';
import 'dart:convert';

/// One medicine parsed (best-effort) from OCR'd prescription text.
class ParsedMedicine {
  ParsedMedicine({
    required this.name,
    this.dose = '',
    this.timesPerDay = 1,
    this.durationDays,
    this.instructions = '',
    this.confidence = 'high',
    List<TimeOfDay>? times,
  }) : times = times ?? defaultTimesFor(timesPerDay);

  factory ParsedMedicine.blank() => ParsedMedicine(name: '', timesPerDay: 1, confidence: 'high');

  String name;
  String dose;
  int timesPerDay;
  int? durationDays;
  String instructions;
  String confidence;
  List<TimeOfDay> times;
}

/// Helper to get medicine list from a ChatMessage. Handles both new Gemini JSON
/// and old raw text fallback formats.
List<ParsedMedicine> getMedsFromOcr(String ocrText) {
  if (ocrText.trim().isEmpty) return [];

  try {
    // Attempt to parse as Gemini JSON first
    final String cleanJson = ocrText.replaceAll('```json', '').replaceAll('```', '').trim();
    final data = jsonDecode(cleanJson);
    final medsList = data['medications'] as List? ?? [];

    return medsList.map((m) {
      final int tpd = int.tryParse(m['timesPerDay']?.toString() ?? '1') ?? 1;
      final durationRaw = m['durationDays'];
      final int? duration = durationRaw == null
          ? null
          : int.tryParse(durationRaw.toString());
      return ParsedMedicine(
        name: m['name']?.toString() ?? 'Unknown',
        dose: m['dose']?.toString() ?? '',
        timesPerDay: tpd,
        durationDays: duration,
        instructions: m['instructions']?.toString() ?? '',
        confidence: m['confidence']?.toString() ?? 'high',
        times: defaultTimesFor(tpd),
      );
    }).toList();
  } catch (_) {
    // If not JSON, use the old heuristic regex parser
    return parsePrescriptionText(ocrText);
  }
}

/// Sensible starting clock times for a given daily frequency.
List<TimeOfDay> defaultTimesFor(int timesPerDay) {
  switch (timesPerDay) {
    case 1:
      return [const TimeOfDay(hour: 9, minute: 0)];
    case 2:
      return [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ];
    case 3:
      return [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ];
    case 4:
      return [
        const TimeOfDay(hour: 6, minute: 0),
        const TimeOfDay(hour: 12, minute: 0),
        const TimeOfDay(hour: 18, minute: 0),
        const TimeOfDay(hour: 23, minute: 59),
      ];
    default:
      if (timesPerDay < 1) return [const TimeOfDay(hour: 9, minute: 0)];
      final gapMinutes = (24 * 60) ~/ timesPerDay;
      const startMinutes = 8 * 60;
      return List.generate(timesPerDay, (i) {
        final total = (startMinutes + gapMinutes * i) % (24 * 60);
        return TimeOfDay(hour: total ~/ 60, minute: total % 60);
      });
  }
}

/// Builds a clean, professional Rx-style summary of the whole prescription
/// from the parsed medicines — used in the chat card, the review screen,
/// and saved into the user's prescription history so it reads well weeks
/// later without needing the original photo.
String buildProfessionalSummary(List<ParsedMedicine> meds, {DateTime? scannedAt}) {
  final valid = meds.where((m) => m.name.trim().isNotEmpty).toList();
  if (valid.isEmpty) {
    return 'No medicines could be confidently read from this prescription.';
  }

  final date = scannedAt ?? DateTime.now();
  final dateLabel =
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  final buffer = StringBuffer();
  buffer.writeln('PRESCRIPTION SUMMARY — $dateLabel');
  buffer.writeln('${valid.length} medicine${valid.length == 1 ? '' : 's'} identified');
  buffer.writeln();

  for (var i = 0; i < valid.length; i++) {
    final m = valid[i];
    buffer.writeln('${i + 1}. ${m.name.trim()}${m.dose.trim().isEmpty ? '' : ' — ${m.dose.trim()}'}');

    final freqLabel = m.timesPerDay == 1 ? 'Once daily' : '${m.timesPerDay}× daily';
    final timesLabel = m.times.map(formatTimeOfDay).join(', ');
    buffer.writeln('   • Frequency: $freqLabel ($timesLabel)');

    if (m.durationDays != null) {
      buffer.writeln('   • Duration: ${m.durationDays} day${m.durationDays == 1 ? '' : 's'}');
    }
    if (m.instructions.trim().isNotEmpty) {
      buffer.writeln('   • Instructions: ${m.instructions.trim()}');
    }
    if (m.confidence == 'low') {
      buffer.writeln('   • ⚠ Low confidence — please verify against the original prescription.');
    }
    buffer.writeln();
  }

  buffer.write('This summary is generated from a scanned image and may contain '
      'reading errors — always confirm with your prescribing doctor or pharmacist '
      'before relying on it.');

  return buffer.toString().trim();
}

/// Formats a [TimeOfDay] as "8:00 PM" — fixed 12-hour format.
String formatTimeOfDay(TimeOfDay t) {
  final int hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final String minute = t.minute.toString().padLeft(2, '0');
  final String period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

final RegExp _doseUnit =
RegExp(r'(\d+(?:\.\d+)?)\s?(mg|mcg|ml|g|iu|gm|tab)\b', caseSensitive: false);

// Frequency shorthand across English, Roman Urdu, and Urdu script — this is
// only the last-resort heuristic fallback used when the AI didn't return
// clean JSON; the primary Gemini pass already understands all three natively.
final Map<RegExp, int> _freqPatterns = {
  RegExp(
      r'\bonce\s+(a\s+)?day\b|\bonce\s+daily\b|\bOD\b|\bQD\b|\b1\s*x\s*(a\s+)?day\b'
      r'|din\s*(mein|main)?\s*(aik|1|ek)\s*bar|روزانہ\s*ایک\s*بار|دن\s*میں\s*ایک\s*بار',
      caseSensitive: false): 1,
  RegExp(
      r'\btwice\s+(a\s+)?day\b|\btwice\s+daily\b|\bBID\b|\bBD\b|\b2\s*x\s*(a\s+)?day\b|\b1\s*\+\s*0\s*\+\s*1\b'
      r'|din\s*(mein|main)?\s*(do|2)\s*bar|subah\s*sh?a?am|صبح\s*و?\s*شام|دن\s*میں\s*دو\s*بار|دن\s*میں\s*2\s*بار',
      caseSensitive: false): 2,
  RegExp(
      r'\bthrice\s+(a\s+)?day\b|\bthree\s+times\s+(a\s+)?day\b|\bTID\b|\bTDS\b|\b3\s*x\s*(a\s+)?day\b|\b1\s*\+\s*1\s*\+\s*1\b'
      r'|din\s*(mein|main)?\s*(teen|3)\s*bar|صبح\s*دوپہر\s*شام|دن\s*میں\s*تین\s*بار|دن\s*میں\s*3\s*بار',
      caseSensitive: false): 3,
  RegExp(
      r'\bfour\s+times\s+(a\s+)?day\b|\bQID\b|\b4\s*x\s*(a\s+)?day\b'
      r'|din\s*(mein|main)?\s*(char|4)\s*bar|دن\s*میں\s*چار\s*بار|دن\s*میں\s*4\s*بار',
      caseSensitive: false): 4,
};

/// Legacy Regex Parser (Heuristic) - Improved for tables
List<ParsedMedicine> parsePrescriptionText(String raw) {
  final List<String> lines = raw.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final List<ParsedMedicine> meds = <ParsedMedicine>[];

  for (final line in lines) {
    final doseMatch = _doseUnit.firstMatch(line);
    if (doseMatch == null) continue;

    // Capture name: search before the dose unit
    String name = line.substring(0, doseMatch.start).trim();
    // Clean up name (remove bullet points, numbers, etc.)
    name = name.replaceFirst(RegExp(r'^[\d.\)\-•\s]+'), '').trim();

    if (name.isEmpty || name.length < 2) continue;

    final String dose = doseMatch.group(0)!.replaceAll(RegExp(r'\s+'), ' ');

    int timesPerDay = 1;
    for (final entry in _freqPatterns.entries) {
      if (entry.key.hasMatch(line)) {
        timesPerDay = entry.value;
        break;
      }
    }

    meds.add(ParsedMedicine(
      name: name,
      dose: dose,
      timesPerDay: timesPerDay,
      times: defaultTimesFor(timesPerDay),
      confidence: 'high', // Legacy always high
    ));
  }

  return meds;
}