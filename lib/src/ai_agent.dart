import 'dart:async';

import 'ai_client.dart';
import 'ai_events.dart';
import 'ai_tool.dart';
import 'chat_message.dart';

/// Runs an automatic tool-calling loop on top of any [AiStreamClient].
///
/// Instead of manually handling `AiToolCall` events, feed the agent a list
/// of [AiTool]s and it manages the full round trip:
///
/// 1. Stream a completion
/// 2. If the model calls tools → execute them, append results, loop
/// 3. When the model responds with text → done
///
/// ```dart
/// final agent = AiAgent(
///   client: OpenAiStreamClient(baseUrl: '...', apiKey: '...'),
///   tools: [getWeatherTool, searchTool],
///   maxIterations: 5,
/// );
///
/// final result = await agent.run(
///   [AiChatMessage.user('What is the weather in Lahore?')],
///   model: 'gpt-4o',
/// );
/// print(result.text);
/// ```
final class AiAgent {
  const AiAgent({
    required this.client,
    this.tools = const [],
    this.maxIterations = 8,
    this.onEvent,
  });

  /// The streaming client to use for completions.
  final AiStreamClient client;

  /// Tools the model may invoke.
  final List<AiTool> tools;

  /// Maximum tool-calling iterations before giving up (safety bound).
  final int maxIterations;

  /// Optional callback for every streaming event (for live UI rendering
  /// while the agent works).
  final void Function(Object event)? onEvent;

  /// Runs the agent: streams a completion, executes any tool calls,
  /// feeds results back, and repeats until the model produces a final
  /// text response or [maxIterations] is hit.
  ///
  /// Returns the final assistant text plus the full conversation.
  Future<AiAgentResult> run(
    List<AiChatMessage> messages, {
    required String model,
    double? temperature,
    int? maxTokens,
  }) async {
    final conversation = [...messages];
    final fullText = StringBuffer();

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final textBuffer = StringBuffer();
      final toolCalls = <AiToolCallRequest>[];

      await for (final event in client.streamChat(
        conversation,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
        extraBody: tools.isEmpty
            ? const {}
            : {
                'tools': [for (final t in tools) t.toRequestJson()],
              },
      )) {
        onEvent?.call(event);
        if (event is AiError) {
          return AiAgentResult(
            text: textBuffer.toString(),
            messages: conversation,
            iterations: iteration,
            error: event,
          );
        }
        if (event is AiTextDelta) {
          textBuffer.write(event.text);
        }
        if (event is AiToolCall) {
          toolCalls.add(AiToolCallRequest(
            id: event.id,
            name: event.name,
            argumentsJson: event.argumentsJson,
          ));
        }

      }

      fullText.write(textBuffer.toString());

      // No tool calls → final response, we're done.
      if (toolCalls.isEmpty) {
        conversation.add(AiChatMessage.assistant(textBuffer.toString()));
        return AiAgentResult(
          text: textBuffer.toString(),
          messages: conversation,
          iterations: iteration,
        );
      }

      // Append the assistant's tool-call message.
      conversation.add(AiChatMessage.assistantWithToolCalls(toolCalls));

      // Execute each tool and append results.
      for (final call in toolCalls) {
        final tool = tools.where((t) => t.name == call.name).firstOrNull;
        final result = tool == null
            ? 'Error: unknown tool "${call.name}"'
            : await tool.runFromJson(call.argumentsJson);
        conversation.add(AiChatMessage.toolResult(
          toolCallId: call.id,
          content: result,
        ));
      }
    }

    // Max iterations hit — return what we have.
    return AiAgentResult(
      text: fullText.toString(),
      messages: conversation,
      iterations: maxIterations,
      error: AiError('maxIterations ($maxIterations) reached'),
    );
  }
}

/// The result of an [AiAgent.run] call.
final class AiAgentResult {
  const AiAgentResult({
    required this.text,
    required this.messages,
    required this.iterations,
    this.error,
  });

  /// The accumulated assistant text across all iterations.
  final String text;

  /// The full conversation including tool calls and results.
  final List<AiChatMessage> messages;

  /// How many tool-calling iterations were used.
  final int iterations;

  /// Non-null when the agent hit an error or max iterations.
  final AiError? error;

  bool get isError => error != null;
}

// firstOrNull extension (Dart 3 collection sugar).
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
