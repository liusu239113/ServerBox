/// Surlor AI 内置模型注册表
///
/// 包含适合手机端运行的轻量级开源大语言模型，
/// 提供多个下载源（含国内镜像）以确保国内用户可正常下载。
library;

import 'package:flutter/material.dart';

/// 单个模型的元数据
@immutable
class AiModelEntry {
  const AiModelEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.size,
    required this.sizeBytes,
    required this.quantization,
    required this.parameterCount,
    required this.contextLength,
    required this.languages,
    required this.useCases,
    required this.downloadSources,
    required this.ollamaName,
    this.defaultApiModelName,
    this.tags = const [],
  });

  /// 唯一标识
  final String id;

  /// 显示名称
  final String name;

  /// 简短描述（中文）
  final String description;

  /// 人类可读的大小（如 "1.2 GB"）
  final String size;

  /// 文件大小（字节）
  final int sizeBytes;

  /// 量化方式（如 Q4_K_M, Q5_K_M, FP16）
  final String quantization;

  /// 参数量（如 "1.7B", "4B", "7B"）
  final String parameterCount;

  /// 上下文长度
  final int contextLength;

  /// 支持的语言
  final List<String> languages;

  /// 适用场景
  final List<String> useCases;

  /// 下载源列表（主源 + 镜像源）
  final List<ModelDownloadSource> downloadSources;

  /// Ollama 模型名（用于 ollama pull/run）
  final String ollamaName;

  /// 默认 API 调用时的模型名（可能和 ollama 名不同）
  final String? defaultApiModelName;

  /// 标签
  final List<String> tags;
}

/// 单个下载源
@immutable
class ModelDownloadSource {
  const ModelDownloadSource({
    required this.name,
    required this.url,
    this.note,
  });

  /// 来源名称（如 "HuggingFace 主站"、"HuggingFace 镜像"）
  final String name;

  /// 下载 URL
  final String url;

  /// 备注（如 "推荐国内用户使用"）
  final String? note;
}

/// API 服务商预设模板
@immutable
class ApiProviderPreset {
  const ApiProviderPreset({
    required this.id,
    required this.name,
    required this.icon,
    required this.baseUrl,
    required this.models,
    required this.docUrl,
    this.apiKeyHint,
    this.note,
  });

  final String id;
  final String name;
  final IconData icon;
  final String baseUrl;
  final List<String> models;
  final String docUrl;
  final String? apiKeyHint;
  final String? note;
}

// ──────────────────── 内置模型列表 ────────────────────

