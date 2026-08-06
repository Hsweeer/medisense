import 'package:flutter/material.dart';

/// One medicine parsed (best-effort) from OCR'd prescription text, or added
/// manually by the user in the review screen. Every field here is editable
/// before it ever becomes a real reminder — this is a starting guess, not
/// a final answer.
class ParsedMedicine {
  ParsedMedicine({
    required this.name,
    this.dose = '',
    this.timesPerDay = 1,
    this.durationDays,
    this.instructions = '',
    List<TimeOfDay>? times,
  }) : times = times ?? defaultTimesFor(1);

  factory ParsedMedicine.blank() => ParsedMedicine(name: '', timesPerDay: 1);

  String name;
  String dose;
  int timesPerDay;
  int? durationDays;
  String instructions;
  List<TimeOfDay> times;
}

/// Sensible starting clock times for a given daily frequency, spread across
/// the day so doses aren't bunched together. The user reviews — and can
/// change every single one — before anything is saved as a reminder.
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
      // Spread evenly across a 24h clock starting at 8 AM.
      final gapMinutes = (24 * 60) ~/ timesPerDay;
      const startMinutes = 8 * 60;
      return List.generate(timesPerDay, (i) {
        final total = (startMinutes + gapMinutes * i) % (24 * 60);
        return TimeOfDay(hour: total ~/ 60, minute: total % 60);
      });
  }
}

/// "8:00 PM" — fixed 12-hour format. Must match NotificationService's
/// parser (services/notification_service.dart `_parseTimeOfDay`) and
/// reminders_screen's own formatter exactly, or the alarm silently fails
/// to schedule.
String formatTimeOfDay(TimeOfDay t) {
  final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

final RegExp _doseUnit =
    RegExp(r'(\d+(?:\.\d+)?)\s?(mg|mcg|ml|g|iu)\b', caseSensitive: false);

final Map<RegExp, int> _freqPatterns = {
  RegExp(r'\bonce\s+(a\s+)?day\b|\bonce\s+daily\b|\bOD\b|\bQD\b|\b1\s*x\s*(a\s+)?day\b',
      caseSensitive: false): 1,
  RegExp(
      r'\btwice\s+(a\s+)?day\b|\btwice\s+daily\b|\bBID\b|\bBD\b|\b2\s*x\s*(a\s+)?day\b',
      caseSensitive: false): 2,
  RegExp(
      r'\bthrice\s+(a\s+)?day\b|\bthree\s+times\s+(a\s+)?day\b|\bTID\b|\bTDS\b|\b3\s*x\s*(a\s+)?day\b',
      caseSensitive: false): 3,
  RegExp(r'\bfour\s+times\s+(a\s+)?day\b|\bQID\b|\b4\s*x\s*(a\s+)?day\b',
      caseSensitive: false): 4,
};

final RegExp _everyHours = RegExp(r'every\s+(\d{1,2})\s*hours?', caseSensitive: false);
final RegExp _durationDays = RegExp(r'(\d{1,3})\s*days?\b', caseSensitive: false);
final RegExp _nightly =
    RegExp(r'\bnightly\b|\bat\s+bedtime\b|\bbefore\s+bed\b', caseSensitive: false);

/// Best-effort extraction of medicine name / dose / daily frequency /
/// duration / instructions from raw OCR'd prescription text.
///
/// This is a heuristic, not a medical-grade parser — Tesseract's reading of
/// a doctor's *handwriting* is frequently poor, and prescriptions vary
/// wildly in layout. The review screen always shows the raw OCR text
/// alongside these guesses, and every field is editable before anything is
/// saved as a real reminder.
List<ParsedMedicine> parsePrescriptionText(String raw) {
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final meds = <ParsedMedicine>[];

  for (final line in lines) {
    final doseMatch = _doseUnit.firstMatch(line);
    if (doseMatch == null) {
      continue; // a line naming a drug almost always has a dose next to it
    }

    // Medicine name = whatever's on the line before the dose number.
    var name = line.substring(0, doseMatch.start).trim();
    // Strip leading bullets/numbering like "1.", "-", "•".
    name = name.replaceFirst(RegExp(r'^[\d.\)\-•\s]+'), '').trim();
    if (name.isEmpty || name.length > 40) continue; // not a plausible drug name

    final dose = doseMatch.group(0)!.replaceAll(RegExp(r'\s+'), ' ');

    int timesPerDay = 1;
    for (final entry in _freqPatterns.entries) {
      if (entry.key.hasMatch(line)) {
        timesPerDay = entry.value;
        break;
      }
    }
    final everyMatch = _everyHours.firstMatch(line);
    if (everyMatch != null) {
      final hours = int.tryParse(everyMatch.group(1)!) ?? 24;
      if (hours > 0) {
        var derived = (24 / hours).round();
        if (derived < 1) derived = 1;
        if (derived > 6) derived = 6;
        timesPerDay = derived;
      }
    }
    if (_nightly.hasMatch(line)) timesPerDay = 1;

    int? durationDays;
    final durMatch = _durationDays.firstMatch(line);
    if (durMatch != null) durationDays = int.tryParse(durMatch.group(1)!);

    final instructions = <String>[];
    if (RegExp(r'after\s+food', caseSensitive: false).hasMatch(line)) {
      instructions.add('After food');
    }
    if (RegExp(r'before\s+food|empty\s+stomach', caseSensitive: false).hasMatch(line)) {
      instructions.add('Before food / empty stomach');
    }
    if (RegExp(r'with\s+(a\s+)?(full\s+)?(glass\s+of\s+)?water', caseSensitive: false)
        .hasMatch(line)) {
      instructions.add('With water');
    }
    if (_nightly.hasMatch(line)) instructions.add('At night');

    meds.add(ParsedMedicine(
      name: name,
      dose: dose,
      timesPerDay: timesPerDay,
      durationDays: durationDays,
      instructions: instructions.join(' · '),
      times: defaultTimesFor(timesPerDay),
    ));
  }

  return meds;
}