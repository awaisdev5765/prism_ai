import 'package:flutter/foundation.dart' show immutable;

/// The role of a message in a conversation.
enum AiRole { system, user, assistant, tool }

/// A single message in a chat conversation.
@immutable
final class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});
  const AiChatMessage.system(String content)
      : this(role: AiRole.system, content: content);
  const AiChatMessage.user(String content)
      : this(role: AiRole.user, content: content);
  const AiChatMessage.assistant(String content)
      : this(role: AiRole.assistant, content: content);

  final AiRole role;
  final String content;

  Map<String, Object?> toJson() => {'role': role.name, 'content': content};

  @override
  String toString() => 'AiChatMessage(${role.name}: ${content.length} chars)';
}
