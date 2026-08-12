import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_keys.dart';

/// One tool call Groq wants us to execute, with its arguments already
/// decoded from JSON.
class GroqToolCall {
  GroqToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// Result of a chat call: either plain text, or one or more tool calls to
/// execute (Groq returns tool calls instead of content when it decides an
/// action is needed).
class GroqChatResult {
  GroqChatResult({this.content, this.toolCalls});
  final String? content;
  final List<GroqToolCall>? toolCalls;

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

/// Thin wrapper around Groq's OpenAI-compatible chat completions and audio
/// transcription endpoints. Powers MedAI's free-text replies, real
/// voice-note transcription, and real actions (reminders, profile edits)
/// in [ChatProvider].
class GroqService {
  GroqService._();

  static const _chatEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _transcribeEndpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  // llama-3.3-70b-versatile was deprecated by Groq on June 17, 2026 —
  // requests to it now fail, which is what was showing up as "trouble
  // reaching MedAI's servers" on every reply. openai/gpt-oss-120b is
  // Groq's official recommended replacement and supports tool calling.
  static const _model = 'openai/gpt-oss-120b';
  static const _whisperModel = 'whisper-large-v3-turbo';

  static void _requireApiKey() {
    if (ApiKeys.groqApiKey.isEmpty ||
        ApiKeys.groqApiKey == 'PASTE_YOUR_GROQ_API_KEY_HERE') {
      throw Exception(
          'No Groq API key set — paste one in lib/core/config/api_keys.dart');
    }
  }

  /// [systemPrompt] sets MedAI's persona/instructions (with health-profile
  /// context folded in when personalization is on).
  /// [history] is the running conversation as {role, content} maps, oldest
  /// first, so MedAI has context beyond just the latest message.
  static Future<String> chat({
    required String systemPrompt,
    required List<Map<String, String>> history,
  }) async {
    final result = await chatWithTools(
      systemPrompt: systemPrompt,
      history: history,
      tools: null,
    );
    final content = result.content;
    if (content == null || content.trim().isEmpty) {
      throw Exception('Groq returned an empty response');
    }
    return content.trim();
  }

  /// Same as [chat], but lets Groq call one of [tools] (OpenAI-style
  /// function-calling schema) instead of just replying with text — this is
  /// what lets MedAI actually create a reminder or edit the health profile
  /// from a plain-language request, not just talk about doing it.
  static Future<GroqChatResult> chatWithTools({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required List<Map<String, dynamic>>? tools,
  }) async {
    _requireApiKey();

    final body = {
      'model': _model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ...history,
      ],
      'temperature': 0.4,
      'max_tokens': 700,
      if (tools != null && tools.isNotEmpty) ...{
        'tools': tools,
        'tool_choice': 'auto',
      },
    };

    final res = await http
        .post(
          Uri.parse(_chatEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${ApiKeys.groqApiKey}',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('Groq error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final message = (data['choices'] as List?)?.first['message']
        as Map<String, dynamic>?;
    if (message == null) {
      throw Exception('Groq returned no message');
    }

    final rawToolCalls = message['tool_calls'] as List?;
    List<GroqToolCall>? toolCalls;
    if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
      toolCalls = rawToolCalls.map((raw) {
        final fn = raw['function'] as Map<String, dynamic>;
        Map<String, dynamic> args;
        try {
          args = jsonDecode(fn['arguments'] as String) as Map<String, dynamic>;
        } catch (_) {
          args = {};
        }
        return GroqToolCall(
          id: raw['id'] as String? ?? '',
          name: fn['name'] as String? ?? '',
          arguments: args,
        );
      }).toList();
    }

    return GroqChatResult(
      content: message['content'] as String?,
      toolCalls: toolCalls,
    );
  }

  /// Transcribes a recorded voice note to real text using Groq's hosted
  /// Whisper endpoint. This is genuine speech-to-text — not a scripted
  /// guess — but note it requires internet (unlike the on-device OCR).
  static Future<String> transcribeAudio(String audioFilePath) async {
    _requireApiKey();

    final file = File(audioFilePath);
    if (!await file.exists()) {
      throw Exception('Voice note file not found at $audioFilePath');
    }
    final size = await file.length();
    if (size < 1000) {
      throw Exception('Recording is too short/empty ($size bytes)');
    }

    final request = http.MultipartRequest('POST', Uri.parse(_transcribeEndpoint))
      ..headers['Authorization'] = 'Bearer ${ApiKeys.groqApiKey}'
      ..fields['model'] = _whisperModel
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        audioFilePath,
        // Set explicitly rather than relying on extension auto-detection —
        // a misidentified content type is a common cause of a transcription
        // API silently rejecting or mis-parsing an otherwise-valid file.
        contentType: MediaType('audio', 'mp4'),
      ));

    debugPrint('[GroqService] transcribeAudio: uploading $audioFilePath ($size bytes)');
    final streamed = await request.send().timeout(const Duration(seconds: 40));
    final res = await http.Response.fromStream(streamed);
    debugPrint('[GroqService] transcribeAudio: HTTP ${res.statusCode}');

    if (res.statusCode != 200) {
      throw Exception('Groq transcription error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      throw Exception('Groq returned an empty transcription');
    }
    return text.trim();
  }
}