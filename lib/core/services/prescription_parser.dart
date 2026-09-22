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

/// Best-effort extraction of a course duration (in days) from free text.
/// Used as a safety net whenever a numeric duration wasn't already
/// returned by the AI — e.g. Gemini's structured JSON came back without
/// "durationDays", or the app fell back to the legacy heuristic parser.
/// Understands English, Roman Urdu, and Urdu-script day/week/month
/// phrasing, plus the "x/7" / "x/52" / "x/12" (days/weeks/months)
/// shorthand doctors often use.
int? extractDurationDays(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;

  // "x/7" = x days, "x/52" = x weeks, "x/12" = x months.
  final shorthand = RegExp(r'\b(\d{1,3})\s*/\s*(7|12|52)\b').firstMatch(t);
  if (shorthand != null) {
    final n = int.parse(shorthand.group(1)!);
    switch (shorthand.group(2)) {
      case '7':
        return n;
      case '52':
        return n * 7;
      case '12':
        return n * 30;
    }
  }

  int? tryUnit({
    required List<RegExp> numbered,
    required List<RegExp> singular,
    required int perUnit,
  }) {
    for (final re in numbered) {
      final m = re.firstMatch(t);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null) return n * perUnit;
      }
    }
    for (final re in singular) {
      if (re.hasMatch(t)) return perUnit;
    }
    return null;
  }

  final months = tryUnit(
    numbered: [
      RegExp(r'(\d+)\s*(months?|mahin[ae]?s?|mah\b)', caseSensitive: false),
      RegExp(r'(\d+)\s*(ماہ|مہینے|مہینہ)'),
    ],
    singular: [
      RegExp(r'\b(a|one|ek|aik)\s+(month|mah)\b', caseSensitive: false),
      RegExp(r'(ایک)\s*(ماہ|مہینہ)'),
    ],
    perUnit: 30,
  );
  if (months != null) return months;

  final weeks = tryUnit(
    numbered: [
      RegExp(r'(\d+)\s*(weeks?|haft[ae]y?)\b', caseSensitive: false),
      RegExp(r'(\d+)\s*(ہفتے|ہفتہ|ہفتوں)'),
    ],
    singular: [
      RegExp(r'\b(a|one|ek|aik)\s+week\b', caseSensitive: false),
      RegExp(r'(ایک)\s*(ہفتہ)'),
    ],
    perUnit: 7,
  );
  if (weeks != null) return weeks;

  return tryUnit(
    numbered: [
      RegExp(r'(\d+)\s*(days?|din)\b', caseSensitive: false),
      RegExp(r'(\d+)\s*دن'),
    ],
    singular: const [],
    perUnit: 1,
  );
}

/// Everything on a prescription that isn't a medicine — patient/doctor
/// details, diagnosis, and any advice that applies to the whole
/// prescription rather than one item. Parsed from the same Gemini JSON
/// [getMedsFromOcr] reads the medicines from, so the two always agree
/// about what was actually on the page.
class PrescriptionMetadata {
  const PrescriptionMetadata({
    this.patientName,
    this.patientAge,
    this.doctorName,
    this.clinicName,
    this.date,
    this.diagnosis,
    this.generalAdvice,
    this.followUp,
  });

  static const empty = PrescriptionMetadata();

  final String? patientName;
  final String? patientAge;
  final String? doctorName;
  final String? clinicName;
  final String? date;
  final String? diagnosis;
  final String? generalAdvice;
  final String? followUp;

  bool get hasAnyDetails =>
      _clean(patientName) != null ||
          _clean(patientAge) != null ||
          _clean(doctorName) != null ||
          _clean(clinicName) != null ||
          _clean(date) != null ||
          _clean(diagnosis) != null;

  bool get hasNotes => _clean(generalAdvice) != null || _clean(followUp) != null;
}

/// A field is only worth showing if it's non-empty and the model didn't
/// just echo back a literal "null"/"n/a" placeholder instead of leaving
/// the JSON value actually null.
String? _clean(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower == 'null' || lower == 'n/a' || lower == 'none' || lower == 'unknown') {
    return null;
  }
  return trimmed;
}

