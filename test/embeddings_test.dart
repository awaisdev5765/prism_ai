import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ai/prism_ai.dart';
// ContentType comes from dart:io

/// Local OpenAI-compatible /embeddings server.
Future<HttpServer> startEmbeddingsServer({
  int statusCode = 200,
  List<List<double>>? vectors,
}) async {
  final vectorsOut = vectors ??
      [
        [0.1, 0.2, 0.3],
        [0.4, 0.5, 0.6],
      ];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    final requestJson = jsonDecode(body) as Map<String, dynamic>;
    final inputs = requestJson['input'] as List;

    // Return vectors in shuffled index order to verify index-based sorting.
    final data = <Map<String, Object?>>[];
    for (var i = 0; i < inputs.length && i < vectorsOut.length; i++) {
      data.add({'object': 'embedding', 'index': i, 'embedding': vectorsOut[i]});
    }
    // Shuffle deliberately (swap first two) unless single input
    if (data.length > 1) {
      final tmp = data[0];
      data[0] = data[1];
      data[1] = tmp;
    }

    request.response.headers.contentType = ContentType.parse('application/json');
    request.response.statusCode = statusCode;
    request.response.write(jsonEncode({
      'object': 'list',
      'data': data,
      'model': requestJson['model'],
      'usage': {'prompt_tokens': 5, 'total_tokens': 5},
    }));
    await request.response.close();
  });
  return server;
}


// flutter_test installs a fake HttpClient that answers 400 to everything;
// clear it so the local test server can be reached.
void _disableFakeHttpOverrides() {
  HttpOverrides.global = null;
}

void main() {
  testWidgets('embed returns vectors in input order (sorted by index)',
      (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startEmbeddingsServer();
      addTearDown(server.close);

      final client = EmbeddingsClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'test',
      );

      final vectors = await client.embed(
        ['first', 'second'],
        model: 'nomic-embed-text',
      );

      // Server deliberately swapped positions; index sorting restores order.
      expect(vectors.length, 2);
      expect(vectors[0], [0.1, 0.2, 0.3]);
      expect(vectors[1], [0.4, 0.5, 0.6]);
    });
  });

  testWidgets('embedOne returns the first vector', (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startEmbeddingsServer();
      addTearDown(server.close);

      final client = EmbeddingsClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      final vector = await client.embedOne('hello', model: 'm');
      expect(vector, [0.1, 0.2, 0.3]);
    });
  });

  testWidgets('throws EmbeddingsException on HTTP error', (tester) async {
    await tester.runAsync(() async {
      _disableFakeHttpOverrides();
      final server = await startEmbeddingsServer(statusCode: 401);
      addTearDown(server.close);

      final client = EmbeddingsClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'bad',
      );

      await expectLater(
        client.embed(['x'], model: 'm'),
        throwsA(isA<EmbeddingsException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  test('throws on empty inputs', () {
    final client = EmbeddingsClient(baseUrl: 'http://localhost');
    expect(
      () => client.embed([], model: 'm'),
      throwsArgumentError,
    );
  });
}
