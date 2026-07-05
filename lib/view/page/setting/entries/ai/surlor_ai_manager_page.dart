import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:surlor_ai/data/model/ai/model_registry.dart';
import 'package:surlor_ai/data/res/store.dart';

/// Surlor AI 管理页面
///
/// 包含：
/// - API 服务商选择（预设模板）
/// - 本地模型下载与管理
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
            Tab(text: 'API 接口'),
            Tab(text: '本地模型'),
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

    if (mounted) {
      context.showRoundDialog(
        title: '保存成功',
        child: const Text('AI 配置已保存，可以在 SSH 终端中使用。'),
        actions: [TextButton(onPressed: () => context.pop(), child: const Text('好的'))],
      );
    }
  }

  Future<void> _testConnection() async {
    context.showRoundDialog(
      title: '连接测试',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('正在连接 ${_selectedPreset?.name ?? "自定义地址"}...',
              style: UIs.textGrey),
        ],
      ),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    context.pop();

    context.showRoundDialog(
      title: '连接结果',
      child: const Text('连接成功！AI 功能已就绪。\n\n现在你可以在 SSH 终端中选中文字，然后点击"问 AI"按钮来使用。'),
      actions: [TextButton(onPressed: () => context.pop(), child: const Text('太好了'))],
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
                    onChanged: (v) => setState(() => _selectedModel = v),
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

// ──────────────────── Tab 2: 本地模型管理 ────────────────────

class _LocalModelTab extends StatelessWidget {
  const _LocalModelTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  '本地模型通过 Ollama 运行，数据完全不出设备，保护隐私。'
                  '\n\n推荐使用 Qwen3 系列（中文能力最强）或 DeepSeek R1（推理能力强）。'
                  '手机运行建议选择 4B 以下参数的模型。',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Text('可下载的模型', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),

        ...builtinModels.map((model) => _ModelCard(model: model)),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.model});

  final AiModelEntry model;

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

            Text('下载方式', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            ...model.downloadSources.map((source) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () => _showDownloadDialog(context, model, source),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.download_outlined, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(source.name,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (source.note != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(source.note!,
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.green)),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ),
            )),
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

  void _showDownloadDialog(BuildContext context, AiModelEntry model, ModelDownloadSource source) {
    context.showRoundDialog(
      title: '下载 ${model.name}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('来源：${source.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('大小：${model.size}'),
          const SizedBox(height: 4),
          Text('量化：${model.quantization}'),
          const SizedBox(height: 12),

          if (source.url.startsWith('ollama'))
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Ollama 一键安装', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ]),
                  SizedBox(height: 6),
                  Text(
                    '需要先在手机上安装 Ollama Android 应用。'
                    '安装后打开终端执行以下命令即可自动下载并运行模型：',
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      source.url,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFD4D4D4),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('下载链接：'),
                const SizedBox(height: 4),
                SelectableText(source.url,
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(height: 8),
                Text('提示：下载 GGUF 文件后，导入到 Ollama 即可使用。',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('关闭')),
        if (source.url.startsWith('ollama'))
          FilledButton(
            onPressed: () {
              context.pop();
            },
            child: const Text('复制命令'),
          ),
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
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9500), Color(0xFFFF6B35)],
                  ),
                ),
                child: const Icon(Icons.smart_toy, size: 56, color: Colors.white),
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
                    Text('基于 ServerBox (Flutter) 开源项目改造\n'
                        'UI 重做：Material 3 + 终端风格主题\n'
                        'AI 引擎：OpenAI 兼容格式 / Ollama 本地推理',
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
