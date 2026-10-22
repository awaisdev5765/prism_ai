import 'dart:convert';

import 'package:http/http.dart' as http;

/// Text embeddings from any OpenAI-compatible `/embeddings` endpoint
/// (OpenAI, Ollama, Groq, DeepSeek, Together, LM Studio, vLLM).
final class EmbeddingsClient {
  EmbeddingsClient({
    required this.baseUrl,
    this.apiKey,
    http.Client? client,
    Map<String, String>? extraHeaders,
  })  : _client = client ?? http.Client(),
        _extraHeaders = extraHeaders ?? const {};

  final String baseUrl;
  final String? apiKey;
  final http.Client _client;
  final Map<String, String> _extraHeaders;

  /// Embeds one or more texts, returning one vector per input
  /// (same order as [inputs]).
  ///
  /// ```dart
  /// final vectors = await client.embed(['hello world'], model: 'nomic-embed-text');
  /// print(vectors.first.length); // e.g. 768
  /// ```
  Future<List<List<double>>> embed(
    List<String> inputs, {
    required String model,
    Map<String, Object?> extraBody = const {},
  }) async {
    if (inputs.isEmpty) {
      throw ArgumentError.value(inputs, 'inputs', 'must not be empty');
    }

    final uri = Uri.parse('$baseUrl/embeddings');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty)
          'Authorization': 'Bearer $apiKey',
        ..._extraHeaders,
      },
      body: jsonEncode({
        'model': model,
        'input': inputs,
        ...extraBody,
      }),
    );

    if (response.statusCode != 200) {
      throw EmbeddingsException(
        'Embeddings request failed with HTTP ${response.statusCode}: '
        '${response.body}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final data = json['data'] as List<Object?>? ?? const [];

    final sorted = [...data]..sort((a, b) {
        final ia = (a as Map<String, Object?>?)?['index'];
        final ib = (b as Map<String, Object?>?)?['index'];
        return (ia as num? ?? 0).compareTo(ib as num? ?? 0);
      });

    return [
      for (final entry in sorted)
        [
          for (final v in (entry as Map<String, Object?>?)?['embedding']
                  as List<Object?>? ??
              const [])
            (v as num).toDouble(),
        ],
      ];
  }

  /// Convenience for a single input.
  Future<List<double>> embedOne(String input, {required String model}) async {
    final vectors = await embed([input], model: model);
    return vectors.first;
  }
}

/// Thrown when the embeddings request fails.
class EmbeddingsException implements Exception {
  EmbeddingsException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'EmbeddingsException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}
