/// Surlor AI 对话页面
///
/// 用户通过自然语言与 AI Agent 交互，Agent 可以执行服务器操作（需用户确认）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surlor_ai/data/helper/gen_ssh.dart';
import 'package:surlor_ai/data/provider/ai/agent_service.dart';
import 'package:surlor_ai/data/provider/ai/mcp_runtime_service.dart';
import 'package:surlor_ai/data/provider/ai/ollama_service.dart';
import 'package:surlor_ai/data/provider/server/all.dart';
import 'package:surlor_ai/data/res/store.dart';

@immutable
class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
    this.toolLogs,
    this.timestamp,
    this.isError = false,
    this.isStreaming = false,
  });

  factory _ChatMessage.fromJson(Map<String, dynamic> json) {
    return _ChatMessage(
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      toolLogs: (json['toolLogs'] as List?)?.map((e) => '$e').toList(),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      isError: json['isError'] == true,
    );
  }

  final String role;
  final String content;
  final List<String>? toolLogs;
  final DateTime? timestamp;
  final bool isError;
  final bool isStreaming;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      if (toolLogs != null && toolLogs!.isNotEmpty) 'toolLogs': toolLogs,
      if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      if (isError) 'isError': true,
    };
  }
}

@immutable
class _AiProfile {
  const _AiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.supportText = true,
    this.supportImage = false,
    this.supportVideo = false,
    this.supportTools = true,
  });

  factory _AiProfile.fromJson(Map<String, dynamic> json) {
    return _AiProfile(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? '未命名配置',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      supportText: json['supportText'] != false,
      supportImage: json['supportImage'] == true,
      supportVideo: json['supportVideo'] == true,
      supportTools: json['supportTools'] != false,
    );
  }

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool supportText;
  final bool supportImage;
  final bool supportVideo;
  final bool supportTools;

  bool get isLocal => baseUrl.contains('127.0.0.1:11434') || baseUrl.contains('localhost:11434');

  _AiProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? supportText,
    bool? supportImage,
    bool? supportVideo,
    bool? supportTools,
  }) {
    return _AiProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      supportText: supportText ?? this.supportText,
      supportImage: supportImage ?? this.supportImage,
      supportVideo: supportVideo ?? this.supportVideo,
      supportTools: supportTools ?? this.supportTools,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'supportText': supportText,
      'supportImage': supportImage,
      'supportVideo': supportVideo,
      'supportTools': supportTools,
    };
  }
}

@immutable
class _AgentConfig {
  const _AgentConfig({
    required this.id,
    required this.name,
    required this.prompt,
    this.enabled = true,
  });

  factory _AgentConfig.fromJson(Map<String, dynamic> json) {
    return _AgentConfig(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? '默认智能体',
      prompt: json['prompt'] as String? ?? '',
      enabled: json['enabled'] != false,
    );
  }

  final String id;
  final String name;
  final String prompt;
  final bool enabled;

  _AgentConfig copyWith({String? id, String? name, String? prompt, bool? enabled}) {
    return _AgentConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'enabled': enabled,
      };
}

@immutable
class _SkillConfig {
  const _SkillConfig({
    required this.id,
    required this.name,
    required this.prompt,
    this.enabled = true,
  });

  factory _SkillConfig.fromJson(Map<String, dynamic> json) {
    return _SkillConfig(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? '未命名技能',
      prompt: json['prompt'] as String? ?? '',
      enabled: json['enabled'] != false,
    );
  }

  final String id;
  final String name;
  final String prompt;
  final bool enabled;

  _SkillConfig copyWith({String? id, String? name, String? prompt, bool? enabled}) {
    return _SkillConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'enabled': enabled,
      };
}

@immutable
class _McpConfig {
  const _McpConfig({
    required this.id,
    required this.name,
    required this.command,
    required this.args,
    this.enabled = true,
  });

  factory _McpConfig.fromJson(Map<String, dynamic> json) {
    return _McpConfig(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'MCP Server',
      command: json['command'] as String? ?? '',
      args: json['args'] as String? ?? '',
      enabled: json['enabled'] != false,
    );
  }

  final String id;
  final String name;
  final String command;
  final String args;
  final bool enabled;

  _McpConfig copyWith({
    String? id,
    String? name,
    String? command,
    String? args,
    bool? enabled,
  }) {
    return _McpConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      args: args ?? this.args,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'args': args,
        'enabled': enabled,
      };
}

