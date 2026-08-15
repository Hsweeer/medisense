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
                "text": "SYSTEM: You are a literal transcriber. "
                    "TASK: Transcribe exactly what is written on this prescription image. "
                    "Do NOT interpret medicine names, do NOT guess, and do NOT structure it. "
                    "If a word is genuinely illegible, mark it as [illegible]. "
                    "OUTPUT: Provide a plain text transcription of every word seen."
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
                "text": "SYSTEM: You are an expert pharmacist specialized in reading messy handwriting. "
                    "INPUT: You are provided with an image of a prescription and a literal transcription of it: \"$rawTranscription\". "
                    "TASK: Extract EVERY medicine mentioned. Use the transcription and image together to verify names. "
                    "RULES: "
                    "1. Never invent a value that isn't supported by the image or transcription. "
                    "2. Leave dose, frequency, or instructions blank rather than guessing. "
                    "3. For every item, set \"confidence\" to \"low\" if the handwriting is ambiguous or the name is a best guess. "
                    "4. Common shorthand: 1+0+1, OD, BD, TDS, QID. "
                    "OUTPUT: Return ONLY a valid JSON object: "
                    "{\"transcription\": \"$rawTranscription\", \"medications\": "
                    "[{\"name\": \"...\", \"dose\": \"...\", \"timesPerDay\": 2, \"instructions\": \"...\", \"confidence\": \"high|low\"}]}"
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
          "responseMimeType": "application/json"
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
}
