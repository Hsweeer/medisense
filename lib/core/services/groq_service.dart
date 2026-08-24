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

/// One event from [GroqService.chatWithToolsStream]: either a growing text
/// delta (call this repeatedly to update the UI live) or the final,
/// fully-assembled result once the stream ends.
class GroqStreamEvent {
  GroqStreamEvent._({this.textSoFar, this.result});

  factory GroqStreamEvent.delta(String textSoFar) => GroqStreamEvent._(textSoFar: textSoFar);
  factory GroqStreamEvent.done(GroqChatResult result) => GroqStreamEvent._(result: result);

  /// Non-null on every delta event — the full text accumulated so far.
  final String? textSoFar;

  /// Non-null only on the final event.
  final GroqChatResult? result;

  bool get isDone => result != null;
}

/// Accumulates one tool call's streamed fragments (name + arguments arrive
/// in pieces across multiple SSE chunks) until the stream ends.
class _ToolCallBuilder {
  String? id;
  String? name;
  final argsBuffer = StringBuffer();
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

  /// Same as [chatWithTools] but streams the reply token-by-token (SSE),
  /// yielding a growing chunk of text as it arrives so the UI can show a
  /// live typing effect instead of one long wait. The final event carries
  /// the fully-assembled [GroqChatResult] (including any tool calls, which
  /// stream in as fragmented deltas and are reassembled here) exactly like
  /// [chatWithTools] would have returned.
  static Stream<GroqStreamEvent> chatWithToolsStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required List<Map<String, dynamic>>? tools,
  }) async* {
    _requireApiKey();

    final body = {
      'model': _model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ...history,
      ],
      'temperature': 0.3,
      'stream': true,
      if (tools != null && tools.isNotEmpty) ...{
        'tools': tools,
        'tool_choice': 'auto',
      },
    };

    final request = http.Request('POST', Uri.parse(_chatEndpoint))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${ApiKeys.groqApiKey}',
      })
      ..body = jsonEncode(body);

    final streamed = await request.send().timeout(const Duration(seconds: 30));

    if (streamed.statusCode != 200) {
      final errBody = await streamed.stream.bytesToString();
      debugPrint('[GroqService] Stream API Error: ${streamed.statusCode} - $errBody');
      throw Exception('Groq Error ${streamed.statusCode}');
    }

    final contentBuffer = StringBuffer();
    final toolBuilders = <int, _ToolCallBuilder>{};

    final lines = streamed.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') break;

      Map<String, dynamic> json;
      try {
        json = jsonDecode(payload);
      } catch (_) {
        continue; // partial/malformed chunk — skip rather than crash the stream
      }

      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final delta = choices[0]['delta'] as Map<String, dynamic>?;
      if (delta == null) continue;

      final contentDelta = delta['content'] as String?;
      if (contentDelta != null && contentDelta.isNotEmpty) {
        contentBuffer.write(contentDelta);
        yield GroqStreamEvent.delta(contentBuffer.toString());
      }

      final toolCallDeltas = delta['tool_calls'] as List?;
      if (toolCallDeltas != null) {
        for (final tcd in toolCallDeltas) {
          final idx = tcd['index'] as int? ?? 0;
          final builder = toolBuilders.putIfAbsent(idx, () => _ToolCallBuilder());
          if (tcd['id'] != null) builder.id = tcd['id'];
          final fn = tcd['function'] as Map<String, dynamic>?;
          if (fn != null) {
            if (fn['name'] != null) builder.name = '${builder.name ?? ''}${fn['name']}';
            if (fn['arguments'] != null) builder.argsBuffer.write(fn['arguments']);
          }
        }
      }
    }

    List<GroqToolCall>? finalToolCalls;
    if (toolBuilders.isNotEmpty) {
      finalToolCalls = toolBuilders.values.map((b) {
        Map<String, dynamic> args = {};
        try {
          args = jsonDecode(b.argsBuffer.toString());
        } catch (_) {
          // Truncated/invalid arguments JSON — treat as no arguments rather
          // than throwing away the whole streamed response.
        }
        return GroqToolCall(id: b.id ?? '', name: b.name ?? '', arguments: args);
      }).toList();
    }

    yield GroqStreamEvent.done(GroqChatResult(
      content: contentBuffer.isEmpty ? null : contentBuffer.toString(),
      toolCalls: finalToolCalls,
    ));
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