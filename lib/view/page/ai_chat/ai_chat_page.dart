/// Surlor AI 对话页面
///
/// 用户通过自然语言与 AI Agent 交互，
/// Agent 可以执行服务器操作（需用户确认）。
library;

import 'dart:async';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:surlor_ai/data/model/ai/agent_tools.dart';
import 'package:surlor_ai/data/provider/ai/agent_service.dart';
import 'package:surlor_ai/data/provider/ai/ask_ai.dart';
import 'package:surlor_ai/data/provider/ai/ollama_service.dart';
import 'package:surlor_ai/data/res/store.dart';

/// 单条聊天消息
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

  final String role;
  final String content;
  final List<String>? toolLogs;
  final DateTime? timestamp;
  final bool isError;
  final bool isStreaming;
}

/// Surlor AI 对话页面
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  static const route = AppRouteNoArg(page: AiChatPage.new, path: '/ai-chat');

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  final _agentService = AgentService();
  Spi? _currentSpi;

  // 模型选择
  String? _selectedModel;
  List<String> _modelOptions = [];
  final _ollamaService = OllamaService();

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      role: 'assistant',
      content: '🤖 **Surlor AI 已上线**\n\n'
          '我是你的服务器智能助手。你可以让我：\n\n'
          '- 📊 查看服务器状态\n'
          '- 📂 浏览和编辑服务器文件\n'
          '- 🔧 执行运维命令\n'
          '- 🐳 管理 Docker 容器\n'
          '- 🛠️ 排查和解决问题\n\n'
          '请先连接一台服务器，然后告诉我你想做什么！',
      timestamp: null,
    ));
    _loadModels();
  }

  Future<void> _loadModels() async {
    final apiModel = Stores.setting.askAiModel.fetch().trim();
    final options = <String>[];
    if (apiModel.isNotEmpty) {
      options.add(apiModel);
      _selectedModel = apiModel;
    }
    try {
      final available = await _ollamaService.isAvailable();
      if (available) {
        final installed = await _ollamaService.listModels();
        for (final m in installed) {
          if (!options.contains(m.name)) options.add(m.name);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _modelOptions = options);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;
    setState(() {
      _messages.add(_ChatMessage(
        role: 'user',
        content: text.trim(),
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
      _messages.add(_ChatMessage(
        role: 'assistant',
        content: '',
        timestamp: DateTime.now(),
        isStreaming: true,
      ));
    });
    _textController.clear();
    _scrollToBottom();
    try {
      await _runAgent(text.trim());
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isStreaming) _messages.removeLast();
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: '⚠️ 出错：$e',
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
    }
  }

  Future<void> _runAgent(String msg) async {
    final selected = _selectedModel;
    String? model, baseUrl, apiKey;

    if (selected != null && selected.isNotEmpty) {
      final isLocal = await _isOllamaModel(selected);
      if (isLocal) {
        model = selected;
        baseUrl = 'http://127.0.0.1:11434/v1';
        apiKey = 'ollama';
      } else {
        model = selected;
      }
    }

    final events = _agentService.run(
      userMessage: msg,
      spi: _currentSpi,
      onNeedConfirm: _confirm,
      model: model,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    final buf = StringBuffer();
    final logs = <String>[];
    await for (final ev in events) {
      if (ev is AgentThinking) { buf.write(ev.delta); _updateMsg(buf.toString(), logs); }
      if (ev is AgentToolCall) { logs.add('🔧 调用：${ev.toolName}'); _updateMsg(buf.toString(), logs); }
      if (ev is AgentToolResult) { logs.add('${ev.success ? '✅' : '❌'} ${ev.toolName}'); _updateMsg(buf.toString(), logs); }
      if (ev is AgentCompleted) { _finalize(buf.toString(), logs); setState(() => _isLoading = false); return; }
      if (ev is AgentError) { _finalize('⚠️ ${ev.message}', logs); setState(() => _isLoading = false); return; }
    }
  }

  Future<bool> _isOllamaModel(String modelName) async {
    try {
      final models = await _ollamaService.listModels();
      return models.any((m) => m.name == modelName);
    } catch (_) {
      return false;
    }
  }

  void _updateMsg(String text, List<String> logs) {
    setState(() {
      if (_messages.isNotEmpty && _messages.last.isStreaming) {
        _messages[_messages.length - 1] = _ChatMessage(
          role: 'assistant', content: text, toolLogs: logs,
          timestamp: DateTime.now(), isStreaming: true,
        );
      }
    });
    _scrollToBottom();
  }

  void _finalize(String text, List<String> logs) {
    setState(() {
      if (_messages.isNotEmpty && _messages.last.isStreaming) {
        _messages[_messages.length - 1] = _ChatMessage(
          role: 'assistant', content: text, toolLogs: logs,
          timestamp: DateTime.now(), isStreaming: false,
        );
      }
    });
  }

  Future<bool> _confirm(String tool, Map<String, dynamic> args, String reason) async {
    final r = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('⚠️ 需要确认'),
      content: Text('AI 即将执行：$tool\n危险等级：$reason\n\n确认执行？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('确认')),
      ],
    ));
    return r ?? false;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surlor AI'),
        actions: [
          if (_modelOptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _modelOptions.contains(_selectedModel) ? _selectedModel : _modelOptions.first,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  items: _modelOptions.map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(m, style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedModel = v);
                  },
                ),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() => _messages.clear()); _loadModels(); }),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (c, i) {
        if (i == _messages.length) return const Padding(
          padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        return _buildBubble(_messages[i]);
      },
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) CircleAvatar(child: const Icon(Icons.smart_toy)),
          Flexible(child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? Colors.orange : Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(msg.content, style: const TextStyle(fontSize: 14)),
          )),
          if (isUser) CircleAvatar(child: const Icon(Icons.person)),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: TextField(
            controller: _textController,
            focusNode: _focusNode,
            decoration: const InputDecoration(hintText: '告诉 AI 你想做什么...'),
            onSubmitted: (v) => _sendMessage(v),
          )),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(_textController.text),
          ),
        ],
      ),
    );
  }
}
