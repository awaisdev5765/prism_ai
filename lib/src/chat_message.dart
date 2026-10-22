import 'package:flutter/foundation.dart' show immutable;

/// The role of a message in a conversation.
enum AiRole { system, user, assistant, tool }

/// A single message in a chat conversation.
@immutable
final class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.content,
    this.toolCalls = const [],
    this.toolCallId,
  });

  factory AiChatMessage.system(String content) =>
      AiChatMessage(role: AiRole.system, content: content);

  factory AiChatMessage.user(String content) =>
      AiChatMessage(role: AiRole.user, content: content);

  factory AiChatMessage.assistant(String content) =>
      AiChatMessage(role: AiRole.assistant, content: content);

  /// An assistant message that invokes tools (OpenAI protocol shape).
  factory AiChatMessage.assistantWithToolCalls(
    List<AiToolCallRequest> toolCalls,
  ) =>
      AiChatMessage(role: AiRole.assistant, content: '', toolCalls: toolCalls);

  /// A tool result answering a specific tool call.
  factory AiChatMessage.toolResult({
    required String toolCallId,
    required String content,
  }) =>
      AiChatMessage(
        role: AiRole.tool,
        content: content,
        toolCallId: toolCallId,
      );

  final AiRole role;
  final String content;

  /// For assistant messages that invoke tools: the parsed tool calls.
  final List<AiToolCallRequest> toolCalls;

  /// For tool-role messages: the id of the tool call this result answers.
  final String? toolCallId;

  Map<String, Object?> toJson() {
    switch (role) {
      case AiRole.assistant when toolCalls.isNotEmpty:
        return {
          'role': 'assistant',
          'content': content.isEmpty ? null : content,
          'tool_calls': [for (final t in toolCalls) t.toJson()],
        };
      case AiRole.tool:
        return {
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': content,
        };
      default:
        return {'role': role.name, 'content': content};
    }
  }

  @override
  String toString() => 'AiChatMessage(${role.name}: ${content.length} chars)';
}

/// A tool invocation declared by the assistant (OpenAI protocol shape).
@immutable
final class AiToolCallRequest {
  const AiToolCallRequest({
    required this.id,
    required this.name,
    this.argumentsJson = '',
  });

  final String id;
  final String name;
  final String argumentsJson;

  Map<String, Object?> toJson() => {
        'type': 'function',
        'id': id,
        'function': {'name': name, 'arguments': argumentsJson},
      };

  @override
  String toString() => 'AiToolCallRequest($name, $argumentsJson)';
}
