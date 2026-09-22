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

  /// CARTO basemap API key — since August 2026 CARTO requires a (free) key
  /// on requests to basemaps.cartocdn.com or it stamps every map tile with
  /// an "API KEY REQUIRED" watermark. Get a free one at
  /// carto.com/basemaps/apikey (no CARTO account needed) and put it in
  /// .env as CARTO_API_KEY — the map still loads without it, just
  /// watermarked, so this degrades gracefully if left unset.
  static String get cartoApiKey => dotenv.env['CARTO_API_KEY'] ?? '';

  /// The Voyager basemap tile URL used by the SOS and Nearby-facilities
  /// maps, with the key appended when one is configured. Centralized here
  /// so both screens stay in sync and there's one place to update if
  /// CARTO's basemap endpoint or key parameter ever changes again.
  static String get cartoVoyagerTileUrlTemplate {
    const base = 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
    return cartoApiKey.isEmpty ? base : '$base?key=$cartoApiKey';
  }
}