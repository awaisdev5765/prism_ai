import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ai/prism_ai.dart';

/// Local Anthropic Messages API server streaming the real wire format.
Future<HttpServer> startAnthropicServer({int statusCode = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType =
        ContentType.parse('text/event-stream');
    request.response.statusCode = statusCode;

    void frame(String event, String data) {
      request.response.write('event: $event\ndata: $data\n\n');
    }

    if (statusCode != 200) {
      request.response.write(
          'event: error\ndata: {"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}\n\n');
      await request.response.close();
      return;
    }

    frame('message_start',
        '{"type":"message_start","message":{"usage":{"input_tokens":25}}}');
    frame('content_block_start',
        '{"type":"content_block_start","index":0,"content_block":{"type":"text"}}');
    frame('content_block_delta',
        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}');
    frame('content_block_delta',
        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" Claude"}}');
    frame('content_block_stop', '{"type":"content_block_stop","index":0}');
    frame('message_delta',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":14}}');
    frame('message_stop', '{"type":"message_stop"}');
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
  final messages = [AiChatMessage.user('Hi')];

  testWidgets('streams text deltas and terminates with AiDone',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startAnthropicServer();
      addTearDown(server.close);

      final client = AnthropicStreamClient(
        apiKey: 'sk-ant-test',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      final deltas = <String>[];
      AiDone? done;
      await for (final event in client.streamChat(messages, model: 'claude-4')) {
        if (event is AiTextDelta) deltas.add(event.text);
        if (event is AiDone) done = event;
      }

      expect(deltas.join(), 'Hello Claude');
      expect(done!.finishReason, 'end_turn');
      expect(done.usage!.inputTokens, 25);
      expect(done.usage!.outputTokens, 14);
    });
  });

  testWidgets('extracts system prompt into the system parameter and '
      'sends required headers', (tester) async {
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
        request.response.write(
            'event: message_stop\ndata: {"type":"message_stop"}\n\n');
        await request.response.close();
      });
      addTearDown(server.close);

      final client = AnthropicStreamClient(
        apiKey: 'sk-ant-test',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await for (final _ in client.streamChat(
        [AiChatMessage.system('Be brief'), AiChatMessage.user('Hi')],
        model: 'claude-4',
      )) {}

      expect(captured!.headers.value('x-api-key'), 'sk-ant-test');
      expect(captured!.headers.value('anthropic-version'), '2023-06-01');
      final body = jsonDecode(await bodyFuture!) as Map<String, dynamic>;
      expect(body['system'], 'Be brief');
      final msgs = body['messages'] as List;
      expect(msgs.length, 1, reason: 'system message must not be duplicated');
      expect(body['max_tokens'], 4096, reason: 'Anthropic requires max_tokens');
    });
  });

  testWidgets('assembles tool calls from input_json_delta partials',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType =
            ContentType.parse('text/event-stream');
        void frame(String event, String data) {
          request.response.write('event: $event\ndata: $data\n\n');
        }

        frame('message_start',
            '{"type":"message_start","message":{"usage":{"input_tokens":10}}}');
        frame('content_block_start',
            '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_weather"}}');
        frame('content_block_delta',
            '{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"city\\":"}}');
        frame('content_block_delta',
            '{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":" \\"Lahore\\"}"}}');
        frame('content_block_stop', '{"type":"content_block_stop","index":0}');
        frame('message_delta',
            '{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}');
        frame('message_stop', '{"type":"message_stop"}');
        await request.response.close();
      });
      addTearDown(server.close);

      final client = AnthropicStreamClient(
        apiKey: 'sk-ant-test',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      AiToolCall? toolCall;
      AiDone? done;
      await for (final event in client.streamChat(messages, model: 'claude-4')) {
        if (event is AiToolCall) toolCall = event;
        if (event is AiDone) done = event;
      }

      expect(toolCall!.id, 'toolu_1');
      expect(toolCall.name, 'get_weather');
      expect(toolCall.argumentsJson, '{"city": "Lahore"}');
      expect(done!.finishReason, 'tool_use');
    });
  });

  testWidgets('surfaces authentication errors', (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startAnthropicServer(statusCode: 401);
      addTearDown(server.close);

      final client = AnthropicStreamClient(
        apiKey: 'wrong',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      AiError? error;
      await for (final event in client.streamChat(messages, model: 'claude-4')) {
        if (event is AiError) error = event;
      }

      expect(error, isNotNull);
      expect(error!.message, contains('invalid x-api-key'));
    });
  });
}
