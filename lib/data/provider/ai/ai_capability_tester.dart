import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:surlor_ai/data/provider/ai/ask_ai.dart';

@immutable
class AiCapabilityProbe {
  const AiCapabilityProbe({
    required this.supported,
    required this.message,
  });

  final bool supported;
  final String message;
}

@immutable
class AiCapabilityTestResult {
  const AiCapabilityTestResult({
    required this.text,
    required this.image,
    required this.video,
    required this.tools,
  });

  final AiCapabilityProbe text;
  final AiCapabilityProbe image;
  final AiCapabilityProbe video;
  final AiCapabilityProbe tools;

  String toHumanText() {
    String line(String name, AiCapabilityProbe probe) {
      return '${probe.supported ? '支持' : '不支持'} $name：${probe.message}';
    }

    return [
      line('文本', text),
      line('图像', image),
      line('视频', video),
      line('工具调用', tools),
    ].join('\n');
  }
}

class AiCapabilityTester {
  AiCapabilityTester({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<AiCapabilityTestResult> test({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final text = await _probeText(baseUrl: baseUrl, apiKey: apiKey, model: model);
    final image = await _probeImage(baseUrl: baseUrl, apiKey: apiKey, model: model);
    final video = await _probeVideo(baseUrl: baseUrl, apiKey: apiKey, model: model);
    final tools = await _probeTools(baseUrl: baseUrl, apiKey: apiKey, model: model);
    return AiCapabilityTestResult(
      text: text,
      image: image,
      video: video,
      tools: tools,
    );
  }

  Future<AiCapabilityProbe> _probeText({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    return _probe(
      baseUrl: baseUrl,
      apiKey: apiKey,
      body: {
        'model': model,
        'stream': false,
        'messages': [
          {'role': 'user', 'content': '请只回复 OK，用于测试文本输入能力。'},
        ],
        'max_tokens': 16,
      },
      successMessage: 'chat/completions 文本请求成功。',
      validate: (data) => _hasAssistantOutput(data),
      failureMessage: '没有拿到文本回复。',
    );
  }

  Future<AiCapabilityProbe> _probeImage({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    return _probe(
      baseUrl: baseUrl,
      apiKey: apiKey,
      body: {
        'model': model,
        'stream': false,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '这是一张 1x1 测试图。请只回复 OK。'},
              {
                'type': 'image_url',
                'image_url': {'url': _onePixelPngDataUrl},
              },
            ],
          },
        ],
        'max_tokens': 16,
      },
      successMessage: '模型接受 image_url 多模态输入。',
      validate: (data) => _hasAssistantOutput(data),
      failureMessage: '请求成功但没有图像回复。',
    );
  }

  Future<AiCapabilityProbe> _probeVideo({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    return _probe(
      baseUrl: baseUrl,
      apiKey: apiKey,
      body: {
        'model': model,
        'stream': false,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '这是一个视频输入能力探针。请只回复 OK。'},
              {
                'type': 'video_url',
                'video_url': {'url': _tinyVideoDataUrl},
              },
            ],
          },
        ],
        'max_tokens': 16,
      },
      successMessage: '模型接受 video_url 多模态输入。',
      validate: (data) => _hasAssistantOutput(data),
      failureMessage: '请求成功但没有视频回复。',
    );
  }

  Future<AiCapabilityProbe> _probeTools({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    return _probe(
      baseUrl: baseUrl,
      apiKey: apiKey,
      body: {
        'model': model,
        'stream': false,
        'messages': [
          {'role': 'user', 'content': '请调用 capability_probe 工具，不要输出普通文本。'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'capability_probe',
              'description': '用于检测模型是否支持 OpenAI function calling。模型支持时可以调用，不支持时可直接回复 OK。',
              'parameters': {
                'type': 'object',
                'properties': {},
                'required': [],
              },
            },
          },
        ],
        'max_tokens': 16,
      },
      successMessage: '模型返回了 tool_calls。',
      validate: _hasToolCall,
      failureMessage: '没有返回 tool_calls。',
    );
  }

  Future<AiCapabilityProbe> _probe({
    required String baseUrl,
    required String apiKey,
    required Map<String, dynamic> body,
    required bool Function(dynamic data) validate,
    required String successMessage,
    required String failureMessage,
  }) async {
    try {
      final uri = AskAiRepository.composeChatCompletionsUri(baseUrl);
      final isLocal = baseUrl.contains('127.0.0.1:11434') || baseUrl.contains('localhost:11434');
      final trimmedKey = apiKey.trim();
      final auth = trimmedKey.startsWith('Bearer ') ? trimmedKey : 'Bearer $trimmedKey';
      final response = await _dio.postUri<dynamic>(
        uri,
        data: jsonEncode(body),
        options: Options(
          headers: {
            Headers.contentTypeHeader: Headers.jsonContentType,
            if (!isLocal || trimmedKey.isNotEmpty) 'Authorization': auth,
          },
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 40),
        ),
      );
      final data = _decodeResponseData(response.data);
      final ok = validate(data);
      return AiCapabilityProbe(
        supported: ok,
        message: ok ? successMessage : failureMessage,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final message = [
        if (status != null) 'HTTP $status',
        if (data != null) _short(data.toString()) else e.message ?? '请求失败',
      ].join('：');
      return AiCapabilityProbe(supported: false, message: message);
    } catch (e) {
      return AiCapabilityProbe(supported: false, message: _short(e.toString()));
    }
  }

  dynamic _decodeResponseData(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  bool _hasAssistantOutput(dynamic data) {
    final choices = _choices(data);
    if (choices.isEmpty) return false;
    for (final choice in choices) {
      final message = choice['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) return true;
        if (content is List && content.isNotEmpty) return true;
        final reasoning = message['reasoning_content'];
        if (reasoning is String && reasoning.trim().isNotEmpty) return true;
        final toolCalls = message['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) return true;
      }
      final text = choice['text'];
      if (text is String && text.trim().isNotEmpty) return true;
    }
    return false;
  }

  bool _hasToolCall(dynamic data) {
    final choices = _choices(data);
    for (final choice in choices) {
      if (choice['finish_reason'] == 'tool_calls') return true;
      final message = choice['message'];
      if (message is Map) {
        final toolCalls = message['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _choices(dynamic data) {
    final raw = data is Map ? data['choices'] : null;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _short(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 180) return compact;
    return '${compact.substring(0, 180)}...';
  }
}

const _onePixelPngDataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

const _tinyVideoDataUrl =
    'data:video/mp4;base64,AAAAIGZ0eXBpc29tAAACAGlzb21pc28ybXA0MQAAAAhmcmVlAAAAGG1kYXQ=';
