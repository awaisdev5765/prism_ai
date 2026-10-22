import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_events.dart';
import 'chat_message.dart';
import 'sse_parser.dart';

/// Streams chat completions from any OpenAI-compatible endpoint.
///
/// One implementation covers OpenAI, Azure OpenAI, Ollama (`/v1`),
/// Groq, DeepSeek, Together, LM Studio, vLLM and every other server that
/// speaks the `/chat/completions` protocol.
///
/// ```dart
/// final client = OpenAiStreamClient(
///   baseUrl: 'https://api.openai.com/v1',
///   apiKey: 'sk-...',
/// );
/// await for (final event in client.streamChat(messages, model: 'gpt-4o')) {
///   if (event is AiTextDelta) stdout.write(event.text);
/// }
/// ```
final class OpenAiStreamClient {
  OpenAiStreamClient({
    required this.baseUrl,
    this.apiKey,
    http.Client? client,
    Map<String, String>? extraHeaders,
  })  : _client = client ?? http.Client(),
        _extraHeaders = extraHeaders ?? const {};

  /// Base URL of the OpenAI-compatible API, e.g.
  /// `https://api.openai.com/v1` or `http://localhost:11434/v1` (Ollama).
  final String baseUrl;

  /// Bearer token, when the endpoint requires one (Ollama doesn't).
  final String? apiKey;

  final http.Client _client;
  final Map<String, String> _extraHeaders;

  /// Streams a chat completion as a sequence of typed events.
  ///
  /// Emits [AiTextDelta] for each content chunk, [AiToolCall] when the model
  /// invokes tools, and terminates with [AiDone]. Errors surface as
  /// [AiError] (the stream does not throw — UI code can just switch on
  /// event types).
  Stream<Object> streamChat(
    List<AiChatMessage> messages, {
    required String model,
    double? temperature,
    int? maxTokens,
    Map<String, Object?> extraBody = const {},
  }) async* {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': [for (final m in messages) m.toJson()],
      'stream': true,
      ?temperature: temperature,
      ?maxTokens: maxTokens,
      ...extraBody,
    });

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream';
    if (apiKey != null && apiKey!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }
    _extraHeaders.forEach((name, value) {
      request.headers[name] = value;
    });
    request.body = body;

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
    final usageCollector = _UsageCollector();

    await for (final chunk
        in response.stream.transform(const Utf8Decoder(allowMalformed: true))) {
      for (final event in parser.addChunk(chunk)) {
        for (final parsed in _parseEvent(event, usageCollector)) {
          if (parsed is _DoneSignal) {
            yield AiDone(
              finishReason: parsed.finishReason ?? 'stop',
              usage: usageCollector.snapshot(),
            );
            return;
          }
          yield parsed;
        }
      }
    }

    // Stream ended without [DONE] — still terminate cleanly.
    yield AiDone(finishReason: 'stop', usage: usageCollector.snapshot());
  }

  /// Normalizes one SSE frame into zero or more provider-agnostic events.
  static List<Object> _parseEvent(
    SseEvent event,
    _UsageCollector usageCollector,
  ) {
    if (event.isDoneSentinel) return [const _DoneSignal()];
    if (event.data.trim().isEmpty) return const [];

    final Map<String, Object?> json;
    try {
      json = jsonDecode(event.data) as Map<String, Object?>;
    } on FormatException {
      return const []; // keep-alive or non-JSON frame — skip
    }

    // Error payload (OpenAI shape: {"error": {"message": ...}}).
    final error = json['error'];
    if (error is Map<String, Object?>) {
      return [
        AiError(
          (error['message'] as String?) ?? 'Unknown provider error',
          statusCode: (error['code'] is int) ? error['code'] as int : null,
        ),
      ];
    }

    final events = <Object>[];
    final choices = json['choices'] as List<Object?>? ?? const [];
    for (final choice in choices) {
      if (choice is! Map<String, Object?>) continue;

      final delta = choice['delta'] as Map<String, Object?>? ??
          choice['message'] as Map<String, Object?>?;
      if (delta != null) {
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          events.add(AiTextDelta(content));
        }
        final toolCalls = delta['tool_calls'] as List<Object?>?;
        if (toolCalls != null) {
          for (final call in toolCalls) {
            if (call is! Map<String, Object?>) continue;
            final function = call['function'] as Map<String, Object?>? ?? {};
            events.add(AiToolCall(
              id: (call['id'] as String?) ?? '',
              name: (function['name'] as String?) ?? '',
              argumentsJson: (function['arguments'] as String?) ?? '',
            ));
          }
        }
      }

      final finishReason = choice['finish_reason'];
      if (finishReason is String && finishReason.isNotEmpty) {
        events.add(_DoneSignal(finishReason: finishReason));
      }
    }

    final usageJson = json['usage'] as Map<String, Object?>?;
    if (usageJson != null) {
      usageCollector.absorb(_usageFromJson(usageJson));
    }
    return events;
  }

  static AiUsage _usageFromJson(Map<String, Object?> json) => AiUsage(
        inputTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['completion_tokens'] as num?)?.toInt() ??
            (json['output_tokens'] as num?)?.toInt() ??
            0,
      );
}

final class _UsageCollector {
  AiUsage? _usage;
  void absorb(AiUsage usage) => _usage = usage;
  AiUsage? snapshot() => _usage;
}

final class _DoneSignal {
  const _DoneSignal({this.finishReason});
  final String? finishReason;
}
