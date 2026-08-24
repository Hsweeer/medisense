import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_keys.dart';

/// One tool call Groq wants us to execute.
class GroqToolCall {
  GroqToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class GroqChatResult {
  GroqChatResult({this.content, this.toolCalls});
  final String? content;
  final List<GroqToolCall>? toolCalls;

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

class GroqService {
  GroqService._();

  static const _chatEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _transcribeEndpoint = 'https://api.groq.com/openai/v1/audio/transcriptions';

  // Current active free-tier model (llama-3.1-8b-instant was decommissioned June 2026)
  static const _model = 'openai/gpt-oss-20b';
  static const _whisperModel = 'whisper-large-v3-turbo';

  static void _requireApiKey() {
    if (ApiKeys.groqApiKey.isEmpty) throw Exception('No API key');
  }

  /// Free-text chat that automatically handles tool calling.
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
      'temperature': 0.3,
      if (tools != null && tools.isNotEmpty) ...{
        'tools': tools,
        'tool_choice': 'auto',
      },
    };

    final res = await http.post(
      Uri.parse(_chatEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${ApiKeys.groqApiKey}',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      debugPrint('[GroqService] API Error: ${res.statusCode} - ${res.body}');
      throw Exception('Groq Error ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    final message = data['choices'][0]['message'];
    final String? content = message['content'];

    List<GroqToolCall>? toolCalls;
    if (message['tool_calls'] != null) {
      toolCalls = (message['tool_calls'] as List).map((tc) {
        final fn = tc['function'];
        return GroqToolCall(
          id: tc['id'],
          name: fn['name'],
          arguments: jsonDecode(fn['arguments']),
        );
      }).toList();
    }

    return GroqChatResult(content: content, toolCalls: toolCalls);
  }

  static Future<String> chat({
    required String systemPrompt,
    required List<Map<String, String>> history,
  }) async {
    final res = await chatWithTools(systemPrompt: systemPrompt, history: history, tools: null);
    return res.content ?? '';
  }

  static Future<String> transcribeAudio(String path) async {
    _requireApiKey();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_transcribeEndpoint))
        ..headers['Authorization'] = 'Bearer ${ApiKeys.groqApiKey}'
        ..fields['model'] = _whisperModel
        ..files.add(await http.MultipartFile.fromPath('file', path, contentType: MediaType('audio', 'mp4')));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data['text'] ?? "";
    } catch (_) { return ""; }
  }
}