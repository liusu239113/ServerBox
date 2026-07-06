import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/riverpod.dart';
import 'package:surlor_ai/data/model/ai/agent_tools.dart';
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

  /// Agent 工具调用流 —— 一次完整的 AI 轮次（含工具调用）
  Stream<AgentInnerEvent> askWithTools({
    required List<Map<String, String>> conversation,
    required Future<String> Function(String name, Map<String, dynamic> args) onToolCall,
    String? model,
    String? baseUrl,
    String? apiKey,
  }) async* {
    final finalBaseUrl = (baseUrl ?? _settings.askAiBaseUrl.fetch()).trim();
    final finalApiKey = (apiKey ?? _settings.askAiApiKey.fetch()).trim();
    final finalModel = (model ?? _settings.askAiModel.fetch()).trim();

    if (finalBaseUrl.isEmpty || finalApiKey.isEmpty || finalModel.isEmpty) {
      yield AgentInnerErr('AI 配置不完整，请先配置 API 地址、Key 和模型');
      return;
    }

    final parsed = Uri.tryParse(finalBaseUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      yield AgentInnerErr('API 地址格式无效: $finalBaseUrl');
      return;
    }

    final uri = composeChatCompletionsUri(finalBaseUrl);
    final authHeader = finalApiKey.startsWith('Bearer ') ? finalApiKey : 'Bearer $finalApiKey';
    final headers = <String, String>{
      Headers.acceptHeader: 'text/event-stream',
      Headers.contentTypeHeader: Headers.jsonContentType,
      'Authorization': authHeader,
    };

    final messages = <Map<String, dynamic>>[
      for (final msg in conversation)
        {'role': msg['role'] ?? 'user', 'content': msg['content'] ?? ''},
    ];

    final requestBody = {
      'model': finalModel,
      'stream': true,
      'messages': messages,
      'tools': builtinAgentTools,
    };

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
      yield AgentInnerErr(e.message ?? '请求失败', e);
      return;
    }

    final body = response.data;
    if (body == null) {
      yield AgentInnerErr('空响应');
      return;
    }

    final contentBuffer = StringBuffer();
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
            if (line.isEmpty || !line.startsWith('data:')) continue;
            final payload = line.substring(5).trim();
            if (payload.isEmpty) continue;
            if (payload == '[DONE]') {
              // flush any pending tool builds and execute
              final toolResults = <String>[];
              for (final builder in toolBuilders.values) {
                final cmd = builder.tryBuild(force: true);
                if (cmd != null) {
                  final args = _parseToolArgs(builder.arguments.toString(), cmd.toolName);
                  try {
                    final result = await onToolCall(cmd.toolName ?? 'unknown', args);
                    toolResults.add(result);
                  } catch (e) {
                    toolResults.add('Error: $e');
                  }
                }
              }
              yield AgentInnerDone(contentBuffer.toString(), toolResults);
              return;
            }

            Map<String, dynamic> json;
            try {
              json = jsonDecode(payload) as Map<String, dynamic>;
            } catch (e, s) {
              continue;
            }

            final choices = json['choices'];
            if (choices is! List || choices.isEmpty) continue;

            for (final choice in choices) {
              if (choice is! Map<String, dynamic>) continue;
              final delta = choice['delta'];
              if (delta is Map<String, dynamic>) {
                final content = delta['content'];
                if (content is String && content.isNotEmpty) {
                  contentBuffer.write(content);
                  yield AgentInnerThink(content);
                } else if (content is List) {
                  for (final item in content) {
                    if (item is Map<String, dynamic>) {
                      final text = item['text'] as String?;
                      if (text != null && text.isNotEmpty) {
                        contentBuffer.write(text);
                        yield AgentInnerThink(text);
                      }
                    }
                  }
                }

                final toolCalls = delta['tool_calls'];
                if (toolCalls is List) {
                  for (final toolCall in toolCalls) {
                    if (toolCall is! Map<String, dynamic>) continue;
                    final index = toolCall['index'] as int? ?? 0;
                    final builder = toolBuilders.putIfAbsent(index, _ToolCallBuilder.new);
                    final function = toolCall['function'];
                    if (function is Map<String, dynamic>) {
                      builder.name ??= function['name'] as String?;
                      final args = function['arguments'] as String?;
                      if (args != null && args.isNotEmpty) builder.arguments.write(args);
                    }
                  }
                }
              }

              final finishReason = choice['finish_reason'];
              if (finishReason == 'tool_calls') {
                final toolResults = <String>[];
                for (final entry in toolBuilders.entries) {
                  final builder = entry.value;
                  builder.tryBuild(force: true);
                  final args = _parseToolArgs(builder.arguments.toString(), builder.name);
                  try {
                    final result = await onToolCall(builder.name ?? 'unknown', args);
                    toolResults.add(result);
                  } catch (e) {
                    toolResults.add('Error: $e');
                  }
                }
                toolBuilders.clear();
                yield AgentInnerDone(contentBuffer.toString(), toolResults);
                return;
              }
            }
          }
        }
      }

      // flush remaining
      if (contentBuffer.isNotEmpty) {
        final toolResults = <String>[];
        for (final builder in toolBuilders.values) {
          builder.tryBuild(force: true);
          final args = _parseToolArgs(builder.arguments.toString(), builder.name);
          try {
            final result = await onToolCall(builder.name ?? 'unknown', args);
            toolResults.add(result);
          } catch (e) {
            toolResults.add('Error: $e');
          }
        }
        yield AgentInnerDone(contentBuffer.toString(), toolResults);
      }
    } catch (e, s) {
      yield AgentInnerErr('$e', e);
      return;
    }
  }

  Map<String, dynamic> _parseToolArgs(String raw, String? toolName) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {'command': raw, 'name': toolName ?? ''};
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

// ─────────── Agent 内部事件（公开供 AgentService 使用）───────────
sealed class AgentInnerEvent { const AgentInnerEvent(); }
class AgentInnerThink extends AgentInnerEvent {
  final String delta; const AgentInnerThink(this.delta);
}
class AgentInnerDone extends AgentInnerEvent {
  final String text; final List<String> toolResults;
  const AgentInnerDone(this.text, this.toolResults);
}
class AgentInnerErr extends AgentInnerEvent {
  final String msg; final Object? err;
  const AgentInnerErr(this.msg, [this.err]);
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