/// Parses the patient/doctor/diagnosis/advice fields Gemini returns
/// alongside the medications array. Best-effort and silent on failure —
/// this is supplementary information, so a malformed or legacy (pre-
/// metadata) JSON payload should still let [getMedsFromOcr] work exactly
/// as before rather than throwing.
PrescriptionMetadata extractPrescriptionMetadata(String ocrText) {
  if (ocrText.trim().isEmpty) return PrescriptionMetadata.empty;
  try {
    final String cleanJson =
    ocrText.replaceAll('```json', '').replaceAll('```', '').trim();
    final data = jsonDecode(cleanJson);
    if (data is! Map) return PrescriptionMetadata.empty;
    return PrescriptionMetadata(
      patientName: data['patientName']?.toString(),
      patientAge: data['patientAge']?.toString(),
      doctorName: data['doctorName']?.toString(),
      clinicName: data['clinicName']?.toString(),
      date: data['date']?.toString(),
      diagnosis: data['diagnosis']?.toString(),
      generalAdvice: data['generalAdvice']?.toString(),
      followUp: data['followUp']?.toString(),
    );
  } catch (_) {
    return PrescriptionMetadata.empty;
  }
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
      final int? aiDuration = durationRaw == null
          ? null
          : int.tryParse(durationRaw.toString());
      // The AI sometimes leaves durationDays null even though the course
      // length was written in plain text (e.g. "for 2 months") inside
      // instructions or the dose line — catch that here instead of
      // silently dropping it.
      final int? duration = aiDuration ??
          extractDurationDays(
              '${m['instructions'] ?? ''} ${m['dose'] ?? ''} ${m['name'] ?? ''}');
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
///
/// [metadata] carries everything on the page that isn't a medicine —
/// patient/doctor details, diagnosis, general advice, follow-up — so the
/// summary reads like an actual clinical record instead of just a bare
/// medicine list. It's optional (and every field within it is optional)
/// because older saved history entries, or a prescription that genuinely
/// didn't have that information printed on it, won't have it.
String buildProfessionalSummary(
    List<ParsedMedicine> meds, {
      DateTime? scannedAt,
      PrescriptionMetadata? metadata,
    }) {
  final valid = meds.where((m) => m.name.trim().isNotEmpty).toList();
  final meta = metadata ?? PrescriptionMetadata.empty;
  if (valid.isEmpty && !meta.hasAnyDetails) {
    return 'No medicines could be confidently read from this prescription.';
  }

  final date = scannedAt ?? DateTime.now();
  final fallbackDateLabel =
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  // Prefer the date actually printed on the prescription over today's
  // date (when we scanned it) — they're frequently different days.
  final dateLabel = _clean(meta.date) ?? fallbackDateLabel;

  final buffer = StringBuffer();
  buffer.writeln('PRESCRIPTION SUMMARY — $dateLabel');

  // Patient / doctor / clinic / diagnosis header block — only the lines
  // that were actually present on the page are shown, so this never pads
  // itself out with empty "Patient: —" placeholders.
  final patientLine = [
    if (_clean(meta.patientName) != null) meta.patientName!.trim(),
    if (_clean(meta.patientAge) != null) meta.patientAge!.trim(),
  ].join(', ');
  if (patientLine.isNotEmpty) buffer.writeln('Patient: $patientLine');
  if (_clean(meta.doctorName) != null) {
    buffer.writeln('Doctor: ${meta.doctorName!.trim()}');
  }
  if (_clean(meta.clinicName) != null) {
    buffer.writeln('Clinic: ${meta.clinicName!.trim()}');
  }
  if (_clean(meta.diagnosis) != null) {
    buffer.writeln('Diagnosis: ${meta.diagnosis!.trim()}');
  }

  buffer.writeln(
      '${valid.length} medicine${valid.length == 1 ? '' : 's'} identified');
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

  // General advice / follow-up apply to the whole prescription, not one
  // medicine — shown as their own section after the medicine list, the
  // way a real Rx summary separates "take these" from "also do this".
  if (meta.hasNotes) {
    buffer.writeln('NOTES');
    if (_clean(meta.generalAdvice) != null) {
      buffer.writeln('   • ${meta.generalAdvice!.trim()}');
    }
    if (_clean(meta.followUp) != null) {
      buffer.writeln('   • Follow-up: ${meta.followUp!.trim()}');
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

// Matches the amount-to-take part of a dose line: a number followed by
// either a strength unit (mg/ml/g/IU) or a quantity/measure word — the
// latter in English, Roman Urdu, and Urdu script, since Pakistani
// prescriptions frequently give the quantity ("1 tablet", "2 goli", "ایک
// چمچ") instead of, or alongside, the strength. This is only the
// last-resort heuristic fallback used when the AI didn't return clean
// JSON; the primary Gemini pass already understands all these forms
// natively and additionally combines strength + quantity when both are
// written (see the prompt in gemini_service.dart).
final RegExp _doseUnit = RegExp(
  r'(\d+(?:\.\d+)?)\s?'
  r'(mg|mcg|ml|cc|g|iu|gm'
  r'|tabs?|tablets?'
  r'|caps?|capsules?'
  r'|goli(?:yan)?'
  r'|cham+ach'
  r'|drops?|boond|qatray?'
  r'|گولی(?:اں)?|چمچ|قطرے?|قطرہ)\b',
  caseSensitive: false,
);

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
    final matches = _doseUnit.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final doseMatch = matches.first;

    // Capture name: search before the dose unit
    String name = line.substring(0, doseMatch.start).trim();
    // Clean up name (remove bullet points, numbers, etc.)
    name = name.replaceFirst(RegExp(r'^[\d.\)\-•\s]+'), '').trim();

    if (name.isEmpty || name.length < 2) continue;

    // A line can carry BOTH the strength ("500mg") and a separate
    // quantity/measure ("2 tablets", "1 chamach") — combine every match
    // on the line instead of only the first, so neither part is silently
    // dropped from the reminder that gets saved.
    final String dose = matches
        .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim())
        .join(' — ');

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
      durationDays: extractDurationDays(line),
      times: defaultTimesFor(timesPerDay),
      confidence: 'high', // Legacy always high
    ));
  }

  return meds;
}