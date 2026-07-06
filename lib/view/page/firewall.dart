import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surlor_ai/core/extension/ssh_client.dart';
import 'package:surlor_ai/core/route.dart';
import 'package:surlor_ai/data/model/server/server_private_info.dart';
import 'package:surlor_ai/data/provider/server/single.dart';
import 'package:surlor_ai/view/page/ssh/page/page.dart';

final class FirewallPage extends ConsumerStatefulWidget {
  const FirewallPage({super.key, required this.args});

  final SpiRequiredArgs args;

  static const route = AppRouteArg<void, SpiRequiredArgs>(
    page: FirewallPage.new,
    path: '/firewall',
  );

  @override
  ConsumerState<FirewallPage> createState() => _FirewallPageState();
}

final class _FirewallPageState extends ConsumerState<FirewallPage> {
  bool _loading = false;
  String _status = '';
  String _ports = '';
  String _tunnels = '';
  Object? _error;

  late final _provider = serverProvider(widget.args.spi.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final serverState = ref.read(_provider);
      final client = serverState.client;
      if (client == null || client.isClosed) {
        setState(() => _error = '服务器未连接');
        return;
      }
      final status = await client.execForOutput(_firewallCmd, stderr: true);
      final ports = await client.execForOutput(_portsCmd, stderr: true);
      final tunnels = await client.execForOutput(_tunnelsCmd, stderr: true);
      if (!mounted) return;
      setState(() {
        _status = status.trim();
        _ports = ports.trim();
        _tunnels = tunnels.trim();
      });
    } catch (e, s) {
      Loggers.app.warning('Firewall page refresh failed', e, s);
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        centerTitle: true,
        title: TwoLineText(up: '防火墙', down: widget.args.spi.name),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
          IconButton(
            tooltip: libL10n.terminal,
            icon: const Icon(Icons.terminal),
            onPressed: _openFirewallShell,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(13),
          children: [
            if (_loading) const LinearProgressIndicator().paddingOnly(bottom: 12),
            if (_error != null) _errorCard(),
            _summaryCard(),
            _sectionCard('防火墙规则', Icons.security_outlined, _status),
            _sectionCard('监听端口', Icons.lan_outlined, _ports),
            _sectionCard('内网穿透', Icons.call_split_outlined, _tunnels),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return CardX(
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text(libL10n.error),
        subtitle: Text('$_error'),
      ),
    ).paddingOnly(bottom: 10);
  }

  Widget _summaryCard() {
    final hasUfw = _status.contains('Status: active') || _status.toLowerCase().contains('ufw');
    final hasFirewalld = _status.contains('running') || _status.toLowerCase().contains('firewalld');
    final hasPublicPorts = RegExp(r'\b(0\.0\.0\.0|::):').hasMatch(_ports) || _ports.contains('LISTEN');
    return CardX(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 18),
                UIs.width7,
                Text('运维摘要', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            UIs.height7,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(hasUfw ? 'UFW 已检测' : 'UFW 未确认', hasUfw),
                _chip(hasFirewalld ? 'Firewalld 已检测' : 'Firewalld 未确认', hasFirewalld),
                _chip(hasPublicPorts ? '存在监听端口' : '未发现监听端口', hasPublicPorts),
              ],
            ),
            UIs.height7,
            Text(
              '本页面只执行只读巡检。新增/删除规则、开放端口、重启防火墙等操作请进入终端确认后执行。',
              style: UIs.text13Grey,
            ),
          ],
        ),
      ),
    ).paddingOnly(bottom: 10);
  }

  Widget _chip(String text, bool active) {
    return Chip(
      avatar: Icon(active ? Icons.check_circle : Icons.info_outline, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _sectionCard(String title, IconData icon, String body) {
    return CardX(
      child: ExpansionTile(
        initiallyExpanded: title == '防火墙规则',
        leading: Icon(icon, size: 18),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              body.trim().isEmpty ? '无输出或系统未安装对应工具。' : body,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    ).paddingOnly(bottom: 10);
  }

  void _openFirewallShell() {
    final args = SshPageArgs(
      spi: widget.args.spi,
      initCmd: widget.args.spi.isRoot ? 'ufw status verbose || firewall-cmd --list-all || nft list ruleset' : 'sudo ufw status verbose || sudo firewall-cmd --list-all || sudo nft list ruleset',
    );
    SSHPage.route.go(context, args);
  }
}

const _firewallCmd = '''
printf '=== ufw ===\n'; (ufw status verbose 2>/dev/null || true)
printf '\n=== firewalld ===\n'; (firewall-cmd --state 2>/dev/null && firewall-cmd --list-all 2>/dev/null || true)
printf '\n=== nftables ===\n'; (nft list ruleset 2>/dev/null | head -160 || true)
printf '\n=== iptables ===\n'; (iptables -S 2>/dev/null | head -160 || true)
''';

const _portsCmd = '''
(ss -tulpen 2>/dev/null || netstat -tulpen 2>/dev/null || lsof -i -P -n 2>/dev/null || true)
''';

const _tunnelsCmd = '''
printf '=== tunnel processes ===\n'; ps aux | grep -Ei 'frpc|frps|ngrok|cloudflared|tailscale|zerotier|wireguard|wg-quick' | grep -v grep || true
printf '\n=== tunnel services ===\n'; (systemctl list-units --type=service --all 2>/dev/null | grep -Ei 'frpc|frps|ngrok|cloudflared|tailscale|zerotier|wireguard|wg-quick' || true)
printf '\n=== tunnel ports ===\n'; (ss -tulpen 2>/dev/null | grep -Ei 'frpc|frps|ngrok|cloudflared|tailscale|zerotier|wireguard|:7000|:7500|:7844|:51820' || true)
''';
