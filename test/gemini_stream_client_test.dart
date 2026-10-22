import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ai/prism_ai.dart';

/// Local Gemini streamGenerateContent server streaming the real wire format.
Future<HttpServer> startGeminiServer({int statusCode = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType =
        ContentType.parse('text/event-stream');
    request.response.statusCode = statusCode;

    void frame(String data) {
      request.response.write('data: $data\n\n');
    }

    if (statusCode != 200) {
      frame(
          '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key."}}');
      await request.response.close();
      return;
    }

    frame(
        '{"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"}}]}');
    frame(
        '{"candidates":[{"content":{"parts":[{"text":" Gemini"}],"role":"model"}}],"usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":3}}');
    frame(
        '{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":""}],"role":"model"}}],"usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":3}}');
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

  testWidgets('streams text deltas and terminates with AiDone + usage',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startGeminiServer();
      addTearDown(server.close);

      final client = GeminiStreamClient(
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      final deltas = <String>[];
      AiDone? done;
      await for (final event in client.streamChat(messages, model: 'gemini-2')) {
        if (event is AiTextDelta) deltas.add(event.text);
        if (event is AiDone) done = event;
      }

      expect(deltas.join(), 'Hello Gemini');
      expect(done!.finishReason, 'STOP');
      expect(done.usage!.inputTokens, 7);
      expect(done.usage!.outputTokens, 3);
    });
  });

  testWidgets('maps system messages to systemInstruction and sends the '
      'API key header', (tester) async {
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
            'data: {"candidates":[{"content":{"parts":[{"text":"ok"}],"role":"model"}}]}\n\n');
        await request.response.close();
      });
      addTearDown(server.close);

      final client = GeminiStreamClient(
        apiKey: 'g-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await for (final _ in client.streamChat(
        [AiChatMessage.system('Be nice'), AiChatMessage.user('Hi')],
        model: 'gemini-2',
      )) {}

      expect(captured!.headers.value('x-goog-api-key'), 'g-key');
      expect(
        captured!.uri.path,
        contains('/models/gemini-2:streamGenerateContent'),
      );
      expect(captured!.uri.queryParameters['alt'], 'sse');
      final body = jsonDecode(await bodyFuture!) as Map<String, dynamic>;
      final sys = body['systemInstruction'] as Map<String, dynamic>;
      expect((sys['parts'] as List).first['text'], 'Be nice');
      final contents = body['contents'] as List;
      expect(contents.length, 1, reason: 'system message excluded');
      expect(contents.first['role'], 'user');
    });
  });

  testWidgets('surfaces API key errors as AiError', (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startGeminiServer(statusCode: 400);
      addTearDown(server.close);

      final client = GeminiStreamClient(
        apiKey: 'bad-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      AiError? error;
      await for (final event in client.streamChat(messages, model: 'gemini-2')) {
        if (event is AiError) error = event;
      }

      expect(error, isNotNull);
      expect(error!.message, contains('API key not valid'));
    });
  });
}