@immutable
class _ConversationRecord {
  const _ConversationRecord({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  factory _ConversationRecord.fromJson(Map<String, dynamic> json) {
    final messages = <_ChatMessage>[];
    final rawMessages = json['messages'];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          messages.add(_ChatMessage.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return _ConversationRecord(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '未命名会话',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      messages: messages,
    );
  }

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<_ChatMessage> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };
}

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  static const route = AppRouteNoArg(page: AiChatPage.new, path: '/ai-chat');

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage>
    with AutomaticKeepAliveClientMixin {
  static const _terminalOrange = Color(0xFFFF8C00);
  static const _terminalBg = Color(0xFF12100C);
  static const _terminalPanel = Color(0xFF1B160F);
  static const _terminalLine = Color(0xFFFFA726);

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _agentService = AgentService();
  final _ollamaService = OllamaService();

  List<_ChatMessage> _messages = [];
  List<_AiProfile> _profiles = [];
  List<_AgentConfig> _agents = [];
  List<_SkillConfig> _skills = [];
  List<_McpConfig> _mcpServers = [];
  List<McpServerStatus> _mcpStatuses = [];
  StreamSubscription<List<McpServerStatus>>? _mcpStatusSub;
  List<String> _localModels = [];
  bool _isLoading = false;
  bool _localRuntimeAvailable = false;
  String? _currentProfileId;
  String? _currentServerId;
  String? _currentAgentId;
  String? _currentConversationId;
  String _workspacePath = '';
  String _attachmentContext = '';
  String? _attachmentName;
  List<String> _attachmentImageDataUrls = [];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _workspacePath = Stores.setting.askAiWorkspacePath.fetch();
    _loadAgentCenter();
    _mcpStatusSub = McpRuntimeService.instance.statuses.listen((statuses) {
      if (!mounted) return;
      setState(() => _mcpStatuses = statuses);
    });
    _loadHistory();
    unawaited(_loadLocalModels());
  }

  @override
  void dispose() {
    _mcpStatusSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  _AiProfile? get _currentProfile {
    if (_profiles.isEmpty) return null;
    return _profiles.firstWhereOrNull((p) => p.id == _currentProfileId) ?? _profiles.first;
  }

  _AgentConfig? get _currentAgent {
    if (_agents.isEmpty) return null;
    return _agents.firstWhereOrNull((a) => a.id == _currentAgentId) ?? _agents.first;
  }

  List<T> _decodeList<T>(String raw, T Function(Map<String, dynamic>) convert) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((e) => convert(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  void _loadProfiles() {
    final raw = Stores.setting.askAiProfiles.fetch();
    final profiles = <_AiProfile>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            profiles.add(_AiProfile.fromJson(item));
          } else if (item is Map) {
            profiles.add(_AiProfile.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (_) {}

    if (profiles.isEmpty) {
      profiles.add(_AiProfile(
        id: 'default',
        name: 'DeepSeek',
        baseUrl: Stores.setting.askAiBaseUrl.fetch(),
        apiKey: Stores.setting.askAiApiKey.fetch(),
        model: Stores.setting.askAiModel.fetch(),
        supportText: Stores.setting.askAiSupportText.fetch(),
        supportImage: Stores.setting.askAiSupportImage.fetch(),
        supportVideo: Stores.setting.askAiSupportVideo.fetch(),
        supportTools: Stores.setting.askAiSupportTools.fetch(),
      ));
    }

    _profiles = profiles;
    final savedId = Stores.setting.askAiCurrentProfileId.fetch();
    _currentProfileId = profiles.any((p) => p.id == savedId) ? savedId : profiles.first.id;
    _persistProfiles();
  }

  void _persistProfiles() {
    Stores.setting.askAiProfiles.put(jsonEncode(_profiles.map((p) => p.toJson()).toList()));
    final profile = _currentProfile;
    if (profile == null) return;
    Stores.setting.askAiCurrentProfileId.put(profile.id);
    Stores.setting.askAiBaseUrl.put(profile.baseUrl);
    Stores.setting.askAiApiKey.put(profile.apiKey);
    Stores.setting.askAiModel.put(profile.model);
    Stores.setting.askAiSupportText.put(profile.supportText);
    Stores.setting.askAiSupportImage.put(profile.supportImage);
    Stores.setting.askAiSupportVideo.put(profile.supportVideo);
    Stores.setting.askAiSupportTools.put(profile.supportTools);
  }

  void _loadAgentCenter() {
    _agents = _decodeList(Stores.setting.askAiAgents.fetch(), _AgentConfig.fromJson);
    if (_agents.isEmpty) {
      _agents = const [
        _AgentConfig(
          id: 'default',
          name: '默认运维 Agent',
          prompt: '你是移动端服务器与本地文件自动化助手，优先保证安全，执行前解释风险。',
        ),
      ];
    }
    _skills = _decodeList(Stores.setting.askAiSkills.fetch(), _SkillConfig.fromJson);
    if (_skills.isEmpty) {
      _skills = const [
        _SkillConfig(
          id: 'server-diagnose',
          name: '服务器诊断',
          prompt: '当用户要求诊断服务器时，先检查负载、内存、磁盘、关键进程和最近日志，再给出结论。',
        ),
        _SkillConfig(
          id: 'safe-file-edit',
          name: '安全改文件',
          prompt: '改文件前先读取原内容，说明改动点；写入或删除前必须确认。',
        ),
        _SkillConfig(
          id: 'ops-panel',
          name: '专业运维面板',
          prompt: '当用户询问防火墙、端口、网络、目录占用、Docker、systemd、内网穿透时，优先使用对应只读工具 firewall_status、port_list、network_status、disk_usage、docker_status、service_status、tunnel_status。',
        ),
      ];
    }
    _mcpServers = _decodeList(Stores.setting.askAiMcpServers.fetch(), _McpConfig.fromJson);
    if (_mcpServers.isEmpty) {
      _mcpServers = [
        _McpConfig(
          id: 'builtin-filesystem',
          name: '手机项目文件系统',
          command: 'builtin-filesystem',
          args: _workspacePath.isEmpty ? '<workspace>' : _workspacePath,
        ),
      ];
    }
    final savedAgent = Stores.setting.askAiCurrentAgentId.fetch();
    _currentAgentId = _agents.any((a) => a.id == savedAgent) ? savedAgent : _agents.first.id;
    _persistAgentCenter();
  }

  void _persistAgentCenter() {
    Stores.setting.askAiAgents.put(jsonEncode(_agents.map((a) => a.toJson()).toList()));
    Stores.setting.askAiSkills.put(jsonEncode(_skills.map((s) => s.toJson()).toList()));
    Stores.setting.askAiMcpServers.put(jsonEncode(_mcpServers.map((m) => m.toJson()).toList()));
    if (_currentAgentId != null) Stores.setting.askAiCurrentAgentId.put(_currentAgentId!);
    unawaited(_syncMcpRuntime());
  }

  Future<void> _syncMcpRuntime() async {
    await McpRuntimeService.instance.sync(
      _mcpServers.map((m) {
        final args = m.command == 'builtin-filesystem' && m.args == '<workspace>' && _workspacePath.isNotEmpty
            ? _workspacePath
            : m.args;
        return McpServerRuntimeConfig(
          id: m.id,
          name: m.name,
          command: m.command,
          args: args,
          enabled: m.enabled,
        );
      }).toList(),
    );
    if (!mounted) return;
    setState(() => _mcpStatuses = McpRuntimeService.instance.snapshot());
  }

  String _buildAgentCenterContext() {
    final buf = StringBuffer();
    final agent = _currentAgent;
    if (agent != null && agent.prompt.trim().isNotEmpty) {
      buf.writeln('当前智能体：${agent.name}');
      buf.writeln(agent.prompt.trim());
    }
    final enabledSkills = _skills.where((s) => s.enabled && s.prompt.trim().isNotEmpty).toList();
    if (enabledSkills.isNotEmpty) {
      buf.writeln('\n已启用技能：');
      for (final skill in enabledSkills) {
        buf.writeln('- ${skill.name}: ${skill.prompt.trim()}');
      }
    }
    final enabledMcp = _mcpServers.where((m) => m.enabled).toList();
    if (enabledMcp.isNotEmpty) {
      buf.writeln('\nMCP 运行时已启用，Agent 可以真实调用 MCP tools：');
      for (final mcp in enabledMcp) {
        final status = _mcpStatuses.firstWhereOrNull((s) => s.id == mcp.id);
        final state = status == null ? '同步中' : (status.running ? '运行中' : '未运行：${status.message}');
        buf.writeln('- ${mcp.name}: ${mcp.command} ${mcp.args} [$state]'.trim());
      }
    }
    return buf.toString().trim();
  }

  void _loadHistory() {
    try {
      final decoded = jsonDecode(Stores.setting.askAiChatHistory.fetch());
      if (decoded is List) {
        _messages = decoded
            .whereType<Map>()
            .map((e) => _ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => !e.isStreaming)
            .toList();
      }
    } catch (_) {
      _messages = [];
    }

    if (_messages.isEmpty) {
      _messages = [
        _ChatMessage(
          role: 'assistant',
          content: 'Surlor AI Agent 已就绪。\n\n'
              '先在下方选择目标服务器和模型，然后直接说：\n'
              '- 查看这台服务器状态\n'
              '- 帮我找 nginx 配置文件\n'
              '- 读取 /var/log/syslog 最近 100 行\n'
              '- 修改某个配置文件并说明风险\n'
              '- 选择本地项目目录后，让我创建、读取、修改手机本地项目文件\n\n'
              '需要参考资料时，可以点左下角附件按钮上传文本文件或图片。',
        ),
      ];
      _persistHistory();
    }
  }

  void _persistHistory({bool saveSnapshot = true}) {
    final saved = _messages
        .where((m) => !m.isStreaming)
        .take(80)
        .map((m) => m.toJson())
        .toList();
    Stores.setting.askAiChatHistory.put(jsonEncode(saved));
    if (saveSnapshot) _saveConversationSnapshot(saved);
  }

  void _saveConversationSnapshot(List<Map<String, dynamic>> savedMessages) {
    final messages = savedMessages.map(_ChatMessage.fromJson).toList();
    if (messages.isEmpty) return;
    _currentConversationId ??= DateTime.now().microsecondsSinceEpoch.toString();
    final title = _conversationTitle(messages);
    final conversations = _decodeList(
      Stores.setting.askAiConversations.fetch(),
      _ConversationRecord.fromJson,
    );
    conversations.removeWhere((c) => c.id == _currentConversationId);
    conversations.insert(
      0,
      _ConversationRecord(
        id: _currentConversationId!,
        title: title,
        updatedAt: DateTime.now(),
        messages: messages,
      ),
    );
    final trimmed = conversations.take(30).map((c) => c.toJson()).toList();
    Stores.setting.askAiConversations.put(jsonEncode(trimmed));
  }

  String _conversationTitle(List<_ChatMessage> messages) {
    final msg = messages.firstWhereOrNull((m) => m.role == 'user' && m.content.trim().isNotEmpty);
    final text = (msg?.content.trim().isNotEmpty == true ? msg!.content : messages.first.content).trim();
    if (text.length <= 24) return text.isEmpty ? '新会话' : text;
    return '${text.substring(0, 24)}...';
  }

  Future<void> _openConversationHistory() async {
    final conversations = _decodeList(
      Stores.setting.askAiConversations.fetch(),
      _ConversationRecord.fromJson,
    );
    final keywordCtrl = TextEditingController();
    var filtered = conversations;
    final selected = await showDialog<_ConversationRecord>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          return AlertDialog(
            title: const Text('历史会话'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: keywordCtrl,
                    decoration: const InputDecoration(
                      labelText: '搜索会话',
                      border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                    ),
                    onChanged: (value) {
                      final kw = value.trim().toLowerCase();
                      setDialogState(() {
                        filtered = kw.isEmpty
                            ? conversations
                            : conversations.where((item) {
                                final haystack = [
                                  item.title,
                                  ...item.messages.map((m) => m.content),
                                ].join('\n').toLowerCase();
                                return haystack.contains(kw);
                              }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 360,
                    child: filtered.isEmpty
                        ? const Center(child: Text('没有匹配的会话'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, index) {
                              final item = filtered[index];
                              return ListTile(
                                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(item.updatedAt.toString(), maxLines: 1),
                                onTap: () => Navigator.pop(c, item),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
            ],
          );
        },
      ),
    );
    keywordCtrl.dispose();
    if (selected == null) return;
    setState(() {
      _currentConversationId = selected.id;
      _messages = selected.messages;
    });
    _persistHistory(saveSnapshot: false);
    _scrollToBottom();
  }

  Future<void> _loadLocalModels() async {
    try {
      final available = await _ollamaService.isAvailable();
      final models = available ? await _ollamaService.listModels() : <OllamaModel>[];
      if (!mounted) return;
      setState(() {
        _localRuntimeAvailable = available;
        _localModels = models.map((m) => m.name).where((m) => m.isNotEmpty).toList();
      });
      _mergeLocalProfiles();
    } catch (_) {
      if (!mounted) return;
      setState(() => _localRuntimeAvailable = false);
    }
  }

  void _mergeLocalProfiles() {
    var changed = false;
    for (final model in _localModels) {
      final exists = _profiles.any((p) => p.isLocal && p.model == model);
      if (!exists) {
        _profiles.add(_AiProfile(
          id: 'ollama-${model.hashCode}',
          name: '本地 $model',
          baseUrl: 'http://127.0.0.1:11434/v1',
          apiKey: 'ollama',
          model: model,
        ));
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
      _persistProfiles();
    }
  }

  void _syncServerSelection(List<Spi> servers) {
    if (servers.isEmpty) {
      _currentServerId = null;
      return;
    }
    final saved = Stores.setting.askAiDefaultServerId.fetch();
    final candidate = _currentServerId ?? (saved.isNotEmpty ? saved : null);
    if (candidate != null && servers.any((s) => s.id == candidate)) {
      _currentServerId = candidate;
      return;
    }
    _currentServerId = servers.first.id;
    Stores.setting.askAiDefaultServerId.put(_currentServerId!);
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    final servers = _orderedServers();
    _syncServerSelection(servers);
    final spi = _selectedServer(servers);
    final profile = _currentProfile;

    if (profile == null || profile.baseUrl.trim().isEmpty || profile.model.trim().isEmpty) {
      _showSnack('请先配置可用的 AI 模型。');
      return;
    }
    if (profile.apiKey.trim().isEmpty && !profile.isLocal) {
      _showSnack('当前模型缺少 API Key。');
      return;
    }
    if (!profile.supportText) {
      _showSnack('当前模型未启用文本能力，请在 AI 配置中勾选并测试。');
      return;
    }
    if (_attachmentImageDataUrls.isNotEmpty && !profile.supportImage) {
      _showSnack('当前模型未启用图片能力，请更换视觉模型或在配置测试通过后勾选图片。');
      return;
    }

    final history = _messages
        .where((m) => !m.isStreaming && (m.role == 'user' || m.role == 'assistant'))
        .take(30)
        .map((m) => AgentConversationMessage(role: m.role, content: m.content))
        .toList();

    setState(() {
      _messages.add(_ChatMessage(
        role: 'user',
        content: trimmed,
        timestamp: DateTime.now(),
      ));
      _messages.add(_ChatMessage(
        role: 'assistant',
        content: '',
        timestamp: DateTime.now(),
        isStreaming: true,
      ));
      _isLoading = true;
    });
    _textController.clear();
    _persistHistory();
    _scrollToBottom();

    try {
      await _runAgent(trimmed, profile, spi, servers, history);
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isStreaming) _messages.removeLast();
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: '出错：$e',
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
      _persistHistory();
    }
  }

  Future<void> _runAgent(
    String msg,
    _AiProfile profile,
    Spi? spi,
    List<Spi> servers,
    List<AgentConversationMessage> history,
  ) async {
    if (profile.supportTools) {
      await _syncMcpRuntime();
    }
    final events = _agentService.run(
      userMessage: msg,
      spi: spi,
      availableServers: servers,
      history: history,
      attachmentContext: [
        _buildAgentCenterContext(),
        _attachmentContext,
      ].where((e) => e.trim().isNotEmpty).join('\n\n'),
      imageDataUrls: _attachmentImageDataUrls,
      workspacePath: _workspacePath,
      onConfirm: _confirm,
      model: profile.model,
      baseUrl: profile.baseUrl,
      apiKey: profile.apiKey,
      enableTools: profile.supportTools,
      extraTools: profile.supportTools ? McpRuntimeService.instance.openAiTools() : const [],
    );
    final buf = StringBuffer();
    final logs = <String>[];
    await for (final ev in events) {
      if (ev is AgentThinking) {
        buf.write(ev.delta);
        _updateMsg(buf.toString(), logs);
      } else if (ev is AgentToolCall) {
        logs.add('调用 ${ev.toolName}');
        _updateMsg(buf.toString(), logs);
      } else if (ev is AgentToolResult) {
        final preview = ev.result.length > 180 ? '${ev.result.substring(0, 180)}...' : ev.result;
        logs.add('${ev.success ? '完成' : '失败'} ${ev.toolName}: $preview');
        _updateMsg(buf.toString(), logs);
      } else if (ev is AgentCompleted) {
        _finalize(buf.isEmpty ? ev.fullResponse : buf.toString(), logs);
        setState(() => _isLoading = false);
        _persistHistory();
        return;
      } else if (ev is AgentError) {
        _finalize('出错：${ev.message}', logs, isError: true);
        setState(() => _isLoading = false);
        _persistHistory();
        return;
      }
    }
    setState(() => _isLoading = false);
    _persistHistory();
  }

  void _updateMsg(String text, List<String> logs) {
    if (!mounted) return;
    setState(() {
      if (_messages.isNotEmpty && _messages.last.isStreaming) {
        _messages[_messages.length - 1] = _ChatMessage(
          role: 'assistant',
          content: text,
          toolLogs: List<String>.from(logs),
          timestamp: DateTime.now(),
          isStreaming: true,
        );
      }
    });
    _scrollToBottom();
  }

  void _finalize(String text, List<String> logs, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      if (_messages.isNotEmpty && _messages.last.isStreaming) {
        _messages[_messages.length - 1] = _ChatMessage(
          role: 'assistant',
          content: text.trim().isEmpty ? '没有返回内容。' : text,
          toolLogs: List<String>.from(logs),
          timestamp: DateTime.now(),
          isError: isError,
        );
      }
    });
  }

  Future<bool> _confirm(
    String tool,
    Map<String, dynamic> args,
    String reason,
  ) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('需要确认'),
        content: SelectableText(
          'AI 即将执行：$tool\n危险等级：$reason\n\n参数：\n${const JsonEncoder.withIndent('  ').convert(args)}\n\n确认执行？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('确认')),
        ],
      ),
    );
    return r ?? false;
  }

  List<Spi> _orderedServers() {
    final state = ref.read(serversProvider);
    final result = <Spi>[];
    for (final id in state.serverOrder) {
      final spi = state.servers[id];
      if (spi != null) result.add(spi);
    }
    for (final spi in state.servers.values) {
      if (!result.any((s) => s.id == spi.id)) result.add(spi);
    }
    return result;
  }

  Spi? _selectedServer(List<Spi> servers) {
    if (_currentServerId == null) return null;
    return servers.firstWhereOrNull((s) => s.id == _currentServerId);
  }

  Future<void> _pickWorkspace() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择本地项目目录',
      );
      if (path == null || path.trim().isEmpty) return;
      setState(() => _workspacePath = path.trim());
      Stores.setting.askAiWorkspacePath.put(_workspacePath);
      _mcpServers = _mcpServers
          .map((m) => m.id == 'builtin-filesystem' ? m.copyWith(args: _workspacePath) : m)
          .toList();
      _persistAgentCenter();
      _showSnack('已设置工作空间：$_workspacePath');
    } catch (e) {
      _showSnack('选择项目目录失败：$e');
    }
  }

  void _clearWorkspace() {
    setState(() => _workspacePath = '');
    Stores.setting.askAiWorkspacePath.put('');
    _mcpServers = _mcpServers
        .map((m) => m.id == 'builtin-filesystem' ? m.copyWith(args: '<workspace>') : m)
        .toList();
    _persistAgentCenter();
    _showSnack('已恢复默认 Agent 工作目录。');
  }

  bool _isImageFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  String _imageMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/png';
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        _showSnack('无法读取文件内容。');
        return;
      }
      if (_isImageFile(file.name)) {
        if (bytes.length > 6 * 1024 * 1024) {
          _showSnack('图片过大，请选择 6MB 以内的图片。');
          return;
        }
        final dataUrl = 'data:${_imageMime(file.name)};base64,${base64Encode(bytes)}';
        setState(() {
          _attachmentName = file.name;
          _attachmentContext = '用户上传了一张图片：${file.name}。如果当前模型支持视觉能力，请直接分析图片内容。';
          _attachmentImageDataUrls = [dataUrl];
        });
        _showSnack('已添加图片：${file.name}');
        return;
      }

