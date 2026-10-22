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

## Roadmap

- [ ] Anthropic adapter (SSE)
- [ ] Gemini adapter (streamGenerateContent)
- [ ] Chat UI widget with streaming markdown rendering

## License

MIT
