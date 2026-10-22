import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'ai_events.dart';
import 'chat_message.dart';
import 'sse_parser.dart';

/// Streams chat completions from the Google Gemini API
/// (`streamGenerateContent?alt=sse`).
///
/// Wire format: SSE frames whose data is a `GenerateContentResponse` JSON.
/// Text arrives in `candidates[0].content.parts[].text`; the final frame
/// carries `usageMetadata`. There is no `[DONE]` sentinel — the stream
/// ending is the completion signal.
final class GeminiStreamClient implements AiStreamClient {
  GeminiStreamClient({
    required this.apiKey,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Google AI Studio API key.
  final String apiKey;

  /// API base URL — override for proxies or gateways.
  final String baseUrl;

  final http.Client _client;

  @override
  Stream<Object> streamChat(
    List<AiChatMessage> messages, {
    required String model,
    double? temperature,
    int? maxTokens,
    Map<String, Object?> extraBody = const {},
  }) async* {
    // Gemini roles: 'user' and 'model' (assistant). System prompts go in
    // a top-level systemInstruction.
    final systemPrompt = messages
        .where((m) => m.role == AiRole.system)
        .map((m) => m.content)
        .join('\n');
    final contents = <Map<String, Object?>>[];
    for (final m in messages) {
      if (m.role == AiRole.system) continue;
      contents.add({
        'role': m.role == AiRole.assistant ? 'model' : 'user',
        'parts': [
          {'text': m.content},
        ],
      });
    }

    final uri = Uri.parse(
      '$baseUrl/models/$model:streamGenerateContent?alt=sse',
    );
    final body = jsonEncode({
      'contents': contents,
      if (systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
      'generationConfig': {
        ?temperature: temperature,
        'maxOutputTokens': ?maxTokens,
      },
      ...extraBody,
    });

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..headers['x-goog-api-key'] = apiKey
      ..body = body;

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      yield AiError(
        'Request failed with HTTP ${response.statusCode}: $errorBody',
        statusCode: response.statusCode,
      );
      return;
    }

    final parser = SseParser();
    var usage = const AiUsage(inputTokens: 0, outputTokens: 0);
    var finishReason = 'stop';

    await for (final chunk
        in response.stream.transform(const Utf8Decoder(allowMalformed: true))) {
      for (final sse in parser.addChunk(chunk)) {
        if (sse.data.trim().isEmpty) continue;

        final Map<String, Object?> json;
        try {
          json = jsonDecode(sse.data) as Map<String, Object?>;
        } on FormatException {
          continue;
        }

        // Error payload: {"error": {"code": ..., "message": ...}}
        final error = json['error'];
        if (error is Map<String, Object?>) {
          yield AiError(
            (error['message'] as String?) ?? 'Unknown provider error',
            statusCode: (error['code'] as num?)?.toInt(),
          );
          return;
        }

        final candidates = json['candidates'] as List<Object?>? ?? const [];
        for (final candidate in candidates) {
          if (candidate is! Map<String, Object?>) continue;

          final content = candidate['content'] as Map<String, Object?>?;
          final parts = content?['parts'] as List<Object?>? ?? const [];
          for (final part in parts) {
            if (part is! Map<String, Object?>) continue;
            final text = part['text'] as String?;
            if (text != null && text.isNotEmpty) {
              yield AiTextDelta(text);
            }
          }

          final reason = candidate['finishReason'] as String?;
          if (reason != null && reason.isNotEmpty) {
            finishReason = reason;
          }
        }

        final usageMeta = json['usageMetadata'] as Map<String, Object?>?;
        if (usageMeta != null) {
          usage = AiUsage(
            inputTokens: (usageMeta['promptTokenCount'] as num?)?.toInt() ?? 0,
            outputTokens:
                (usageMeta['candidatesTokenCount'] as num?)?.toInt() ?? 0,
          );
        }
      }
    }

    yield AiDone(finishReason: finishReason, usage: usage);
  }
}
