import 'dart:convert';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:surlor_ai/data/model/ai/model_registry.dart';
import 'package:surlor_ai/data/provider/ai/ai_capability_tester.dart';
import 'package:surlor_ai/data/provider/ai/ollama_service.dart';
import 'package:surlor_ai/data/res/store.dart';

/// Surlor AI 管理页面
///
/// 包含：
/// - API 服务商选择（预设模板）
/// - 本地/自建 OpenAI 兼容服务接入
/// - 连接测试
class SurlorAiManagerPage extends StatefulWidget {
  const SurlorAiManagerPage({super.key});

  @override
  State<SurlorAiManagerPage> createState() => _SurlorAiManagerPageState();
}

class _SurlorAiManagerPageState extends State<SurlorAiManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surlor AI 引擎'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'API 配置'),
            Tab(text: '本地/自建'),
            Tab(text: '关于'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ApiProviderTab(),
          _LocalModelTab(),
          _AboutTab(),
        ],
      ),
    );
  }
}

// ──────────────────── Tab 1: API 服务商配置 ────────────────────

class _ApiProviderTab extends StatefulWidget {
  const _ApiProviderTab();

  @override
  State<_ApiProviderTab> createState() => _ApiProviderTabState();
}

class _ApiProviderTabState extends State<_ApiProviderTab> {
  ApiProviderPreset? _selectedPreset;
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _modelCtrl;
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    final savedUrl = Stores.setting.askAiBaseUrl.fetch();
    final savedKey = Stores.setting.askAiApiKey.fetch();
    final savedModel = Stores.setting.askAiModel.fetch();

    _baseUrlCtrl = TextEditingController(text: savedUrl);
    _apiKeyCtrl = TextEditingController(text: savedKey);
    _modelCtrl = TextEditingController(text: savedModel);

    if (savedUrl.isNotEmpty) {
      for (final p in apiPresets) {
        if (p.baseUrl.isNotEmpty) {
          final host = Uri.tryParse(p.baseUrl)?.host ?? '';
          if (host.isNotEmpty && savedUrl.contains(host)) {
            _selectedPreset = p;
            break;
          }
        }
      }
    }
    if (savedModel.isNotEmpty) _selectedModel = savedModel;
    if (_selectedPreset != null &&
        _selectedPreset!.models.isNotEmpty &&
        !_selectedPreset!.models.contains(_selectedModel)) {
      _selectedPreset = null;
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _onPresetSelected(ApiProviderPreset preset) {
    setState(() {
      _selectedPreset = preset;
      _baseUrlCtrl.text = preset.baseUrl;
      _selectedModel = preset.models.isNotEmpty ? preset.models.first : null;
      _modelCtrl.text = _selectedModel ?? '';
    });
  }

  Future<void> _saveConfig() async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) {
      context.showRoundDialog(
        title: '提示',
        child: const Text('请输入 API 地址'),
        actions: [TextButton(onPressed: () => context.pop(), child: const Text('确定'))],
      );
      return;
    }

