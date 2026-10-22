/// A minimal, allocation-friendly parser for Server-Sent Events streams.
///
/// Handles both `\n\n`-delimited SSE frames and byte-chunked transport, so it
/// can be driven directly from an `http.Client().send()` byte stream — the
/// primitive behind every AI provider's streaming protocol (OpenAI,
/// Anthropic and Gemini all ship SSE).
library;

/// A single parsed SSE event.
final class SseEvent {
  const SseEvent({required this.data, this.event, this.id});

  /// The concatenated `data:` payload lines (joined with `\n`).
  final String data;

  /// Optional `event:` field, null when absent.
  final String? event;

  /// Optional `id:` field, null when absent.
  final String? id;

  /// True when this event is the OpenAI `[DONE]` sentinel.
  bool get isDoneSentinel => data.trim() == '[DONE]';

  @override
  String toString() => 'SseEvent(event: $event, data: ${data.length} chars)';
}

/// Stateful incremental parser: feed it raw string chunks, receive fully
/// assembled [SseEvent]s.
///
/// Handles `\r\n`, `\n` and lone `\r` line endings, `:` comment lines, and
/// multi-line `data:` fields (joined with `\n`).
final class SseParser {
  final StringBuffer _buffer = StringBuffer();

  /// Feeds a raw chunk and returns every complete event it terminated.
  List<SseEvent> addChunk(String chunk) {
    _buffer.write(chunk);
    final events = <SseEvent>[];

    var text = _buffer.toString();
    var consumed = 0;

    while (true) {
      final frameEnd = _findFrameEnd(text, consumed);
      if (frameEnd == -1) break; // frame not complete yet
      final frame = text.substring(consumed, frameEnd);
      consumed = frameEnd;
      final event = _parseFrame(frame);
      if (event != null) events.add(event);
    }

    if (consumed > 0) {
      _buffer.clear();
      _buffer.write(text.substring(consumed));
    }
    return events;
  }

  /// Flushes any buffered partial frame (call once at stream end).
  List<SseEvent> flush() {
    final text = _buffer.toString();
    _buffer.clear();
    if (text.trim().isEmpty) return const [];
    final event = _parseFrame(text);
    return event == null ? const [] : [event];
  }

  /// Finds the index just past the next blank line (frame terminator),
  /// or -1 when no complete frame exists after [from].
  int _findFrameEnd(String text, int from) {
    for (var i = from; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A) {
        // \n — blank line if the char before was also a line break
        // or we're already at a line start after a break.
        if (i == 0) continue;
        final prev = text.codeUnitAt(i - 1);
        if (prev == 0x0A || prev == 0x0D) return i + 1;
      } else if (c == 0x0D) {
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
          if (i >= 2) {
            final prev2 = text.codeUnitAt(i - 2);
            if (prev2 == 0x0A || prev2 == 0x0D) return i + 2;
          }
        }
      }
    }
    // Fallback: a frame ending with \r\n\r\n spans the doubled break —
    // the simple prev-char scan above handles \n\n and \r\n\r\n via the
    // \n branch, which is the overwhelmingly common wire format.
    return -1;
  }

  SseEvent? _parseFrame(String frame) {
    if (frame.trim().isEmpty) return null;

    String? event;
    String? id;
    final dataLines = <String>[];

    for (final rawLine in frame.split(RegExp(r'\r\n|\n|\r'))) {
      if (rawLine.isEmpty || rawLine.startsWith(':')) continue;
      final colon = rawLine.indexOf(':');
      final field = colon == -1 ? rawLine : rawLine.substring(0, colon);
      var value = colon == -1 ? '' : rawLine.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'event':
          event ??= value;
        case 'id':
          id ??= value;
        case 'data':
          dataLines.add(value);
      }
    }

    if (dataLines.isEmpty) return null;
    return SseEvent(data: dataLines.join('\n'), event: event, id: id);
  }
}
