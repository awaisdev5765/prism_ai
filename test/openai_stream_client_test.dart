import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ai/prism_ai.dart';

/// Local HTTP server that streams an SSE frame per line, each terminated
/// with a blank line (the real wire format), with realistic delays.
Future<HttpServer> startStreamingServer(List<String> sseLines,
    {int statusCode = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType =
        ContentType.parse('text/event-stream');
    request.response.statusCode = statusCode;
    for (final line in sseLines) {
      request.response.write('$line\n\n');
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    await request.response.close();
  });
  return server;
}


// flutter_test installs a fake HttpClient that answers 400 to everything;
// clear it so the local SSE server can be reached.
void _disableFakeHttpOverrides() {
  HttpOverrides.global = null;
}

void main() {
  final messages = [AiChatMessage.user('Hello!')];

  testWidgets('streams text deltas and terminates with AiDone',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startStreamingServer([
        'data: {"choices":[{"delta":{"content":"Hel"}}]}',
        'data: {"choices":[{"delta":{"content":"lo AI"}}]}',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
        'data: [DONE]',
        '',
      ]);
      addTearDown(server.close);

      final client = OpenAiStreamClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'test-key',
      );

      final deltas = <String>[];
      Object? lastEvent;
      await for (final event
          in client.streamChat(messages, model: 'gpt-4o')) {
        if (event is AiTextDelta) deltas.add(event.text);
        lastEvent = event;
      }

      expect(deltas.join(), 'Hello AI');
      expect(lastEvent, isA<AiDone>());
    });
  });

  testWidgets('reports usage when the provider includes it', (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startStreamingServer([
        'data: {"choices":[{"delta":{"content":"Hi"}}]}',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":34}}',
        'data: [DONE]',
      ]);
      addTearDown(server.close);

      final client = OpenAiStreamClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      AiDone? done;
      await for (final event in client.streamChat(messages, model: 'm')) {
        if (event is AiDone) done = event;
      }

      expect(done, isNotNull);
      expect(done!.usage, isNotNull);
      expect(done.usage!.inputTokens, 12);
      expect(done.usage!.outputTokens, 34);
    });
  });

  testWidgets('surfaces provider errors as AiError events', (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startStreamingServer(
        ['data: {"error":{"message":"Invalid API key"}}'],
        statusCode: 401,
      );
      addTearDown(server.close);

      final client = OpenAiStreamClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'wrong',
      );

      AiError? error;
      await for (final event in client.streamChat(messages, model: 'm')) {
        if (event is AiError) error = event;
      }

      expect(error, isNotNull);
      expect(error!.statusCode, 401);
      expect(error.message, contains('Invalid API key'));
    });
  });

  testWidgets('emits tool call events when the model calls a tool',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startStreamingServer([
        'data: {"choices":[{"delta":{"tool_calls":[{"id":"call_1","function":{"name":"get_weather","arguments":"{\\"city\\": \\"Lahore\\"}"}}]}}]}',
        'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
        'data: [DONE]',
      ]);
      addTearDown(server.close);

      final client = OpenAiStreamClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      AiToolCall? toolCall;
      await for (final event in client.streamChat(messages, model: 'm')) {
        if (event is AiToolCall) toolCall = event;
      }

      expect(toolCall, isNotNull);
      expect(toolCall!.name, 'get_weather');
      expect(toolCall.argumentsJson, '{"city": "Lahore"}');
    });
  });

  testWidgets('request carries model, messages and auth header',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      HttpRequest? captured;
      Future<String>? bodyFuture;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        captured = request;
        bodyFuture = utf8.decoder.bind(request).join();
        request.response.headers.contentType =
            ContentType.parse('text/event-stream');
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      addTearDown(server.close);

      final client = OpenAiStreamClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'sk-secret',
      );
      await for (final _ in client.streamChat(messages, model: 'gpt-4o')) {}

      expect(captured, isNotNull);
      expect(captured!.headers.value('authorization'), 'Bearer sk-secret');
      final body = await bodyFuture!;
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['model'], 'gpt-4o');
      expect(json['stream'], true);
      expect((json['messages'] as List).length, 1);
    });
  });
}
