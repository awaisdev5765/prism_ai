# Prism AI

![pub version](https://img.shields.io/pub/v/prism_ai) ![pub points](https://img.shields.io/pub/points/prism_ai?label=points&color=green) ![pub likes](https://img.shields.io/pub/likes/prism_ai?label=likes&color=red)

A lean, provider-agnostic streaming client for AI chat completions.
One package covers **OpenAI, Ollama, Groq, DeepSeek, Together, LM Studio,
vLLM** and every other OpenAI-compatible endpoint — with typed streaming
events and zero heavyweight dependencies.

Part of the [Prism](https://pub.dev/packages/prism_markdown) family.

## Usage

```dart
final client = OpenAiStreamClient(
  baseUrl: 'http://localhost:11434/v1', // Ollama
  // baseUrl: 'https://api.openai.com/v1', apiKey: 'sk-...',
);

await for (final event in client.streamChat(messages, model: 'llama3')) {
  switch (event) {
    case AiTextDelta(:final text):
      setState(() => response += text);   // stream into PrismMarkdown!
    case AiToolCall(:final name):
      handleTool(name);
    case AiDone(:final usage):
      log('done: ${usage?.outputTokens} tokens');
    case AiError(:final message):
      showError(message);
  }
}
```

## Why prism_ai

| | prism_ai | dart_openai | langchain_dart |
|---|---|---|---|
| Streaming SSE with typed events | ✅ | ❌ | ✅ |
| One client, any OpenAI-compatible host | ✅ | ❌ | partial |
| Lightweight (http only) | ✅ | ❌ | ❌ heavy |
| Maintained | ✅ | ❌ abandoned | ✅ |

Pairs with [**prism_markdown**](https://pub.dev/packages/prism_markdown):
render streaming AI responses as live markdown.

## Architecture

- `SseParser` — stateful incremental SSE parser (chunk-safe, CRLF-safe)
- `OpenAiStreamClient` — streams `/chat/completions` with auth + headers
- Typed events: `AiTextDelta`, `AiToolCall`, `AiDone`, `AiError`

## Providers

| Provider | Client | Notes |
|---|---|---|
| OpenAI & every OpenAI-compatible host | `OpenAiStreamClient` | OpenAI, Ollama, Groq, DeepSeek, Together, LM Studio, vLLM, Azure |
| Anthropic (Claude) | `AnthropicStreamClient` | Messages API with tool-use streaming |
| Google Gemini | `GeminiStreamClient` | `streamGenerateContent` (SSE) |

## Chat UI included

`AiChatView` renders a full streaming chat conversation from an
`AiChatController` — user/assistant bubbles, typing indicator, auto-scroll:

```dart
final controller = AiChatController();
AiChatView(
  controller: controller,
  onSendMessage: (text) async {
    controller.sendUserMessage(text);
    await for (final event in client.streamChat(
      controller.messages, model: 'llama3')) {
      switch (event) {
        case AiTextDelta(:final text):
          controller.appendAssistantDelta(text);
        case AiDone():
          controller.finishAssistant();
        case AiError(:final message):
          controller.reportError(message);
      }
    }
  },
)
```

## Roadmap

- [x] Embeddings API support
- [x] Markdown rendering inside assistant bubbles via prism_markdown

## Contributing

Issues, PRs and feature requests are welcome!

```bash
git clone https://github.com/awaisdev5765/prism_ai.git
cd prism_ai
flutter pub get
flutter test        # 34 tests, all passing
flutter analyze     # no issues
```

Before opening a PR:
- Add tests for new features (the repo uses real local servers for SSE/HTTP tests)
- Run `flutter analyze` — no issues
- Update CHANGELOG.md

## License

MIT
