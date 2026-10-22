import 'ai_events.dart';
import 'chat_message.dart';

/// Common interface for all provider adapters in `prism_ai`.
///
/// Every adapter normalizes its provider's wire format into the same typed
/// event sequence: [AiTextDelta] chunks, optional [AiToolCall]s, and a
/// terminal [AiDone]. Errors surface as [AiError] events — implementations
/// never throw into the consumer's stream loop.
abstract interface class AiStreamClient {
  /// Streams a chat completion as a sequence of typed events.
  Stream<Object> streamChat(
    List<AiChatMessage> messages, {
    required String model,
    double? temperature,
    int? maxTokens,
    Map<String, Object?> extraBody,
  });
}
