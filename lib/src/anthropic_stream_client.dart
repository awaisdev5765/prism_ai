import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'ai_events.dart';
import 'chat_message.dart';
import 'sse_parser.dart';

/// Streams chat completions from the Anthropic Messages API
/// (`https://api.anthropic.com/v1/messages`).
///
/// Wire format: SSE frames with typed `event:` fields (`message_start`,
/// `content_block_start`, `content_block_delta`, `content_block_stop`,
/// `message_delta`, `message_stop`). Text arrives via `text_delta` deltas;
/// tool calls arrive as `tool_use` blocks with `input_json_delta` partials.
final class AnthropicStreamClient implements AiStreamClient {
  AnthropicStreamClient({
    required this.apiKey,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.version = '2023-06-01',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Anthropic API key (starts with `sk-ant-`).
  final String apiKey;

  /// API base URL — override for proxies or gateways.
  final String baseUrl;

  /// Anthropic API version header.
  final String version;

  final http.Client _client;

  @override
  Stream<Object> streamChat(
    List<AiChatMessage> messages, {
    required String model,
    double? temperature,
    int? maxTokens,
    Map<String, Object?> extraBody = const {},
  }) async* {
    // Anthropic takes the system prompt as a top-level parameter, not a
    // message in the array.
    final systemPrompt = messages
        .where((m) => m.role == AiRole.system)
        .map((m) => m.content)
        .join('\n');
    final chat = messages.where((m) => m.role != AiRole.system).toList();

    final uri = Uri.parse('$baseUrl/messages');
    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens ?? 4096, // required by Anthropic
      'messages': [for (final m in chat) m.toJson()],
      'stream': true,
      if (systemPrompt.isNotEmpty) 'system': systemPrompt,
      ?temperature: temperature,
      ...extraBody,
    });

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..headers['x-api-key'] = apiKey
      ..headers['anthropic-version'] = version
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
    final state = _AnthropicStreamState();

    await for (final chunk
        in response.stream.transform(const Utf8Decoder(allowMalformed: true))) {
      for (final sseEvent in parser.addChunk(chunk)) {
        for (final event in state.consume(sseEvent)) {
          if (event is _DoneSignal) {
            yield AiDone(
              finishReason: event.finishReason ?? 'end_turn',
              usage: AiUsage(
                inputTokens: state.inputTokens,
                outputTokens: state.outputTokens,
              ),
            );
            return;
          }
          yield event;
        }
      }
    }

    yield AiDone(
      finishReason: 'end_turn',
      usage: AiUsage(
        inputTokens: state.inputTokens,
        outputTokens: state.outputTokens,
      ),
    );
  }
}

final class _AnthropicStreamState {
  int inputTokens = 0;
  int outputTokens = 0;
  String? _finishReason;

  String? _openToolId;
  String? _openToolName;
  final StringBuffer _toolArgs = StringBuffer();

  List<Object> consume(SseEvent sse) {
    if (sse.data.trim().isEmpty) return const [];

    final Map<String, Object?> json;
    try {
      json = jsonDecode(sse.data) as Map<String, Object?>;
    } on FormatException {
      return const [];
    }

    final type = json['type'] as String?;
    switch (type) {
      case 'message_start':
        final message = json['message'] as Map<String, Object?>? ?? {};
        final usage = message['usage'] as Map<String, Object?>? ?? {};
        inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? inputTokens;
        return const [];

      case 'content_block_start':
        final block = json['content_block'] as Map<String, Object?>? ?? {};
        if (block['type'] == 'tool_use') {
          _openToolId = block['id'] as String?;
          _openToolName = block['name'] as String?;
          _toolArgs.clear();
        }
        return const [];

      case 'content_block_delta':
        final delta = json['delta'] as Map<String, Object?>? ?? {};
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'] as String?;
            if (text != null && text.isNotEmpty) return [AiTextDelta(text)];
            return const [];
          case 'input_json_delta':
            _toolArgs.write((delta['partial_json'] as String?) ?? '');
            return const [];
        }
        return const [];

      case 'content_block_stop':
        if (_openToolId != null) {
          final call = AiToolCall(
            id: _openToolId!,
            name: _openToolName ?? '',
            argumentsJson: _toolArgs.toString(),
          );
          _openToolId = null;
          _openToolName = null;
          _toolArgs.clear();
          return [call];
        }
        return const [];

      case 'message_delta':
        final delta = json['delta'] as Map<String, Object?>? ?? {};
        _finishReason = delta['stop_reason'] as String? ?? _finishReason;
        final usage = json['usage'] as Map<String, Object?>? ?? {};
        outputTokens =
            (usage['output_tokens'] as num?)?.toInt() ?? outputTokens;
        return const [];

      case 'message_stop':
        return [_DoneSignal(finishReason: _finishReason)];

      case 'error':
        final error = json['error'] as Map<String, Object?>? ?? {};
        return [
          AiError((error['message'] as String?) ?? 'Unknown provider error'),
        ];
    }
    return const [];
  }
}

final class _DoneSignal {
  const _DoneSignal({this.finishReason});
  final String? finishReason;
}
