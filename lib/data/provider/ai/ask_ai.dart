import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/riverpod.dart';
import 'package:surlor_ai/data/model/ai/ask_ai_models.dart';
import 'package:surlor_ai/data/res/store.dart';
import 'package:surlor_ai/data/store/setting.dart';

final askAiRepositoryProvider = Provider<AskAiRepository>((ref) {
  return AskAiRepository();
});

class AskAiRepository {
  AskAiRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  SettingStore get _settings => Stores.setting;

  /// Streams the AI response using the configured endpoint.
  Stream<AskAiEvent> ask({
    required String selection,
    String? localeHint,
    List<AskAiMessage> conversation = const [],
  }) async* {
    final baseUrl = _settings.askAiBaseUrl.fetch().trim();
    final apiKey = _settings.askAiApiKey.fetch().trim();
    final model = _settings.askAiModel.fetch().trim();

    final missing = <AskAiConfigField>[];
    if (baseUrl.isEmpty) missing.add(AskAiConfigField.baseUrl);
    if (apiKey.isEmpty) missing.add(AskAiConfigField.apiKey);
    if (model.isEmpty) missing.add(AskAiConfigField.model);
    if (missing.isNotEmpty) {
      throw AskAiConfigException(missingFields: missing);
    }

    final parsedBaseUri = Uri.tryParse(baseUrl);
    final hasScheme = parsedBaseUri?.hasScheme ?? false;
    final hasHost = (parsedBaseUri?.host ?? '').isNotEmpty;
    if (!hasScheme || !hasHost) {
      throw AskAiConfigException(invalidBaseUrl: baseUrl);
    }

    final uri = composeChatCompletionsUri(baseUrl);
    final authHeader = apiKey.startsWith('Bearer ') ? apiKey : 'Bearer $apiKey';
    final headers = <String, String>{
      Headers.acceptHeader: 'text/event-stream',
      Headers.contentTypeHeader: Headers.jsonContentType,
      'Authorization': authHeader,
    };

    final requestBody = _buildRequestBody(
      model: model,
      selection: selection,
      localeHint: localeHint,
      conversation: conversation,
    );

    Response<ResponseBody> response;
    try {
      response = await _dio.postUri<ResponseBody>(
        uri,
        data: jsonEncode(requestBody),
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException catch (e) {
      throw AskAiNetworkException(
        message: e.message ?? 'Request failed',
        cause: e,
      );
    }

    final body = response.data;
    if (body == null) {
      throw AskAiNetworkException(message: 'Empty response body');
    }

    final contentBuffer = StringBuffer();
    final commands = <AskAiCommand>[];
    final toolBuilders = <int, _ToolCallBuilder>{};
    final utf8Stream = body.stream.cast<List<int>>().transform(utf8.decoder);
    final carry = StringBuffer();

    try {
      await for (final chunk in utf8Stream) {
        carry.write(chunk);
        final segments = carry.toString().split('\n\n');
        carry
          ..clear()
          ..write(segments.removeLast());

        for (final segment in segments) {
          final lines = segment.split('\n');
          for (final rawLine in lines) {
            final line = rawLine.trim();
            if (line.isEmpty || !line.startsWith('data:')) {
              continue;
            }
            final payload = line.substring(5).trim();
            if (payload.isEmpty) {
              continue;
            }
            if (payload == '[DONE]') {
              yield AskAiCompleted(
                fullText: contentBuffer.toString(),
                commands: List.unmodifiable(commands),
              );
              return;
            }

            Map<String, dynamic> json;
            try {
              json = jsonDecode(payload) as Map<String, dynamic>;
            } catch (e, s) {
              yield AskAiStreamError(e, s);
              continue;
            }

            final choices = json['choices'];
            if (choices is! List || choices.isEmpty) {
              continue;
            }

            for (final choice in choices) {
              if (choice is! Map<String, dynamic>) {
                continue;
              }
              final delta = choice['delta'];
              if (delta is Map<String, dynamic>) {
                final content = delta['content'];
                if (content is String && content.isNotEmpty) {
                  contentBuffer.write(content);
                  yield AskAiContentDelta(content);
                } else if (content is List) {
                  for (final item in content) {
                    if (item is Map<String, dynamic>) {
                      final text = item['text'] as String?;
                      if (text != null && text.isNotEmpty) {
                        contentBuffer.write(text);
                        yield AskAiContentDelta(text);
                      }
                    }
                  }
                }

                final toolCalls = delta['tool_calls'];
                if (toolCalls is List) {
                  for (final toolCall in toolCalls) {
                    if (toolCall is! Map<String, dynamic>) continue;
                    final index = toolCall['index'] as int? ?? 0;
                    final builder = toolBuilders.putIfAbsent(
                      index,
                      _ToolCallBuilder.new,
                    );
                    final function = toolCall['function'];
                    if (function is Map<String, dynamic>) {
                      builder.name ??= function['name'] as String?;
                      final args = function['arguments'] as String?;
                      if (args != null && args.isNotEmpty) {
                        builder.arguments.write(args);
                        final command = builder.tryBuild();
                        if (command != null) {
                          commands.add(command);
                          yield AskAiToolSuggestion(command);
                        }
                      }
                    }
                  }
                }
              }

              final finishReason = choice['finish_reason'];
              if (finishReason == 'tool_calls') {
                for (final builder in toolBuilders.values) {
                  final command = builder.tryBuild(force: true);
                  if (command != null) {
                    commands.add(command);
                    yield AskAiToolSuggestion(command);
                  }
                }
                toolBuilders.clear();
              }
            }
          }
        }
      }

      // Flush remaining buffer if [DONE] not received.
      if (contentBuffer.isNotEmpty || commands.isNotEmpty) {
        yield AskAiCompleted(
          fullText: contentBuffer.toString(),
          commands: List.unmodifiable(commands),
        );
      }
    } catch (e, s) {
      yield AskAiStreamError(e, s);
      return;
    }
  }

  /// 构建请求体，支持自定义 tools
  Map<String, dynamic> _buildRequestBody({
    required String model,
    required String selection,
    String? localeHint,
    List<AskAiMessage> conversation = const [],
    List<Map<String, dynamic>>? tools,
  }) {
    final messages = <Map<String, String>>[
      {'role': 'user', 'content': selection},
      for (final msg in conversation)
        {'role': msg.apiRole, 'content': msg.content},
    ];
    return {
      'model': model,
      'stream': true,
      'messages': messages,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };
  }

  @visibleForTesting
  static Uri composeChatCompletionsUri(String endpoint) {
    final uri = Uri.parse(endpoint.replaceAll(RegExp(r'/+$'), ''));
    final segments = uri.pathSegments;
    final hasChatCompletionsPath =
        segments.length >= 2 &&
        segments[segments.length - 2] == 'chat' &&
        segments.last == 'completions';

    if (hasChatCompletionsPath) {
      return uri;
    }

    final appendSegments = segments.isNotEmpty && segments.last == 'v1'
        ? ['chat', 'completions']
        : ['v1', 'chat', 'completions'];
    return uri.replace(pathSegments: [...segments, ...appendSegments]);
  }
}

// ─────────── Agent 内部事件 ───────────
sealed class _AgentEvent { const _AgentEvent(); }
class _AgentThink extends _AgentEvent {
  final String delta; const _AgentThink(this.delta);
}
class _AgentToolDone extends _AgentEvent {
  final List<String> results; const _AgentToolDone(this.results);
}
class _AgentDone extends _AgentEvent {
  final String text; final List<String> toolResults;
  const _AgentDone(this.text, this.toolResults);
}
class _AgentErr extends _AgentEvent {
  final String msg; const _AgentErr(this.msg);
}

// SSE 解析事件
sealed class _SseEvent { const _SseEvent(); }
class _SseDelta extends _SseEvent {
  final String text; const _SseDelta(this.text);
}
class _SseTool extends _SseEvent {
  final int idx; final String? name; final String? args;
  const _SseTool({required this.idx, this.name, this.args});
}

// 工具调用缓冲
class _TcData {
  final int idx; String? name; final StringBuffer args = StringBuffer();
  _TcData(this.idx);
}


class _ToolCallBuilder {
  _ToolCallBuilder();

  final StringBuffer arguments = StringBuffer();
  String? name;
  bool _emitted = false;

  AskAiCommand? tryBuild({bool force = false}) {
    if (_emitted && !force) return null;
    final raw = arguments.toString();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final command = decoded['command'] as String?;
      if (command == null || command.trim().isEmpty) {
        if (force) {
          _emitted = true;
        }
        return null;
      }
      final description =
          decoded['description'] as String? ??
          decoded['explanation'] as String? ??
          '';
      _emitted = true;
      return AskAiCommand(
        command: command.trim(),
        description: description.trim(),
        toolName: name,
      );
    } on FormatException {
      if (force) {
        _emitted = true;
      }
      return null;
    }
  }
}

@immutable
enum AskAiConfigField { baseUrl, apiKey, model }

class AskAiConfigException implements Exception {
  const AskAiConfigException({
    this.missingFields = const [],
    this.invalidBaseUrl,
  });

  final List<AskAiConfigField> missingFields;
  final String? invalidBaseUrl;

  bool get hasInvalidBaseUrl => (invalidBaseUrl ?? '').isNotEmpty;

  @override
  String toString() {
    final parts = <String>[];
    if (missingFields.isNotEmpty) {
      parts.add('missing: ${missingFields.map((e) => e.name).join(', ')}');
    }
    if (hasInvalidBaseUrl) {
      parts.add('invalidBaseUrl: $invalidBaseUrl');
    }
    if (parts.isEmpty) {
      return 'AskAiConfigException()';
    }
    return 'AskAiConfigException(${parts.join('; ')})';
  }
}

@immutable
class AskAiNetworkException implements Exception {
  const AskAiNetworkException({required this.message, this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AskAiNetworkException(message: $message)';
}
