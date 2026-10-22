# Changelog

## 0.2.0

- **New provider**: `AnthropicStreamClient` — Anthropic Messages API with
  streaming text deltas, tool-use blocks (`input_json_delta` assembly), and
  usage tracking (`message_start`/`message_delta`)
- **New provider**: `GeminiStreamClient` — Gemini `streamGenerateContent`
  (SSE) with `usageMetadata` reporting
- New `AiStreamClient` interface so providers are interchangeable
- New `AiChatMessage` constructors: `.system()`, `.user()`, `.assistant()`

## 0.1.0

- Initial release: SSE parser, OpenAI-compatible streaming client with
  typed events (AiTextDelta / AiToolCall / AiDone / AiError), auth and
  custom headers. Verified against a real local SSE server.