/// 所有内置的本地模型
const List<AiModelEntry> builtinModels = [
  // ===== Qwen3 系列（阿里通义，中文能力最强）=====
  AiModelEntry(
    id: 'qwen3-1.7b-q4',
    name: 'Qwen3 1.7B',
    description: '超轻量，响应最快，适合简单问答和命令生成。中文能力优秀。',
    size: '~1.2 GB',
    sizeBytes: 1200000000,
    quantization: 'Q4_K_M',
    parameterCount: '1.7B',
    contextLength: 32768,
    languages: ['中文', '英文', '代码'],
    useCases: ['快速问答', '命令建议', '文本摘要'],
    tags: ['推荐', '最轻', '中文强'],
    ollamaName: 'qwen3:1.7b',
    defaultApiModelName: 'qwen3:1.7b',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull qwen3:1.7b',
        note: '需安装 Ollama，自动下载',
      ),
      ModelDownloadSource(
        name: 'ModelScope 镜像',
        url: 'https://www.modelscope.cn/models/Qwen/Qwen3-1.7B-GGUF/files',
        note: '国内高速下载',
      ),
      ModelDownloadSource(
        name: 'HuggingFace',
        url: 'https://huggingface.co/Qwen/Qwen3-1.7B-GGUF',
        note: '国际源，速度取决于网络',
      ),
    ],
  ),

  AiModelEntry(
    id: 'qwen3-4b-q4',
    name: 'Qwen3 4B',
    description: '平衡之选，推理能力和速度兼顾。适合大多数服务器管理场景。',
    size: '~2.4 GB',
    sizeBytes: 2400000000,
    quantization: 'Q4_K_M',
    parameterCount: '4B',
    contextLength: 32768,
    languages: ['中文', '英文', '代码', '多语言'],
    useCases: ['服务器运维', '日志分析', '脚本编写', '问题排查'],
    tags: ['推荐', '平衡'],
    ollamaName: 'qwen3:4b',
    defaultApiModelName: 'qwen3:4b',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull qwen3:4b',
        note: '需安装 Ollama，自动下载',
      ),
      ModelDownloadSource(
        name: 'ModelScope 镜像',
        url: 'https://www.modelscope.cn/models/Qwen/Qwen3-4B-GGUF/files',
        note: '国内高速下载',
      ),
      ModelDownloadSource(
        name: 'HuggingFace',
        url: 'https://huggingface.co/Qwen/Qwen3-4B-GGUF',
      ),
    ],
  ),

  // ===== DeepSeek R1 系列（推理能力强）=====
  AiModelEntry(
    id: 'deepseek-r1-7b-q4',
    name: 'DeepSeek R1 7B',
    description: '推理能力强，擅长复杂问题分析和多步骤任务拆解。',
    size: '~4.8 GB',
    sizeBytes: 4800000000,
    quantization: 'Q4_K_M',
    parameterCount: '7B',
    contextLength: 65536,
    languages: ['中文', '英文', '代码'],
    useCases: ['复杂故障排查', '架构设计', '深度分析'],
    tags: ['推理强'],
    ollamaName: 'deepseek-r1:7b',
    defaultApiModelName: 'deepseek-r1:7b',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull deepseek-r1:7b',
        note: '需安装 Ollama',
      ),
      ModelDownloadSource(
        name: 'ModelScope 镜像',
        url: 'https://www.modelscope.cn/models/deepseek-ai/DeepSeek-R1-Distill-Qwen-7B-GGUF/files',
        note: '国内高速',
      ),
      ModelDownloadSource(
        name: 'HuggingFace',
        url: 'https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-7B-GGUF',
      ),
    ],
  ),

  // ===== Llama 系列（Meta 开源）=====
  AiModelEntry(
    id: 'llama3.2-3b-q4',
    name: 'Llama 3.2 3B',
    description: 'Meta 出品，通用性强，多语言支持好。',
    size: '~1.9 GB',
    sizeBytes: 1900000000,
    quantization: 'Q4_K_M',
    parameterCount: '3B',
    contextLength: 131072,
    languages: ['英文', '多语言', '代码'],
    useCases: ['通用对话', '多语言翻译', '代码辅助'],
    tags: ['通用', '多语言'],
    ollamaName: 'llama3.2:3b',
    defaultApiModelName: 'llama3.2:3b',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull llama3.2:3b',
      ),
      ModelDownloadSource(
        name: 'ModelScope 镜像',
        url: 'https://www.modelscope.cn/models/meta-llama/Llama-3.2-3B-Instruct-GGUF/files',
        note: '国内高速',
      ),
    ],
  ),

  // ===== Phi 系列（微软出品，超轻量）=====
  AiModelEntry(
    id: 'phi3-mini-q4',
    name: 'Phi-3 Mini',
    description: '微软出品，极轻量但能力不俗，特别适合移动设备。',
    size: '~2.2 GB',
    sizeBytes: 2200000000,
    quantization: 'Q4_K_M',
    parameterCount: '3.8B',
    contextLength: 128000,
    languages: ['英文', '代码', '中文(基础)'],
    useCases: ['代码生成', '快速问答', '边缘部署'],
    tags: ['轻量', '代码强'],
    ollamaName: 'phi3:mini',
    defaultApiModelName: 'phi3:mini',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull phi3:mini',
      ),
      ModelDownloadSource(
        name: 'HuggingFace',
        url: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf',
      ),
    ],
  ),

  // ===== Gemma 系列（Google 出品）=====
  AiModelEntry(
    id: 'gemma2-2b-q4',
    name: 'Gemma 2 2B',
    description: 'Google 出品的小型高效模型，速度快且质量稳定。',
    size: '~1.4 GB',
    sizeBytes: 1400000000,
    quantization: 'Q4_K_M',
    parameterCount: '2B',
    contextLength: 8192,
    languages: ['英文', '代码', '中文(基础)'],
    useCases: ['快速问答', '分类任务', '轻量助手'],
    tags: ['轻量', '稳定'],
    ollamaName: 'gemma2:2b',
    defaultApiModelName: 'gemma2:2b',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull gemma2:2b',
      ),
      ModelDownloadSource(
        name: 'HuggingFace',
        url: 'https://huggingface.co/google/gemma-2-2b-it-GGUF',
      ),
    ],
  ),

  // ===== Qwen3 更大版本 =====
  AiModelEntry(
    id: 'qwen3-8b-q4',
    name: 'Qwen3 8B',
    description: '更强的中文理解能力，适合需要高质量回答的场景。',
    size: '~4.9 GB',
    sizeBytes: 4900000000,
    quantization: 'Q4_K_M',
    parameterCount: '8B',
    contextLength: 32768,
    languages: ['中文', '英文', '代码', '多语言'],
    useCases: ['深度分析', '长文写作', '复杂数据处理'],
    tags: ['高质量'],
    ollamaName: 'qwen3:8b',
    defaultApiModelName: 'qwen3:8b',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull qwen3:8b',
      ),
      ModelDownloadSource(
        name: 'ModelScope 镜像',
        url: 'https://www.modelscope.cn/models/Qwen/Qwen3-8B-GGUF/files',
        note: '国内高速',
      ),
      ModelDownloadSource(
        name: 'HuggingFace',
        url: 'https://huggingface.co/Qwen/Qwen3-8B-GGUF',
      ),
    ],
  ),

  // ===== Yi 系列（零一万物，中文优化）=====
  AiModelEntry(
    id: 'yi-1.5-9b-q4',
    name: 'Yi 1.5 9B',
    description: '零一万物出品，专为中文优化的开源模型。',
    size: '~5.6 GB',
    sizeBytes: 5600000000,
    quantization: 'Q4_K_M',
    parameterCount: '9B',
    contextLength: 16384,
    languages: ['中文', '英文', '代码'],
    useCases: ['中文对话', '内容创作', '知识问答'],
    tags: ['中文优化'],
    ollamaName: 'yi:1.5-9b',
    defaultApiModelName: 'yi:1.5-9b-chat',
    downloadSources: [
      ModelDownloadSource(
        name: 'Ollama 官方 (推荐)',
        url: 'ollama pull yi:1.5-9b',
      ),
      ModelDownloadSource(
        name: 'HuggingFace',
        url: 'https://huggingface.co/zero-one-ai/Yi-1.5-9B-Chat-GGUF',
      ),
    ],
  ),
];

