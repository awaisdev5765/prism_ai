import 'dart:convert';

/// A tool the model can invoke — the unit of AI agency.
///
/// ```dart
/// AiTool(
///   name: 'get_weather',
///   description: 'Get current weather for a city',
///   parametersSchema: {
///     'type': 'object',
///     'properties': {
///       'city': {'type': 'string'},
///     },
///     'required': ['city'],
///   },
///   execute: (args) async => 'Sunny, 25°C',
/// )
/// ```
final class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.execute,
    this.parametersSchema = const {
      'type': 'object',
      'properties': {},
    },
  });

  /// Tool name the model references (snake_case, e.g. `get_weather`).
  final String name;

  /// Natural-language description the model uses to decide when to call it.
  final String description;

  /// JSON Schema describing the arguments object.
  final Map<String, Object?> parametersSchema;

  /// Executes the tool with parsed arguments and returns the string result
  /// the model should see. Non-string returns are JSON-encoded automatically.
  final Future<Object?> Function(Map<String, Object?> arguments) execute;

  /// Runs the tool with raw JSON arguments (from the model) and returns
  /// the string result.
  Future<String> runFromJson(String argumentsJson) async {
    Map<String, Object?> args;
    try {
      args = argumentsJson.trim().isEmpty
          ? {}
          : jsonDecode(argumentsJson) as Map<String, Object?>;
    } on FormatException {
      args = {};
    }
    final result = await execute(args);
    if (result is String) return result;
    return jsonEncode(result);
  }

  /// The OpenAI tool declaration shape.
  Map<String, Object?> toRequestJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parametersSchema,
        },
      };
}
