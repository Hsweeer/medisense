import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';

/// Professional AI vision service using direct REST calls.
/// Optimized with a two-pass reading strategy for messy handwriting.
class GeminiService {
  GeminiService._();

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent';

  /// Pass 1: Literal Transcription
  /// Asks the model to transcribe exactly what it sees without guessing.
  static Future<String> transcribeRaw(String imagePath) async {
    try {
      final File imageFile = File(imagePath);
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      final Map<String, dynamic> requestBody = {
        "contents": [
          {
            "parts": [
              {
                "text": "SYSTEM: You are a literal transcriber fluent in English, Urdu (اردو script), "
                    "and Roman Urdu. "
                    "TASK: Transcribe exactly what is written on this prescription image, in "
                    "whatever language/script it is written in — English, Urdu script, or Roman "
                    "Urdu. Prescriptions in Pakistan are frequently a mix of English medicine "
                    "names with Urdu instructions (e.g. \"دن میں دو بار کھانے کے بعد\"), so preserve "
                    "each part in its original script; do NOT translate anything in this pass. "
                    "Do NOT interpret medicine names, do NOT guess, and do NOT structure it. "
                    "If a word is genuinely illegible, mark it as [illegible]. "
                    "OUTPUT: Provide a plain text transcription of every word seen, in its "
                    "original script."
              },
              {
                "inlineData": {
                  "mimeType": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }
        ]
      };

      final response = await http.post(
        Uri.parse('$_baseUrl?key=${ApiKeys.geminiApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Transcription Pass Error ${response.statusCode}');
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      return data['candidates']?[0]['content']?['parts']?[0]['text'] ?? '';
    } catch (e) {
      debugPrint('[GeminiService] TranscribeRaw Error: $e');
      rethrow;
    }
  }

  /// General-purpose image analysis for arbitrary photos and screenshots.
  /// Great for user-sent images that are not a prescription or skin-scan.
  static Future<String> describeImage(String imagePath, {String prompt = 'Describe what you see in this image.'}) async {
    try {
      final File imageFile = File(imagePath);
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      final Map<String, dynamic> requestBody = {
        'contents': [
          {
            'parts': [
              {
                'text': 'SYSTEM: You are a professional visual assistant chatting naturally with a user, '
                    'like a premium AI app (not a rigid form). Analyze the image with careful observation, not guessing. '
                    'Your job is to be useful, grounded, and honest.\n\n'
                    'RULES:\n'
                    '1. Answer the user\'s actual request directly and conversationally — write a normal, natural reply, '
                    'not a fixed template or labeled sections.\n'
                    '2. Only mention what is clearly visible and relevant to what was asked; don\'t force in unrelated '
                    'observations just to fill out a structure.\n'
                    '3. State uncertainty honestly (in plain sentences, not a "Confidence: High/Medium/Low" label) if the '
                    'image is blurry, cropped, low-light, or ambiguous.\n'
                    '4. Do not invent details or claim diagnosis without evidence.\n'
                    '5. Keep the reply concise — a few sentences for a simple question, more only if the user\'s request '
                    'genuinely needs it.\n'
                    '6. Only ask a follow-up question if it\'s genuinely needed to help — don\'t add one by default.\n\n'
                    'USER REQUEST: $prompt'
              },
              {
                'inlineData': {
                  'mimeType': 'image/jpeg',
                  'data': base64Image,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'topP': 0.9,
          'topK': 32,
        }
      };

      final response = await http.post(
        Uri.parse('$_baseUrl?key=${ApiKeys.geminiApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Image Analysis Error ${response.statusCode}');
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final String? text = data['candidates']?[0]['content']?['parts']?[0]['text'];

      if (text == null || text.trim().isEmpty) {
        throw Exception('AI returned an empty image analysis response.');
      }

      return text.trim();
    } catch (e) {
      debugPrint('[GeminiService] DescribeImage Error: $e');
      rethrow;
    }
  }

  /// Pass 2: Structure into Data
  /// Uses both the original image and the raw transcription to produce structured JSON.
  static Future<String> readPrescription(String imagePath) async {
    try {
      // 1. Get raw transcription first
      final String rawTranscription = await transcribeRaw(imagePath);
      debugPrint('[GeminiService] Raw Transcription: $rawTranscription');

      // 2. Structure into JSON using image + transcription context
      final File imageFile = File(imagePath);
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      final Map<String, dynamic> requestBody = {
        "contents": [
          {
            "parts": [
              {
                "text": "SYSTEM: You are an expert pharmacist specialized in reading messy handwriting, "
                    "fully fluent in English, Urdu (اردو script), and Roman Urdu. Pakistani "
                    "prescriptions are frequently bilingual: English medicine/brand names with "
                    "Urdu dosage instructions, either in Urdu script or Roman Urdu. "
                    "INPUT: You are provided with an image of a prescription and a literal transcription of it: \"$rawTranscription\". "
                    "TASK: Extract the COMPLETE prescription, not just the medicine list — every "
                    "medicine mentioned in whichever language(s) it was written, AND every other "
                    "piece of information written on the page (patient details, doctor/clinic "
                    "details, date, diagnosis, and any general advice or follow-up instructions). "
                    "Use the transcription and image together to verify everything. "
                    "RULES: "
                    "1. Never invent a value that isn't supported by the image or transcription. "
                    "2. Leave any field blank/null rather than guessing — a field that genuinely "
                    "isn't written on the prescription should be left empty, not filled with a "
                    "plausible-sounding guess. "
                    "3. For every medicine, set \"confidence\" to \"low\" if the handwriting is "
                    "ambiguous or the name is a best guess. "
                    "4. Recognize frequency shorthand in ALL of these forms and convert to a numeric timesPerDay: "
                    "English/Latin (1+0+1, OD, BD/BID, TDS/TID, QID, \"once a day\", \"twice daily\", \"three times a day\"); "
                    "Urdu script (روزانہ ایک بار = once daily, دن میں دو بار = twice a day, دن میں تین بار = three times a day, "
                    "صبح و شام = morning & evening = 2, صبح، دوپہر، شام = morning/noon/evening = 3); "
                    "Roman Urdu (din mein aik bar, din mein 2 bar / do bar, din mein 3 bar / teen bar, subah shaam). "
                    "5. Write every free-text field (\"instructions\", \"diagnosis\", \"generalAdvice\") in the "
                    "SAME language the prescription used for it (don't force-translate to English) — e.g. keep "
                    "\"کھانے کے بعد\" or \"khanay ke baad\" as written if that's how it appears, since the patient "
                    "will read it back in that language. Common instruction meanings to recognize regardless of "
                    "script: کھانے سے پہلے/khane se pehle = before food, کھانے کے بعد/khane ke baad = after food, "
                    "خالی پیٹ/khali pait = empty stomach, سونے سے پہلے/sone se pehle = before bed. "
                    "6. Also extract each medicine's course duration in days if written in any language, converting to days: "
                    "\"5 days\" = 5, \"x 7/7\" = 7, \"1 week\"/\"a week\" = 7, \"2 weeks\"/\"x 2/52\" = 14, "
                    "\"1 month\"/\"a month\"/\"1 mah\"/\"x 1/12\" = 30, \"2 months\"/\"2 mah\"/\"do mah\" = 60, "
                    "\"5 دن\" = 5, \"5 din\" = 5, \"ایک ہفتہ\" = 7, \"ایک ماہ\"/\"ایک مہینہ\" = 30, \"دو ماہ\" = 60. "
                    "Set \"durationDays\" to that number, or null if no duration is written — never guess a duration that isn't stated. "
                    "7. \"patientName\": the patient's name if written anywhere on the prescription, else null. "
                    "8. \"patientAge\": the patient's age/sex if written (e.g. \"34, F\"), else null. "
                    "9. \"doctorName\": the prescribing doctor's name (often at the top, sometimes with "
                    "qualifications like \"Dr.\" or \"MBBS\"), else null. "
                    "10. \"clinicName\": the hospital/clinic/practice name printed on the letterhead, else null. "
                    "11. \"date\": the date written on the prescription exactly as written, else null. "
                    "12. \"diagnosis\": the condition/diagnosis if the doctor wrote one (e.g. \"Rx: Typhoid\", "
                    "\"Dx:\", or a plain condition name), else null. "
                    "13. \"generalAdvice\": any instructions that apply to the whole prescription rather than one "
                    "medicine — diet/rest advice, warnings, tests ordered, etc. — joined into one string, else null. "
                    "14. \"followUp\": any next-visit / follow-up date or instruction (e.g. \"review after 1 week\"), else null. "
                    "15. \"dose\" must capture the FULL amount to take, not just the drug strength — "
                    "include both the strength (mg/mcg/ml/g/IU) AND the quantity/measure to take, "
                    "in whichever language it was written: tablet/capsule counts (\"2 tablets\", "
                    "\"1 capsule\", \"2 goli\", \"aik tablet\", \"ایک گولی\", \"دو گولیاں\"), liquid "
                    "spoon/drop measures (\"1 teaspoon\", \"chamach\", \"1 chamach\", \"ایک چمچ\", "
                    "\"2 boond\"/\"2 قطرے\" = 2 drops), or volume (\"5ml\", \"10cc\"). If the "
                    "prescription only wrote the strength (e.g. just \"500mg\") with no separate "
                    "count, put the strength alone — never invent a quantity that wasn't written — "
                    "but if BOTH a strength and a count/measure are written (as is common, e.g. "
                    "\"Panadol 500mg — 1 tablet\" or \"Syrup — 2 چمچ\"), include both in \"dose\" "
                    "rather than dropping the strength or the quantity. "
                    "OUTPUT: Return ONLY a valid JSON object with this exact shape: "
                    "{\"transcription\": \"$rawTranscription\", "
                    "\"patientName\": \"...\", \"patientAge\": \"...\", \"doctorName\": \"...\", "
                    "\"clinicName\": \"...\", \"date\": \"...\", \"diagnosis\": \"...\", "
                    "\"generalAdvice\": \"...\", \"followUp\": \"...\", "
                    "\"medications\": "
                    "[{\"name\": \"...\", \"dose\": \"...\", \"timesPerDay\": 2, \"durationDays\": 5, \"instructions\": \"...\", \"confidence\": \"high|low\"}]}"
              },
              {
                "inlineData": {
                  "mimeType": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }
        ],
        "generationConfig": {
          "responseMimeType": "application/json",
          "temperature": 0.2,
          "topP": 0.9,
          "topK": 32,
          // A prescription with several medicines PLUS the new
          // patient/doctor/diagnosis/advice fields is noticeably longer
          // JSON than the medicines-only shape this used to return.
          // Without an explicit ceiling here Gemini's default could cut
          // a longer response off mid-object, silently dropping whatever
          // fields (and medicines) came after the cut — this gives it
          // comfortable headroom instead.
          "maxOutputTokens": 4096,
        }
      };

      final response = await http.post(
        Uri.parse('$_baseUrl?key=${ApiKeys.geminiApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Structuring Pass Error ${response.statusCode}');
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final String? text = data['candidates']?[0]['content']?['parts']?[0]['text'];

      if (text == null || text.isEmpty) {
        throw Exception('AI returned an empty response.');
      }

      return text.trim();
    } catch (e) {
      debugPrint('[GeminiService] ReadPrescription Error: $e');
      rethrow;
    }
  }

  /// Reads an actual document (PDF or plain text) and answers a question
  /// about it — sent to Gemini as inline base64 data, the same way
  /// [describeImage] sends photos. Gemini's multimodal API reads PDFs
  /// (text + layout) natively, so no separate PDF-parsing package is
  /// needed. Throws [UnsupportedDocumentException] for formats this can't
  /// read yet (e.g. .docx) so the caller can give an honest message
  /// instead of pretending it looked at the file.
  static Future<String> describeDocument(String filePath, {String prompt = 'Summarize this document.'}) async {
    final lower = filePath.toLowerCase();
    late final String mimeType;
    if (lower.endsWith('.pdf')) {
      mimeType = 'application/pdf';
    } else if (lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.csv')) {
      mimeType = 'text/plain';
    } else {
      throw UnsupportedDocumentException(
          "I can currently read PDF or plain-text files. This one looks "
              "like a different format — try exporting/saving it as a PDF, or "
              "send a clear photo of the page instead.");
    }

    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      // Gemini's inline (non-File-API) payload has a practical size
      // ceiling — fail with an honest message rather than a cryptic 400.
      if (bytes.length > 15 * 1024 * 1024) {
        throw UnsupportedDocumentException(
            "That file is too large for me to read directly (over 15MB). "
                "Try a smaller export, or send a photo of the specific page "
                "you need help with.");
      }
      final base64Doc = base64Encode(bytes);

      final requestBody = {
        'contents': [
          {
            'parts': [
              {
                'text': 'SYSTEM: You are a careful document assistant. Read the attached '
                    'document and answer the request grounded only in what it actually '
                    'contains — never invent figures, names, or clauses that aren\'t there. '
                    'If the document is a scanned image with no readable text, or the '
                    'requested information genuinely isn\'t in it, say so plainly instead '
                    'of guessing.\n\nUSER REQUEST: $prompt'
              },
              {
                'inlineData': {'mimeType': mimeType, 'data': base64Doc}
              }
            ]
          }
        ],
        'generationConfig': {'temperature': 0.2, 'topP': 0.9, 'topK': 32},
      };

      final response = await http.post(
        Uri.parse('$_baseUrl?key=${ApiKeys.geminiApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception('Document Analysis Error ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]['content']?['parts']?[0]['text'];
      if (text == null || (text as String).trim().isEmpty) {
        throw Exception('AI returned an empty document analysis response.');
      }
      return text.trim();
    } on UnsupportedDocumentException {
      rethrow;
    } catch (e) {
      debugPrint('[GeminiService] DescribeDocument Error: $e');
      rethrow;
    }
  }
}

/// Thrown when a file's format genuinely can't be read yet (as opposed to
/// a transient network/API failure) — lets the caller show an honest,
/// specific message instead of a generic "something went wrong".
class UnsupportedDocumentException implements Exception {
  UnsupportedDocumentException(this.message);
  final String message;
  @override
  String toString() => message;
}