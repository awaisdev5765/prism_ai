/// Prism AI — a lean, provider-agnostic streaming client for AI chat
/// completions, with typed events and zero heavyweight dependencies.
///
/// One client implementation covers every OpenAI-compatible endpoint
/// (OpenAI, Ollama, Groq, DeepSeek, Together, LM Studio, vLLM).
///
/// ```dart
/// final client = OpenAiStreamClient(
///   baseUrl: 'http://localhost:11434/v1', // Ollama
/// );
/// await for (final event in client.streamChat(messages, model: 'llama3')) {
///   if (event is AiTextDelta) setState(() => response += event.text);
/// }
/// ```
///
/// Designed to pair with the [Prism](https://pub.dev/packages/prism_markdown)
/// family: stream into `PrismMarkdown` for live AI-response rendering.
library;

export 'src/ai_events.dart';
export 'src/chat_message.dart';
export 'src/openai_stream_client.dart';
export 'src/sse_parser.dart';
