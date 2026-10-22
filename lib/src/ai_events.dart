/// Typed, provider-agnostic events emitted while an AI completion streams.
///
/// Every provider adapter normalizes its wire format into this event
/// sequence, so UI code never touches provider-specific payloads.
library;

import 'package:flutter/foundation.dart' show immutable;

/// A chunk of assistant text has arrived.
@immutable
final class AiTextDelta {
  const AiTextDelta(this.text);
  final String text;
  @override
  String toString() => 'AiTextDelta(${text.length} chars)';
}

/// The model invoked a tool.
@immutable
final class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    this.argumentsJson = '',
  });
  final String id;
  final String name;
  final String argumentsJson;
  @override
  String toString() => 'AiToolCall($name, ${argumentsJson.length} chars)';
}

/// The completion finished normally.
@immutable
final class AiDone {
  const AiDone({this.finishReason = 'stop', this.usage});
  final String finishReason;
  final AiUsage? usage;
  @override
  String toString() => 'AiDone($finishReason)';
}

/// Token usage reported by the provider, when available.
@immutable
final class AiUsage {
  const AiUsage({
    required this.inputTokens,
    required this.outputTokens,
  });
  final int inputTokens;
  final int outputTokens;
  @override
  String toString() => 'AiUsage(in: $inputTokens, out: $outputTokens)';
}

/// The stream failed. The error is provider-agnostic.
@immutable
final class AiError {
  const AiError(this.message, {this.statusCode, this.cause});
  final String message;
  final int? statusCode;
  final Object? cause;
  @override
  String toString() => 'AiError($message${statusCode != null ? ' [$statusCode]' : ''})';
}