    Stores.setting.askAiBaseUrl.put(url);
    final key = _apiKeyCtrl.text.trim();
    if (key.isNotEmpty) {
      Stores.setting.askAiApiKey.put(key);
    }
    final model = _selectedModel ?? _modelCtrl.text.trim();
    if (model.isNotEmpty) {
      Stores.setting.askAiModel.put(model);
    }
    _savePrimaryProfile(
      url: url,
      apiKey: key,
      model: model,
      supportText: true,
      supportImage: false,
      supportVideo: false,
      supportTools: true,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已保存。')),
      );
    }
  }

  void _savePrimaryProfile({
    required String url,
    required String apiKey,
    required String model,
    required bool supportText,
    required bool supportImage,
    required bool supportVideo,
    required bool supportTools,
  }) {
    final raw = Stores.setting.askAiProfiles.fetch();
    final profiles = <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) profiles.add(Map<String, dynamic>.from(item));
        }
      }
    } catch (_) {}

    final currentId = Stores.setting.askAiCurrentProfileId.fetch();
    var index = profiles.indexWhere((p) => p['id'] == currentId);
    if (index < 0) index = profiles.indexWhere((p) => p['id'] == 'default');
    final profile = <String, dynamic>{
      if (index >= 0) ...profiles[index],
      'id': index >= 0 ? (profiles[index]['id'] ?? 'default') : 'default',
      'name': _selectedPreset?.name ?? (model.isEmpty ? '自定义模型' : model),
      'baseUrl': url,
      'apiKey': apiKey,
      'model': model,
      'supportText': supportText,
      'supportImage': supportImage,
      'supportVideo': supportVideo,
      'supportTools': supportTools,
    };
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.insert(0, profile);
    }
    Stores.setting.askAiProfiles.put(jsonEncode(profiles));
    Stores.setting.askAiCurrentProfileId.put('${profile['id']}');
  }

  Future<void> _testConnection() async {
    final url = _baseUrlCtrl.text.trim();
    final key = _apiKeyCtrl.text.trim();
    final model = (_selectedModel ?? _modelCtrl.text).trim();
    if (url.isEmpty || model.isEmpty) {
      context.showRoundDialog(
        title: '连接测试',
        child: const Text('请先填写 API 地址和模型名称。'),
        actions: [TextButton(onPressed: () => context.pop(), child: const Text('确定'))],
      );
      return;
    }
    final isLocal = url.contains('127.0.0.1:11434') || url.contains('localhost:11434');
    if (!isLocal && key.isEmpty) {
      context.showRoundDialog(
        title: '连接测试',
        child: const Text('非本地服务需要填写 API Key。'),
        actions: [TextButton(onPressed: () => context.pop(), child: const Text('确定'))],
      );
      return;
    }

    context.showRoundDialog(
      title: '连接测试',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('正在测试 $model ...', style: UIs.textGrey),
        ],
      ),
    );

    String resultText;
    Object? error;
    try {
      final result = await AiCapabilityTester().test(
        baseUrl: url,
        apiKey: key,
        model: model,
      );
      Stores.setting.askAiSupportText.put(result.text.supported);
      Stores.setting.askAiSupportImage.put(result.image.supported);
      Stores.setting.askAiSupportVideo.put(result.video.supported);
      Stores.setting.askAiSupportTools.put(result.tools.supported);
      _savePrimaryProfile(
        url: url,
        apiKey: key,
        model: model,
        supportText: result.text.supported,
        supportImage: result.image.supported,
        supportVideo: result.video.supported,
        supportTools: result.tools.supported,
      );
      resultText = '模型 $model 能力测试完成：\n${result.toHumanText()}\n\n'
          '已根据测试结果更新文本、图像、视频、工具调用能力开关；不支持的能力会被关闭。';
    } catch (e) {
      error = e;
      resultText = '连接失败：$e';
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    context.showRoundDialog(
      title: error == null ? '连接成功' : '连接失败',
      child: SelectableText(resultText),
      actions: [TextButton(onPressed: () => context.pop(), child: const Text('确定'))],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('选择 API 服务商', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...apiPresets.map((preset) => _buildPresetCard(preset)),

        const Divider(height: 32),

        Text('详细配置', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Input(
                  controller: _baseUrlCtrl,
                  label: 'API 地址',
                  hint: 'https://api.openai.com/v1',
                  icon: Icons.link,
                  onChanged: (v) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Input(
                  controller: _apiKeyCtrl,
                  label: 'API Key (可选)',
                  hint: 'sk-...',
                  icon: Icons.key,
                  obscureText: true,
                  onChanged: (v) => setState(() {}),
                ),
                const SizedBox(height: 12),

                if (_selectedPreset != null && _selectedPreset!.models.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _selectedModel,
                    decoration: InputDecoration(
                      labelText: '模型',
                      prefixIcon: const Icon(Icons.view_module, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: _selectedPreset!.models.map((m) {
                      return DropdownMenuItem(value: m, child: Text(m));
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedModel = v;
                        _modelCtrl.text = v ?? '';
                      });
                    },
                  )
                else
                  Input(
                    controller: _modelCtrl,
                    label: '模型名称',
                    hint: 'gpt-4o-mini 或 qwen3:4b 等',
                    icon: Icons.view_module,
                    onChanged: (v) => setState(() {}),
                  ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveConfig,
                        icon: const Icon(Icons.save),
                        label: const Text('保存配置'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _baseUrlCtrl.text.trim().isNotEmpty ? _testConnection : null,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('测试连接'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        _buildStatusCard(),
      ],
    );
  }

  Widget _buildPresetCard(ApiProviderPreset preset) {
    final isSelected = _selectedPreset == preset;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: Icon(preset.icon,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : null),
        title: Text(preset.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preset.note != null)
              Text(preset.note!,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            Text(preset.baseUrl,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ],
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary)
            : const Icon(Icons.circle_outlined, color: Colors.grey),
        onTap: () => _onPresetSelected(preset),
      ),
    );
  }

  Widget _buildStatusCard() {
    final hasConfig =
        Stores.setting.askAiBaseUrl.fetch().isNotEmpty &&
        Stores.setting.askAiApiKey.fetch().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: hasConfig
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        border: Border.all(
            color: hasConfig ? Colors.green : Colors.orange.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(hasConfig ? Icons.check_circle_outline : Icons.info_outline,
              color: hasConfig ? Colors.green : Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasConfig
                  ? 'AI 已就绪\n在 SSH 终端选中文字即可使用"AI 助手"'
                  : '尚未配置 AI\n请选择一个 API 服务商或输入自定义地址',
              style: TextStyle(
                fontSize: 13,
                color: hasConfig ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────── Tab 2: 本地/自建服务 ────────────────────

class _LocalModelTab extends StatefulWidget {
  const _LocalModelTab();

  @override
  State<_LocalModelTab> createState() => _LocalModelTabState();
}

class _LocalModelTabState extends State<_LocalModelTab> {
  final _ollamaService = OllamaService();
  bool _ollamaAvailable = false;
  bool _checking = true;
  List<OllamaModel> _installedModels = [];
  // 下载状态：key=ollamaName, value=进度(0.0~1.0)或null(下载中未知进度)
  final Map<String, double?> _downloadProgress = {};
  final Map<String, String?> _downloadStatus = {};

  @override
  void initState() {
    super.initState();
    _checkOllama();
  }

  Future<void> _checkOllama() async {
    setState(() { _checking = true; _ollamaAvailable = false; });
    try {
      _ollamaAvailable = await _ollamaService.isAvailable();
      if (_ollamaAvailable) {
        _installedModels = await _ollamaService.listModels();
      }
    } catch (_) {
      _ollamaAvailable = false;
    }
    if (mounted) setState(() => _checking = false);
  }

  bool _isInstalled(AiModelEntry model) {
    return _installedModels.any((m) => m.name == model.ollamaName);
  }

  void _startDownload(AiModelEntry model) {
    final name = model.ollamaName;
    _downloadProgress[name] = null;
    _downloadStatus[name] = '准备下载...';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final pct = _downloadProgress[name];
          final status = _downloadStatus[name] ?? '';
          final double progress = pct ?? 0.0;

          Future<void> cancel() async {
            _downloadProgress.remove(name);
            _downloadStatus.remove(name);
            Navigator.pop(ctx);
          }

          return AlertDialog(
            title: Text('下载 ${model.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pct != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(value: progress),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(),
                  ),
                Text(status, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                if (pct != null)
                  Text('${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(onPressed: cancel, child: const Text('取消')),
            ],
          );
        });
      },
    ).then((_) {
      // dialog dismissed
      _downloadProgress.remove(name);
      _downloadStatus.remove(name);
    });

    _doDownload(model);
  }

  Future<void> _doDownload(AiModelEntry model) async {
    final name = model.ollamaName;
    try {
      final stream = _ollamaService.pullModel(name);
      await for (final ev in stream) {
        if (!mounted) return;
        setState(() {
          if (ev is PullDownloading) {
            _downloadProgress[name] = ev.pct;
            _downloadStatus[name] = ev.status;
          } else if (ev is PullStatus) {
            _downloadStatus[name] = ev.msg;
          } else if (ev is PullDone) {
            _downloadProgress[name] = 1.0;
            _downloadStatus[name] = '下载完成';
          } else if (ev is PullErr) {
            _downloadStatus[name] = '错误: ${ev.msg}';
          }
        });
      }
      // 下载完成，刷新列表
      if (mounted) {
        _installedModels = await _ollamaService.listModels();
        setState(() {});
        // 关闭进度对话框
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadStatus[name] = '错误: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_ollamaAvailable) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.orange.withOpacity(0.1),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Ollama 未检测到', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
                const SizedBox(height: 12),
                const Text(
                  'App 内不会直接部署或运行大模型。请连接一套已经运行的 Ollama / vLLM / llama.cpp / OpenAI 兼容服务。手机端推荐把模型跑在电脑、NAS 或服务器上，再在 API 配置里填写地址。',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text('方式一：连接电脑/NAS/服务器上的 Ollama',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SelectableText(
                    '在运行模型的设备上启动 Ollama，并确保手机可访问该地址。',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFD4D4D4)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('方式二：连接自建 OpenAI 兼容接口',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                const Text(
                  '支持 vLLM、llama.cpp、One API、New API 等兼容 /v1/chat/completions 的服务。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checkOllama,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新检测'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text('推荐接入的模型', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...builtinModels.map((model) => _ModelCard(
            model: model,
            isInstalled: false,
            onDeploy: null,
          )),
        ],
      );
    }

    // Ollama 可用
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '本地/自建模型需要外部运行时提供 OpenAI 兼容 API。'
                  '\n\n如果当前设备能访问 Ollama，这里会显示已安装模型；手机端通常建议连接电脑、NAS 或服务器上的模型服务。',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Text('推荐接入的模型', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text('已安装 ${_installedModels.length} 个',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 8),

        ...builtinModels.map((model) => _ModelCard(
          model: model,
          isInstalled: _isInstalled(model),
          isDownloading: _downloadProgress.containsKey(model.ollamaName),
          downloadProgress: _downloadProgress[model.ollamaName],
          downloadStatus: _downloadStatus[model.ollamaName],
          onDeploy: () => _startDownload(model),
        )),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    this.isInstalled = false,
    this.isDownloading = false,
    this.downloadProgress,
    this.downloadStatus,
    this.onDeploy,
  });

  final AiModelEntry model;
  final bool isInstalled;
  final bool isDownloading;
  final double? downloadProgress;
  final String? downloadStatus;
  final VoidCallback? onDeploy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(model.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 8),
                      ...model.tags.take(2).map((tag) => Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tag == '推荐'
                              ? Colors.orange.withOpacity(0.15)
                              : Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tag,
                            style: TextStyle(
                                fontSize: 10,
                                color: tag == '推荐'
                                    ? Colors.orange
                                    : Colors.blue[700])),
                      )),
                      const SizedBox(width: 6),
                      if (isInstalled)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('已安装',
                              style: TextStyle(fontSize: 10, color: Colors.green)),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(model.size,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'monospace')),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Text(model.description,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),

            if (isDownloading && downloadStatus != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: downloadProgress,
              ),
              const SizedBox(height: 4),
              Text(downloadStatus!,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],

            const SizedBox(height: 8),

            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _infoChip(Icons.memory_outlined, model.parameterCount),
                _infoChip(Icons.text_fields_outlined, '${model.contextLength ~/ 1024}K'),
                _infoChip(Icons.language, model.languages.first),
                ...model.useCases.take(1).map((u) => _infoChip(Icons.bolt_outlined, u)),
              ],
            ),

            const SizedBox(height: 12),

            if (isInstalled)
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green[600]),
                  const SizedBox(width: 6),
                  Text('已通过 Ollama 安装',
                      style: TextStyle(fontSize: 12, color: Colors.green[600])),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isDownloading ? null : onDeploy,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(isDownloading ? '拉取中...' : '通过 Ollama 拉取'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey[500]),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

// ──────────────────── Tab 3: 关于 ────────────────────

class _AboutTab extends StatelessWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/app_icon.png', width: 100, height: 100, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),

              const Text('Surlor AI',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const Text('AI 驱动的服务器智能管家',
                  style: TextStyle(fontSize: 14, color: Colors.grey)),

              const SizedBox(height: 24),

              _featureRow(Icons.chat_bubble_outline, '自然语言对话式操作服务器'),
              _featureRow(Icons.download_outlined, '内置轻量本地模型，隐私安全'),
              _featureRow(Icons.cloud_outlined, '兼容国内外所有 OpenAI 格式 API'),
              _featureRow(Icons.terminal, 'SSH 终端集成，选中即问 AI'),
              _featureRow(Icons.security, '操作前确认机制，防止误操作'),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    const Text('技术基础', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('移动端 AI Agent 工具箱\n'
                        'UI：橙色像素终端风格\n'
                        'AI 引擎：OpenAI 兼容格式 / 外部本地模型服务',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.6)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.orange[700]),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
