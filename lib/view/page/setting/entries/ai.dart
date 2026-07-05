part of '../entry.dart';

extension _AI on _AppSettingsPageState {
  Widget _buildAskAiTextTile({
    required HiveProp<String> prop,
    required Widget leading,
    required String title,
    required String hint,
    required String Function(String? value) displayBuilder,
    String? description,
    bool obscure = false,
  }) {
    return prop.listenable().listenVal((val) {
      return ListTile(
        leading: leading,
        title: Text(title),
        subtitle: Text(
          displayBuilder(val),
          style: UIs.textGrey,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _showAskAiFieldDialog(
          prop: prop,
          title: title,
          hint: hint,
          description: description,
          obscure: obscure,
        ),
      );
    });
  }

  Widget _buildAskAiConfig() {
    final l10n = context.l10n;

    // Surlor AI 管理入口（新功能）
    final managerEntry = ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF9500), Color(0xFFFF6B35)]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.smart_toy, color: Colors.white, size: 20),
      ),
      title: Text('Surlor AI 引擎管理',
          style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold)),
      subtitle: const Text('本地模型下载 · API 预设配置 · 连接测试'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SurlorAiManagerPage())),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          managerEntry,
          const Divider(height: 1, indent: 56),
          ExpandTile(
            leading: const Icon(LineAwesome.robot_solid, size: _kIconSize),
            title: TipText(l10n.askAi, l10n.askAiUsageHint),
            children: [
              _buildAskAiTextTile(
                prop: _setting.askAiBaseUrl,
                leading: const Icon(MingCute.link_2_line),
                title: l10n.askAiBaseUrl,
                hint: 'https://api.openai.com/v1/chat/completions',
                description: l10n.askAiEndpointTip,
                displayBuilder: (val) =>
                    (val == null || val.isEmpty) ? libL10n.empty : val,
              ),
              _buildAskAiTextTile(
                prop: _setting.askAiModel,
                leading: const Icon(Icons.view_module),
                title: libL10n.askAiModel,
                hint: 'gpt-4o-mini',
                displayBuilder: (val) =>
                    (val == null || val.isEmpty) ? libL10n.empty : val,
              ),
              _buildAskAiTextTile(
                prop: _setting.askAiApiKey,
                leading: const Icon(MingCute.key_2_line),
                title: l10n.askAiApiKey,
                hint: 'sk-...',
                obscure: true,
                displayBuilder: (val) =>
                    val?.isNotEmpty == true ? l10n.configured : libL10n.empty,
              ),
            ],
          ).cardx,
        ],
      ),
    );
  }

  Future<void> _showAskAiFieldDialog({
    required HiveProp<String> prop,
    required String title,
    required String hint,
    String? description,
    bool obscure = false,
  }) async {
    return withTextFieldController((ctrl) async {
      final fetched = prop.fetch();
      if (fetched != null && fetched.isNotEmpty) ctrl.text = fetched;

      void onSave() {
        prop.put(ctrl.text.trim());
        context.pop();
      }

      await context.showRoundDialog(
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Input(
              controller: ctrl,
              autoFocus: true,
              label: title,
              hint: hint,
              icon: obscure ? MingCute.key_2_line : Icons.edit,
              obscureText: obscure,
              suggestion: !obscure,
              onSubmitted: (_) => onSave(),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description, style: UIs.textGrey),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              prop.delete();
              context.pop();
            },
            child: Text(libL10n.clear),
          ),
          TextButton(onPressed: onSave, child: Text(libL10n.ok)),
        ],
      );
    });
  }
}
