import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place for third-party API keys.
/// Keys are now securely loaded from the .env file.
class ApiKeys {
  ApiKeys._();

  static const googlePlacesApiKey = '';

  /// Groq API key — powers MedAI's free-text replies.
  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  
  /// Gemini API Key — powers the prescription scanner.
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
}