      var content = utf8.decode(bytes, allowMalformed: true);
      if (content.length > 20000) {
        content = '${content.substring(0, 20000)}\n\n[内容过长，已截断]';
      }
      setState(() {
        _attachmentName = file.name;
        _attachmentContext = '文件名：${file.name}\n\n$content';
        _attachmentImageDataUrls = [];
      });
      _showSnack('已添加文件上下文：${file.name}');
    } catch (e) {
      _showSnack('读取文件失败：$e');
    }
  }

  void _clearAttachment() {
    setState(() {
      _attachmentContext = '';
      _attachmentName = null;
      _attachmentImageDataUrls = [];
    });
  }

  void _clearConversation() {
    setState(() {
      _messages = [
        const _ChatMessage(
          role: 'assistant',
          content: '新会话已开始。请选择服务器和模型，然后输入你的任务。',
        ),
      ];
      _attachmentContext = '';
      _attachmentName = null;
      _attachmentImageDataUrls = [];
      _currentConversationId = DateTime.now().microsecondsSinceEpoch.toString();
    });
    _persistHistory();
  }

  Future<void> _openAgentCenter() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Agent 控制中心'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _centerTile(
                icon: Icons.smart_toy_outlined,
                title: '智能体',
                subtitle: _currentAgent == null ? '未配置' : '${_currentAgent!.name} · ${_agents.length} 个',
                onTap: _openAgentsDialog,
              ),
              _centerTile(
                icon: Icons.extension_outlined,
                title: '技能',
                subtitle: '${_skills.where((s) => s.enabled).length}/${_skills.length} 已启用',
                onTap: _openSkillsDialog,
              ),
              _centerTile(
                icon: Icons.hub_outlined,
                title: 'MCP 配置',
                subtitle: '${_mcpServers.where((m) => m.enabled).length}/${_mcpServers.length} 已启用',
                onTap: _openMcpDialog,
              ),
              const SizedBox(height: 10),
              const Text(
                '这些配置会进入 Agent 上下文。MCP 当前先作为移动端配置入口保存，后续可接入真实 MCP 运行时。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _centerTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: _terminalOrange),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _openAgentsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('智能体'),
          content: SizedBox(
            width: 560,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _agents.length,
              itemBuilder: (_, index) {
                final item = _agents[index];
                return RadioListTile<String>(
                  value: item.id,
                  groupValue: _currentAgentId,
                  title: Text(item.name),
                  subtitle: Text(item.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
                  secondary: IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final updated = await _editAgent(item);
                      if (updated == null) return;
                      setState(() => _agents[index] = updated);
                      setDialogState(() {});
                      _persistAgentCenter();
                    },
                  ),
                  onChanged: (value) {
                    setState(() => _currentAgentId = value);
                    setDialogState(() {});
                    _persistAgentCenter();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
            FilledButton(
              onPressed: () async {
                final created = await _editAgent(null);
                if (created == null) return;
                setState(() {
                  _agents.add(created);
                  _currentAgentId = created.id;
                });
                setDialogState(() {});
                _persistAgentCenter();
              },
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_AgentConfig?> _editAgent(_AgentConfig? agent) async {
    final current = agent ??
        const _AgentConfig(
          id: '',
          name: '自定义智能体',
          prompt: '描述这个智能体的角色、目标、工具使用边界和回答风格。',
        );
    final nameCtrl = TextEditingController(text: current.name);
    final promptCtrl = TextEditingController(text: current.prompt);
    final result = await showDialog<_AgentConfig>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(agent == null ? '新增智能体' : '编辑智能体'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 10),
              TextField(
                controller: promptCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '智能体提示词',
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                c,
                current.copyWith(
                  id: current.id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : current.id,
                  name: nameCtrl.text.trim().isEmpty ? '未命名智能体' : nameCtrl.text.trim(),
                  prompt: promptCtrl.text.trim(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    promptCtrl.dispose();
    return result;
  }

  Future<void> _openSkillsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('技能'),
          content: SizedBox(
            width: 560,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _skills.length,
              itemBuilder: (_, index) {
                final item = _skills[index];
                return SwitchListTile(
                  value: item.enabled,
                  title: Text(item.name),
                  subtitle: Text(item.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
                  secondary: IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final updated = await _editSkill(item);
                      if (updated == null) return;
                      setState(() => _skills[index] = updated);
                      setDialogState(() {});
                      _persistAgentCenter();
                    },
                  ),
                  onChanged: (value) {
                    setState(() => _skills[index] = item.copyWith(enabled: value));
                    setDialogState(() {});
                    _persistAgentCenter();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
            FilledButton(
              onPressed: () async {
                final created = await _editSkill(null);
                if (created == null) return;
                setState(() => _skills.add(created));
                setDialogState(() {});
                _persistAgentCenter();
              },
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_SkillConfig?> _editSkill(_SkillConfig? skill) async {
    final current = skill ??
        const _SkillConfig(
          id: '',
          name: '自定义技能',
          prompt: '描述这个技能何时触发、具体步骤和输出格式。',
        );
    final nameCtrl = TextEditingController(text: current.name);
    final promptCtrl = TextEditingController(text: current.prompt);
    final result = await showDialog<_SkillConfig>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(skill == null ? '新增技能' : '编辑技能'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 10),
              TextField(
                controller: promptCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '技能提示词',
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                c,
                current.copyWith(
                  id: current.id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : current.id,
                  name: nameCtrl.text.trim().isEmpty ? '未命名技能' : nameCtrl.text.trim(),
                  prompt: promptCtrl.text.trim(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    promptCtrl.dispose();
    return result;
  }

  Future<void> _openMcpDialog() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('MCP 配置'),
          content: SizedBox(
            width: 560,
            child: _mcpServers.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('还没有 MCP 配置。可以添加内置文件系统或 stdio command + args 形式的 MCP server。'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _mcpServers.length,
                    itemBuilder: (_, index) {
                      final item = _mcpServers[index];
                      final status = _mcpStatuses.firstWhereOrNull((s) => s.id == item.id);
                      final statusText = status == null
                          ? '同步中'
                          : (status.running ? '运行中 · ${status.message}' : '未运行 · ${status.message}');
                      return SwitchListTile(
                        value: item.enabled,
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.command} ${item.args}\n$statusText'.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondary: IconButton(
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final updated = await _editMcp(item);
                            if (updated == null) return;
                            setState(() => _mcpServers[index] = updated);
                            setDialogState(() {});
                            _persistAgentCenter();
                          },
                        ),
                        onChanged: (value) {
                          setState(() => _mcpServers[index] = item.copyWith(enabled: value));
                          setDialogState(() {});
                          _persistAgentCenter();
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
            FilledButton(
              onPressed: () async {
                final created = await _editMcp(null);
                if (created == null) return;
                setState(() => _mcpServers.add(created));
                setDialogState(() {});
                _persistAgentCenter();
              },
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_McpConfig?> _editMcp(_McpConfig? mcp) async {
    final current = mcp ??
        const _McpConfig(
          id: '',
          name: '手机项目文件系统',
          command: 'builtin-filesystem',
          args: '<workspace>',
        );
    final nameCtrl = TextEditingController(text: current.name);
    final commandCtrl = TextEditingController(text: current.command);
    final argsCtrl = TextEditingController(text: current.args);
    final result = await showDialog<_McpConfig>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(mcp == null ? '新增 MCP' : '编辑 MCP'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 10),
              TextField(controller: commandCtrl, decoration: const InputDecoration(labelText: 'Command')),
              const SizedBox(height: 10),
              TextField(
                controller: argsCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Args',
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '手机端只内置文件系统 MCP，用于读取/写入你授权的本地项目目录。Node/Python 等外部 stdio MCP 不能在手机 App 内直接运行，需要部署在桌面端或服务器兼容服务中。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                c,
                current.copyWith(
                  id: current.id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : current.id,
                  name: nameCtrl.text.trim().isEmpty ? 'MCP Server' : nameCtrl.text.trim(),
                  command: commandCtrl.text.trim(),
                  args: argsCtrl.text.trim(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    commandCtrl.dispose();
    argsCtrl.dispose();
    return result;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serverState = ref.watch(serversProvider);
    final servers = _orderedServers();
    _syncServerSelection(servers);
    final profile = _currentProfile;
    final spi = _selectedServer(servers);

    return Scaffold(
      backgroundColor: _terminalBg,
      appBar: AppBar(
        title: const Text('Surlor Agent'),
        actions: [
          IconButton(
            tooltip: '历史会话',
            icon: const Icon(Icons.history),
            onPressed: _isLoading ? null : _openConversationHistory,
          ),
          IconButton(
            tooltip: 'Agent 控制中心',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: _isLoading ? null : _openAgentCenter,
          ),
          IconButton(
            tooltip: '刷新本地模型',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadLocalModels,
          ),
          IconButton(
            tooltip: '新会话',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _isLoading ? null : _clearConversation,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_terminalBg, Color(0xFF21170B)],
          ),
        ),
        child: Column(
          children: [
            _buildHeader(profile, spi, servers.length, serverState.serverOrder.length),
            Expanded(child: _buildList()),
            _buildInput(profile, spi, servers),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_AiProfile? profile, Spi? spi, int visibleServers, int orderedServers) {
    final chips = <Widget>[
      _statusChip('模型', profile == null ? '未配置' : '${profile.name} / ${profile.model}'),
      _statusChip('Agent', _currentAgent?.name ?? '默认'),
      _statusChip('技能', '${_skills.where((s) => s.enabled).length}'),
      _statusChip('MCP', '${_mcpServers.where((m) => m.enabled).length}'),
      _statusChip('服务器', '$visibleServers/$orderedServers'),
      _statusChip('目标', spi == null ? '未选择' : '${spi.name} ${spi.user}@${spi.ip}:${spi.port}'),
      _statusChip('工作区', _workspacePath.isEmpty ? '默认目录' : _workspacePath),
      _statusChip('本地模型', _localRuntimeAvailable ? 'Ollama 已检测' : '需外部运行时'),
      if (_attachmentName != null) _statusChip('附件', _attachmentName!),
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _terminalPanel,
        border: Border.all(color: _terminalLine, width: 1.2),
        borderRadius: BorderRadius.zero,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }

  Widget _statusChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        border: Border.all(color: _terminalOrange.withOpacity(0.58)),
      ),
      child: Center(
        child: Text(
          '$label: $value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFFFFCC80)),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (c, i) => _buildBubble(_messages[i]),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isUser = msg.role == 'user';
    final color = isUser ? const Color(0xFF2A1A05) : const Color(0xFF17130D);
    final border = isUser ? _terminalOrange : const Color(0xFF7C4D00);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: msg.isError ? Colors.redAccent : border,
          width: 1.2,
        ),
        borderRadius: BorderRadius.zero,
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontSize: 14,
          height: 1.45,
          color: Color(0xFFFFF3E0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? '> USER' : '> AGENT',
              style: TextStyle(
                color: isUser ? _terminalOrange : const Color(0xFFFFCC80),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              msg.content.isEmpty && msg.isStreaming ? '思考中...' : msg.content,
            ),
            if (msg.toolLogs != null && msg.toolLogs!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  border: Border.all(color: _terminalOrange.withOpacity(0.3)),
                ),
                child: Text(
                  msg.toolLogs!.map((e) => '- $e').join('\n'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFFCC80),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final avatar = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFF332414) : _terminalOrange,
        border: Border.all(color: const Color(0xFFFFCC80), width: 2),
        borderRadius: BorderRadius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: isUser
          ? const Center(
              child: Text(
                'U',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : Image.asset('assets/app_icon.png', fit: BoxFit.cover),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isUser
            ? [Flexible(child: bubble), const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), Flexible(child: bubble)],
      ),
    );
  }

  Widget _buildInput(_AiProfile? profile, Spi? spi, List<Spi> servers) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF120D08),
        border: Border(top: BorderSide(color: _terminalLine, width: 1.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildProfileSelector(profile)),
              const SizedBox(width: 8),
              Expanded(child: _buildServerSelector(spi, servers)),
            ],
          ),
          if (_attachmentName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已附加：$_attachmentName',
                    style: const TextStyle(color: Color(0xFFFFCC80), fontSize: 12),
                  ),
                ),
                TextButton(onPressed: _clearAttachment, child: const Text('移除')),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: '上传文件或图片作为上下文',
                onPressed: _isLoading ? null : _pickAttachment,
                icon: const Icon(Icons.attach_file),
              ),
              IconButton(
                tooltip: _workspacePath.isEmpty ? '选择本地项目目录' : '已选工作空间，长按清除',
                onPressed: _isLoading ? null : _pickWorkspace,
                onLongPress: _isLoading || _workspacePath.isEmpty ? null : _clearWorkspace,
                icon: const Icon(Icons.folder_open),
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  style: const TextStyle(),
                  decoration: const InputDecoration(
                    hintText: '输入任务，例如：查看服务器状态 / 读取日志 / 修改配置文件...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  ),
                  onSubmitted: (v) => _sendMessage(v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isLoading ? null : () => _sendMessage(_textController.text),
                child: Text(_isLoading ? '运行中' : '发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSelector(_AiProfile? profile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: _terminalOrange.withOpacity(0.6)),
        color: Colors.black.withOpacity(0.18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: profile?.id,
          isExpanded: true,
          hint: const Text('选择模型'),
          items: _profiles
              .map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.name} · ${p.model}', overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _isLoading
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() => _currentProfileId = v);
                  _persistProfiles();
                },
        ),
      ),
    );
  }

  Widget _buildServerSelector(Spi? spi, List<Spi> servers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: _terminalOrange.withOpacity(0.6)),
        color: Colors.black.withOpacity(0.18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: spi?.id,
          isExpanded: true,
          hint: const Text('选择服务器'),
          items: servers
              .map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text('${s.name} · ${s.user}@${s.ip}', overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _isLoading
              ? null
              : (v) {
                  setState(() => _currentServerId = v);
                  if (v != null) Stores.setting.askAiDefaultServerId.put(v);
                },
        ),
      ),
    );
  }
}
