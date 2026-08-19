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
      return ParsedMedicine(
        name: m['name']?.toString() ?? 'Unknown',
        dose: m['dose']?.toString() ?? '',
        timesPerDay: tpd,
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

/// Formats a [TimeOfDay] as "8:00 PM" — fixed 12-hour format.
String formatTimeOfDay(TimeOfDay t) {
  final int hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final String minute = t.minute.toString().padLeft(2, '0');
  final String period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

final RegExp _doseUnit =
    RegExp(r'(\d+(?:\.\d+)?)\s?(mg|mcg|ml|g|iu|gm|tab)\b', caseSensitive: false);

final Map<RegExp, int> _freqPatterns = {
  RegExp(r'\bonce\s+(a\s+)?day\b|\bonce\s+daily\b|\bOD\b|\bQD\b|\b1\s*x\s*(a\s+)?day\b',
      caseSensitive: false): 1,
  RegExp(
      r'\btwice\s+(a\s+)?day\b|\btwice\s+daily\b|\bBID\b|\bBD\b|\b2\s*x\s*(a\s+)?day\b|\b1\s*\+\s*0\s*\+\s*1\b',
      caseSensitive: false): 2,
  RegExp(
      r'\bthrice\s+(a\s+)?day\b|\bthree\s+times\s+(a\s+)?day\b|\bTID\b|\bTDS\b|\b3\s*x\s*(a\s+)?day\b|\b1\s*\+\s*1\s*\+\s*1\b',
      caseSensitive: false): 3,
  RegExp(r'\bfour\s+times\s+(a\s+)?day\b|\bQID\b|\b4\s*x\s*(a\s+)?day\b',
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
