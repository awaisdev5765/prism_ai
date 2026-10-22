import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ai/prism_ai.dart';

void main() {
  group('SseParser', () {
    test('parses a complete frame', () {
      final parser = SseParser();
      final events = parser.addChunk('data: {"a":1}\n\n');
      expect(events.length, 1);
      expect(events.first.data, '{"a":1}');
    });

    test('assembles frames delivered in split chunks', () {
      final parser = SseParser();
      expect(parser.addChunk('data: {"me'), isEmpty);
      // The chunk that carries the frame terminator emits the frame.
      final first = parser.addChunk('ssage"}\n\ndata: [DON');
      expect(first.length, 1);
      expect(first.first.data, '{"message"}');
      final second = parser.addChunk('E]\n\n');
      expect(second.length, 1);
      expect(second.first.isDoneSentinel, isTrue);
    });

    test('handles CRLF line endings', () {
      final parser = SseParser();
      final events = parser.addChunk('data: hello\r\n\r\n');
      expect(events.length, 1);
      expect(events.first.data, 'hello');
    });

    test('joins multi-line data with newline', () {
      final parser = SseParser();
      final events = parser.addChunk('data: line1\ndata: line2\n\n');
      expect(events.length, 1);
      expect(events.first.data, 'line1\nline2');
    });

    test('skips comment lines and captures event/id fields', () {
      final parser = SseParser();
      final events = parser
          .addChunk(': keep-alive ping\nevent: message\nid: 42\ndata: x\n\n');
      expect(events.length, 1);
      expect(events.first.event, 'message');
      expect(events.first.id, '42');
      expect(events.first.data, 'x');
    });

    test('flush emits a trailing partial frame', () {
      final parser = SseParser();
      expect(parser.addChunk('data: tail'), isEmpty);
      final events = parser.flush();
      expect(events.length, 1);
      expect(events.first.data, 'tail');
    });
  });
}
