import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ai/prism_ai.dart';

void _disableFakeHttpOverrides() {
  HttpOverrides.global = null;
}

/// SSE server that responds with a tool call on the first request and
/// final text on the second — exercising the full agent loop.
Future<HttpServer> startAgentServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requestCount = 0;
  server.listen((request) async {
    requestCount++;
    request.response.headers.contentType =
        ContentType.parse('text/event-stream');

    if (requestCount == 1) {
      // Model asks to call the weather tool
      request.response.write(
          'data: {"choices":[{"delta":{"tool_calls":[{"id":"call_1","type":"function","function":{"name":"get_weather","arguments":"{\\"city\\": \\"Lahore\\"}"}}]}}]}\n\n');
      request.response.write(
          'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n');
      request.response.write('data: [DONE]\n\n');
    } else {
      // Model responds with final text after seeing the tool result
      request.response.write(
          'data: {"choices":[{"delta":{"content":"The weather in Lahore is sunny and warm."}}]}\n\n');
      request.response.write(
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n');
      request.response.write('data: [DONE]\n\n');
    }
    await request.response.close();
  });
  return server;
}

void main() {
  testWidgets('agent loop: tool call → execute → final response',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startAgentServer();
      addTearDown(server.close);

      var toolExecuted = false;
      Map<String, Object?>? receivedArgs;

      final agent = AiAgent(
        client: OpenAiStreamClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          apiKey: 'test',
        ),
        tools: [
          AiTool(
            name: 'get_weather',
            description: 'Get weather',
            execute: (args) async {
              toolExecuted = true;
              receivedArgs = args;
              return 'Sunny, 25°C';
            },
          ),
        ],
        maxIterations: 3,
      );

      final result = await agent.run(
        [AiChatMessage.user('Weather in Lahore?')],
        model: 'gpt-4o',
      );

      expect(toolExecuted, isTrue, reason: 'tool should have been executed');
      expect(receivedArgs, {'city': 'Lahore'});
      expect(result.text, 'The weather in Lahore is sunny and warm.');
      expect(result.isError, isFalse);
      expect(result.iterations, 1);
      // Full conversation: user → assistant(tool_call) → tool(result) → assistant(text)
      expect(result.messages.length, 4);
    });
  });

  testWidgets('agent returns final text without tools when none needed',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startAgentServer();
      addTearDown(server.close);

      final agent = AiAgent(
        client: OpenAiStreamClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          apiKey: 'test',
        ),
        tools: [],
        maxIterations: 3,
      );

      final result = await agent.run(
        [AiChatMessage.user('Hi')],
        model: 'gpt-4o',
      );

      // Single iteration, no tool calls
      expect(result.iterations, 1);
      expect(result.isError, isFalse);
      expect(result.text, isNotEmpty);
    });
  });

  test('cosineSimilarity: identical vectors → 1.0', () {
    final s = cosineSimilarity([1.0, 0.0], [1.0, 0.0]);
    expect(s, closeTo(1.0, 0.001));
  });

  test('cosineSimilarity: orthogonal vectors → 0.0', () {
    final s = cosineSimilarity([1.0, 0.0], [0.0, 1.0]);
    expect(s, closeTo(0.0, 0.001));
  });
}
