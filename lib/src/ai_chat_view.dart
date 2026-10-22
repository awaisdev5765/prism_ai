import 'package:flutter/material.dart';

import 'ai_client.dart';
import 'chat_message.dart';

/// A ready-made streaming chat UI built on the `prism_ai` event model.
///
/// Feed it a conversation and a [Stream<AiChatMessage>] (or wire it to any
/// [AiStreamClient] yourself via [AiChatController]), and it renders the
/// conversation with user/assistant bubbles, live typing indicator, and
/// auto-scroll as new content arrives.
///
/// ```dart
/// final controller = AiChatController();
/// AiChatView(controller: controller)
/// ```
///
/// Push streaming events into the controller:
///
/// ```dart
/// await for (final event in client.streamChat(messages, model: 'gpt-4o')) {
///   if (event is AiTextDelta) controller.appendAssistantDelta(event.text);
///   if (event is AiDone) controller.finishAssistant();
/// }
/// ```
final class AiChatController extends ChangeNotifier {
  final List<AiChatMessage> _messages = [];
  List<AiChatMessage> get messages => List.unmodifiable(_messages);

  /// Whether a response is currently streaming in.
  bool isStreaming = false;

  /// Sends a user message and starts a streaming assistant response.
  void sendUserMessage(String text) {
    _messages.add(AiChatMessage.user(text));
    _messages.add(const AiChatMessage.assistant(''));
    isStreaming = true;
    notifyListeners();
  }

  /// Appends a chunk of assistant text to the streaming response.
  void appendAssistantDelta(String text) {
    if (_messages.isEmpty) return;
    final last = _messages.last;
    if (last.role != AiRole.assistant) return;
    _messages[_messages.length - 1] =
        AiChatMessage.assistant(last.content + text);
    notifyListeners();
  }

  /// Marks the streaming response as finished.
  void finishAssistant() {
    isStreaming = false;
    notifyListeners();
  }

  /// Reports an error as the assistant's response content.
  void reportError(String message) {
    if (_messages.isNotEmpty && _messages.last.role == AiRole.assistant) {
      _messages[_messages.length - 1] =
          AiChatMessage.assistant('⚠ $message');
    }
    isStreaming = false;
    notifyListeners();
  }

  /// Clears the conversation.
  void clear() {
    _messages.clear();
    isStreaming = false;
    notifyListeners();
  }
}

/// Renders a chat conversation with streaming assistant responses.
///
/// Assistant messages are shown in a neutral surface bubble; user messages
/// in a primary-colored bubble aligned to the right. While
/// [AiChatController/isStreaming] is true, a typing indicator is shown and
/// the list auto-scrolls to the latest content.
final class AiChatView extends StatefulWidget {
  const AiChatView({
    required this.controller,
    this.onSendMessage,
    this.inputHint = 'Send a message…',
    this.userBubbleColor,
    this.assistantBubbleColor,
    this.padding = const EdgeInsets.all(12),
    this.scrollController,
    super.key,
  });

  /// Source of truth for the conversation.
  final AiChatController controller;

  /// Called when the user submits the input field. Wire this to your
  /// client: call [AiChatController/sendUserMessage], then stream the
  /// provider events into the controller.
  final void Function(String text)? onSendMessage;

  /// Hint text for the input field.
  final String inputHint;

  /// Bubble colors — defaults derive from the ambient theme.
  final Color? userBubbleColor;
  final Color? assistantBubbleColor;

  /// Outer padding of the view.
  final EdgeInsets padding;

  /// Optional external scroll controller (auto-scroll works out of the box).
  final ScrollController? scrollController;

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  late final ScrollController _scroll;
  final _inputController = TextEditingController();
  bool _ownsScroll = false;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _scroll = widget.scrollController!;
    } else {
      _scroll = ScrollController();
      _ownsScroll = true;
    }
    widget.controller.addListener(_autoScroll);
  }

  @override
  void didUpdateWidget(covariant AiChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_autoScroll);
      widget.controller.addListener(_autoScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_autoScroll);
    if (_ownsScroll) _scroll.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _autoScroll() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _submit() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    widget.controller.sendUserMessage(text);
    widget.onSendMessage?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userColor =
        widget.userBubbleColor ?? theme.colorScheme.primaryContainer;
    final assistantColor =
        widget.assistantBubbleColor ?? theme.colorScheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.messages;
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: widget.padding,
                itemCount:
                    messages.length + (widget.controller.isStreaming ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= messages.length) {
                    return const _TypingIndicator();
                  }
                  final message = messages[index];
                  final isUser = message.role == AiRole.user;
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.sizeOf(context).width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: isUser ? userColor : assistantColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft:
                              Radius.circular(isUser ? 16 : 4),
                          bottomRight:
                              Radius.circular(isUser ? 4 : 16),
                        ),
                      ),
                      child: SelectableText(
                        message.content.isEmpty && !isUser
                            ? '…'
                            : message.content,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.onSendMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: InputDecoration(
                          hintText: widget.inputHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _submit,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Three pulsing dots shown while the assistant response streams in.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(3, (i) {
          return FadeTransition(
            opacity: Tween<double>(begin: 0.2, end: 1.0).animate(
              CurvedAnimation(
                parent: _controller,
                curve: Interval(i * 0.2, (i + 1) * 0.2 + 0.4,
                    curve: Curves.easeInOut),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: CircleAvatar(
                radius: 4,
                backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }),
      ),
    );
  }
}
