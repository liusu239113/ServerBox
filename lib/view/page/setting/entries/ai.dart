part of '../entry.dart';

extension _AI on _AppSettingsPageState {
  Widget _buildAskAiConfig() {
    final managerEntry = ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset('assets/app_icon.png', width: 36, height: 36, fit: BoxFit.cover),
      ),
      title: Text(
        'Surlor AI 引擎管理',
        style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold),
      ),
      subtitle: const Text('统一配置模型、Agent、技能、MCP 和能力测试'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SurlorAiManagerPage())),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: managerEntry,
    );
  }
}