// ──────────────────── API 服务商预设 ────────────────────

/// 预配置的 API 服务商列表
/// 用户选择后自动填充 baseUrl 和可选的模型列表
const List<ApiProviderPreset> apiPresets = [
  // ===== 国内服务商 =====

  ApiProviderPreset(
    id: 'deepseek_api',
    name: 'DeepSeek',
    icon: Icons.psychology,
    baseUrl: 'https://api.deepseek.com/v1',
    models: [
      'deepseek-chat',
      'deepseek-reasoner',
    ],
    docUrl: 'https://platform.deepseek.com/api-docs',
    apiKeyHint: 'sk-...',
    note: '性价比高，中文能力强，推荐国内用户首选',
  ),

  ApiProviderPreset(
    id: 'qwen_api',
    name: '通义千问',
    icon: Icons.cloud_queue,
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: [
      'qwen-turbo',
      'qwen-plus',
      'qwen-max',
      'qwen-coder-plus',
      'qwen-vl-max-latest',
    ],
    docUrl: 'https://help.aliyun.com/zh/model-studio/getting-started',
    apiKeyHint: 'sk-...',
    note: '阿里云出品，中文能力强，支持视觉模型',
  ),

  ApiProviderPreset(
    id: 'zhipu_api',
    name: '智谱 GLM',
    icon: Icons.auto_awesome,
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: [
      'glm-4-flash',
      'glm-4-air',
      'glm-4-plus',
      'glm-4-long',
      'glm-4v-flash',
    ],
    docUrl: 'https://open.bigmodel.cn/dev/api',
    apiKeyHint: '...',
    note: '免费额度充足，GLM-4-flash 免费可用',
  ),

  ApiProviderPreset(
    id: 'moonshot_api',
    name: 'Moonshot (Kimi)',
    icon: Icons.nightlight_round,
    baseUrl: 'https://api.moonshot.cn/v1',
    models: [
      'moonshot-v1-8k',
      'moonshot-v1-32k',
      'moonshot-v1-128k',
    ],
    docUrl: 'https://platform.moonshot.cn/docs/api',
    apiKeyHint: 'sk-...',
    note: '长上下文能力强，适合处理大量日志',
  ),

  ApiProviderPreset(
    id: 'baichuan_api',
    name: '百川智能',
    icon: Icons.waves,
    baseUrl: 'https://api.baichuan-ai.com/v1',
    models: [
      'Baichuan2-Turbo',
      'Baichuan2-53B',
      'Baichuan-NPC-Turbo',
      'Baichuan-Text-Turbo',
    ],
    docUrl: 'https://platform.baichuan-ai.com/docs',
    apiKeyHint: 'sk-...',
    note: '角色扮演能力强',
  ),


  // ===== 国际服务商 =====

  ApiProviderPreset(
    id: 'openai_api',
    name: 'OpenAI',
    icon: Icons.smart_toy,
    baseUrl: 'https://api.openai.com/v1',
    models: [
      'gpt-4o-mini',
      'gpt-4o',
      'gpt-4-turbo',
      'o1-mini',
      'o3-mini',
    ],
    docUrl: 'https://platform.openai.com/docs/api-reference',
    apiKeyHint: 'sk-...',
    note: '业界标杆，价格较高',
  ),

  ApiProviderPreset(
    id: 'anthropic_api',
    name: 'Anthropic Claude',
    icon: Icons.fingerprint,
    baseUrl: 'https://api.anthropic.com/v1',
    models: [
      'claude-sonnet-4-20250514',
      'claude-haiku-4-20250514',
      'claude-opus-4-20250514',
    ],
    docUrl: 'https://docs.anthropic.com/en/docs/about-claude/models',
    apiKeyHint: 'sk-ant-...',
    note: '长文本和编程能力强，注意：非标准 OpenAI 格式',
  ),

  ApiProviderPreset(
    id: 'google_ai',
    name: 'Google Gemini',
    icon: Icons.auto_awesome,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
    models: [
      'gemini-2.0-flash',
      'gemini-2.0-pro',
      'gemini-1.5-pro',
      'gemini-1.5-flash',
    ],
    docUrl: 'https://ai.google.dev/gemini-api/docs',
    apiKeyHint: 'AIza...',
    note: '多模态能力强，Flash 版本免费',
  ),

  // ===== 本地 / 自建服务 =====

  ApiProviderPreset(
    id: 'ollama_local',
    name: 'Ollama 本地',
    icon: Icons.dns,
    baseUrl: 'http://127.0.0.1:11434/v1',
    models: [], // 动态获取已安装的模型
    docUrl: 'https://ollama.com',
    note: '本地运行，隐私安全，无需 API Key。需先安装 Ollama。',
  ),

  ApiProviderPreset(
    id: 'vllm_local',
    name: 'vLLM / 自建服务',
    icon: Icons.router,
    baseUrl: 'http://192.168.1.100:8000/v1',
    models: [],
    docUrl: 'https://github.com/vllm-project/vllm',
    note: '自建的 vLLM / TGI / llama.cpp 兼容服务',
  ),

  ApiProviderPreset(
    id: 'custom',
    name: '自定义地址',
    icon: Icons.edit,
    baseUrl: '',
    models: [],
    docUrl: '',
    note: '手动输入任意兼容 OpenAI 格式的 API 地址',
  ),
];

/// 根据模型 ID 查找模型信息
AiModelEntry? findModelById(String id) {
  for (final model in builtinModels) {
    if (model.id == id) return model;
  }
  return null;
}

/// 根据 preset ID 查找预设
ApiProviderPreset? findPresetById(String id) {
  for (final preset in apiPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// 获取推荐模型（标记为 "推荐" 的模型）
List<AiModelEntry> get recommendedModels =>
    builtinModels.where((m) => m.tags.contains('推荐')).toList();

/// 获取轻量模型（小于 2GB）
List<AiModelEntry> get lightweightModels =>
    builtinModels.where((m) => m.sizeBytes < 2000000000).toList();
