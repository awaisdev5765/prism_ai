import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ai/prism_ai.dart';
import 'package:prism_markdown/prism_markdown.dart' show PrismMarkdown;

void main() {
  Future<void> pumpView(
    WidgetTester tester,
    AiChatController controller, {
    bool markdown = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiChatView(
          controller: controller,
          onSendMessage: null,
          markdownAssistantResponses: markdown,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('renders user and assistant bubbles', (tester) async {
    final controller = AiChatController();
    await pumpView(tester, controller);

    controller.sendUserMessage('Hello!');
    controller.appendAssistantDelta('Hi there 👋');
    controller.finishAssistant();
    await tester.pump();

    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Hi there 👋'), findsOneWidget);
  });

  testWidgets('sendUserMessage appends user + empty assistant and starts '
      'streaming', (tester) async {
    final controller = AiChatController();
    await pumpView(tester, controller);

    controller.sendUserMessage('What is Dart?');

    expect(controller.messages.length, 2);
    expect(controller.messages.first.role, AiRole.user);
    expect(controller.isStreaming, isTrue);
  });

  testWidgets('appendAssistantDelta streams text into the last bubble',
      (tester) async {
    final controller = AiChatController();
    controller.sendUserMessage('hi');

    controller.appendAssistantDelta('Hello');
    controller.appendAssistantDelta(' world');
    controller.finishAssistant();

    expect(controller.messages.last.content, 'Hello world');
    expect(controller.isStreaming, isFalse);
  });

  testWidgets('input field sends messages through onSendMessage',
      (tester) async {
    final controller = AiChatController();
    final sent = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiChatView(
          controller: controller,
          onSendMessage: sent.add,
        ),
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ping');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, ['ping']);
    expect(controller.messages.first.content, 'ping');
  });

  testWidgets('clear() empties the conversation', (tester) async {
    final controller = AiChatController();
    controller.sendUserMessage('hi');
    controller.clear();

    expect(controller.messages, isEmpty);
    expect(controller.isStreaming, isFalse);
  });

  group('markdown assistant responses', () {
    testWidgets('assistant bubble renders markdown when enabled',
        (tester) async {
      final controller = AiChatController();
      controller.sendUserMessage('hi');
      controller.appendAssistantDelta('# Title\n\n- item');
      controller.finishAssistant();
      await pumpView(tester, controller, markdown: true);
      await tester.pumpAndSettle();

      expect(find.text('Title'), findsOneWidget);
      expect(find.text('item'), findsOneWidget);
    });

    testWidgets('assistant bubble stays plain text when disabled',
        (tester) async {
      final controller = AiChatController();
      controller.sendUserMessage('hi');
      controller.appendAssistantDelta('# Title');
      controller.finishAssistant();
      await pumpView(tester, controller, markdown: false);

      expect(find.text('# Title'), findsOneWidget);
      expect(find.byType(PrismMarkdown), findsNothing);
    });

    testWidgets('user bubbles never render markdown', (tester) async {
      final controller = AiChatController();
      controller.sendUserMessage('# not a heading');
      controller.finishAssistant();
      await pumpView(tester, controller, markdown: true);

      expect(find.text('# not a heading'), findsOneWidget);
    });
  });
}
