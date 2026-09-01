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
                    "TASK: Extract EVERY medicine mentioned, in whichever language(s) it was written. Use the transcription and image together to verify names. "
                    "RULES: "
                    "1. Never invent a value that isn't supported by the image or transcription. "
                    "2. Leave dose, frequency, or instructions blank rather than guessing. "
                    "3. For every item, set \"confidence\" to \"low\" if the handwriting is ambiguous or the name is a best guess. "
                    "4. Recognize frequency shorthand in ALL of these forms and convert to a numeric timesPerDay: "
                    "English/Latin (1+0+1, OD, BD/BID, TDS/TID, QID, \"once a day\", \"twice daily\", \"three times a day\"); "
                    "Urdu script (روزانہ ایک بار = once daily, دن میں دو بار = twice a day, دن میں تین بار = three times a day, "
                    "صبح و شام = morning & evening = 2, صبح، دوپہر، شام = morning/noon/evening = 3); "
                    "Roman Urdu (din mein aik bar, din mein 2 bar / do bar, din mein 3 bar / teen bar, subah shaam). "
                    "5. Write the \"instructions\" field in the SAME language the prescription used for that "
                    "instruction (don't force-translate to English) — e.g. keep \"کھانے کے بعد\" or \"khanay ke baad\" "
                    "as written if that's how it appears, since the patient will read it back in that language. "
                    "Common instruction meanings to recognize regardless of script: کھانے سے پہلے/khane se pehle = before food, "
                    "کھانے کے بعد/khane ke baad = after food, خالی پیٹ/khali pait = empty stomach, سونے سے پہلے/sone se pehle = before bed. "
                    "6. Also extract the course duration in days if written in any language (e.g. \"5 days\", \"x 7/7\", "
                    "\"1 week\" = 7, \"5 دن\", \"5 din\", \"ایک ہفتہ\" = 7). "
                    "Set \"durationDays\" to that number, or null if no duration is written — never guess a duration that isn't stated. "
                    "OUTPUT: Return ONLY a valid JSON object: "
                    "{\"transcription\": \"$rawTranscription\", \"medications\": "
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