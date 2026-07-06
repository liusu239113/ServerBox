/// Surlor AI - Agent engine
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart';
import 'package:surlor_ai/core/utils/shell_quote.dart';
import 'package:surlor_ai/data/helper/gen_ssh.dart';
import 'package:surlor_ai/data/model/ai/agent_tools.dart';
import 'package:surlor_ai/data/provider/ai/ask_ai.dart';
import 'package:surlor_ai/data/provider/ai/mcp_runtime_service.dart';

// Agent events
sealed class AgentEvent {
  const AgentEvent();
}

class AgentThinking extends AgentEvent {
  final String delta;
  const AgentThinking(this.delta);
}

class AgentToolCall extends AgentEvent {
  final String toolName;
  final Map<String, dynamic> arguments;
  const AgentToolCall(this.toolName, this.arguments);
}

class AgentToolResult extends AgentEvent {
  final String toolName;
  final String result;
  final bool success;
  const AgentToolResult(this.toolName, this.result, this.success);
}

class AgentNeedConfirm extends AgentEvent {
  final String toolName;
  final Map<String, dynamic> arguments;
  final String reason;
  final completer = Completer<bool>();
  AgentNeedConfirm(this.toolName, this.arguments, this.reason);
}

class AgentCompleted extends AgentEvent {
  final String fullResponse;
  const AgentCompleted(this.fullResponse);
}

class AgentError extends AgentEvent {
  final String message;
  final Object? error;
  const AgentError(this.message, [this.error]);
}

@immutable
class AgentConversationMessage {
  const AgentConversationMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class _ToolRes {
  final String out;
  final bool ok;
  const _ToolRes(this.out, this.ok);
}

/// Agent service
class AgentService {
  final _repo = AskAiRepository();
  String? _activeWorkspacePath;

  Stream<AgentEvent> run({
    required String userMessage,
    required Spi? spi,
    List<Spi> availableServers = const [],
    List<AgentConversationMessage> history = const [],
    String? attachmentContext,
    List<String> imageDataUrls = const [],
    String? workspacePath,
    Future<bool> Function(String, Map<String, dynamic>, String)? onConfirm,
    int maxTurns = 10,
    String? model,
    String? baseUrl,
    String? apiKey,
    bool enableTools = true,
    List<Map<String, dynamic>> extraTools = const [],
  }) async* {
    _activeWorkspacePath = (workspacePath ?? '').trim().isEmpty ? null : workspacePath!.trim();
    final conv = <Map<String, dynamic>>[];
    conv.add({'role': 'system', 'content': agentSystemPrompt});
    conv.add({
      'role': 'system',
      'content': _buildServerContext(spi, availableServers),
    });
    conv.add({'role': 'system', 'content': _buildLocalFileContext()});
    if ((attachmentContext ?? '').trim().isNotEmpty) {
      conv.add({
        'role': 'system',
        'content': '用户上传/附加的参考内容如下，回答时可以结合它：\n$attachmentContext',
      });
    }
    for (final item in history) {
      final role = item.role == 'assistant' ? 'assistant' : 'user';
      final content = item.content.trim();
      if (content.isEmpty) continue;
      conv.add({'role': role, 'content': content});
    }
    if (imageDataUrls.isEmpty) {
      conv.add({'role': 'user', 'content': userMessage});
    } else {
      conv.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': userMessage},
          for (final url in imageDataUrls)
            {
              'type': 'image_url',
              'image_url': {'url': url},
            },
        ],
      });
    }

    var turn = 0;
    while (turn < maxTurns) {
      turn++;
      try {
        var requestedTool = false;
        final toolEvents = <AgentEvent>[];
        await for (final ev in _repo.askWithTools(
          conversation: conv,
          model: model,
          baseUrl: baseUrl,
          apiKey: apiKey,
          enableTools: enableTools,
          extraTools: extraTools,
          onToolCall: (name, args) async {
            requestedTool = true;
            final d = _checkDanger(name, args);
            toolEvents.add(AgentToolCall(name, args));
            if (d != 'safe' && onConfirm != null) {
              if (!await onConfirm(name, args, d)) {
                toolEvents.add(AgentToolResult(name, '用户取消了操作。', false));
                return '{"error":"cancelled by user"}';
              }
            }
            final r = await _runTool(name, args, spi);
            toolEvents.add(AgentToolResult(name, r.out, r.ok));
            return r.out;
          },
        )) {
          if (ev is AgentInnerThink) {
            yield AgentThinking(ev.delta);
          } else if (ev is AgentInnerDone) {
            for (final event in toolEvents) {
              yield event;
            }
            toolEvents.clear();
            if (ev.toolResults.isNotEmpty || requestedTool) {
              conv.add({'role': 'assistant', 'content': ev.text});
              conv.add({
                'role': 'user',
                'content': 'Tool results:\n${ev.toolResults.join('\n---\n')}\n请基于工具结果继续回答用户。',
              });
              break;
            } else {
              yield AgentCompleted(ev.text);
              return;
            }
          } else if (ev is AgentInnerErr) {
            yield AgentError(ev.msg, ev.err);
            return;
          }
        }
      } catch (e) {
        yield AgentError('Turn $turn error: $e', e);
        return;
      }
    }
    yield AgentError('工具调用轮次过多，已停止。');
  }

  String _buildServerContext(Spi? current, List<Spi> servers) {
    final buf = StringBuffer();
    if (servers.isEmpty) {
      buf.writeln('当前 App 还没有配置任何服务器。');
      buf.writeln('如果用户要求操作服务器，请提示先在服务器页添加服务器。');
      return buf.toString();
    }
    buf.writeln('App 中已配置的服务器列表：');
    for (var i = 0; i < servers.length; i++) {
      final s = servers[i];
      final selected = current?.id == s.id ? '（当前选中）' : '';
      buf.writeln(
        '${i + 1}. $selected name=${s.name}, id=${s.id}, host=${s.user}@${s.ip}:${s.port}',
      );
    }
    if (current == null) {
      buf.writeln('当前没有选中服务器。需要执行 SSH 工具时，请让用户先在对话界面选择目标服务器。');
    } else {
      buf.writeln('当前默认操作服务器：${current.name} (${current.user}@${current.ip}:${current.port})。');
      buf.writeln('除非用户明确要求其它服务器，否则工具调用都作用于当前默认服务器。');
    }
    return buf.toString();
  }

  String _buildLocalFileContext() {
    return '手机/App 本地文件默认工作目录：${_localRoot.path}\n'
        '当用户说“手机文件”“本地文件”“App 文件”时，优先使用 local_* 工具。\n'
        '相对路径会解析到默认工作目录下；绝对路径只有在系统允许访问时才可操作。';
  }

  Future<_ToolRes> _runTool(
    String name,
    Map<String, dynamic> args,
    Spi? spi,
  ) async {
    try {
      if (McpRuntimeService.instance.hasTool(name)) {
        final out = await McpRuntimeService.instance.callTool(name, args);
        return _ToolRes(out, true);
      }
      if (_isLocalTool(name)) {
        return switch (name) {
          'local_list_directory' => await _localList(args),
          'local_read_file' => await _localRead(args),
          'local_write_file' => await _localWrite(args),
          'local_create_directory' => await _localCreateDirectory(args),
          'local_delete_path' => await _localDelete(args),
          _ => _ToolRes('Unknown local tool: $name', false),
        };
      }
      if (spi == null) return const _ToolRes('Error: no selected server', false);
      return switch (name) {
        'run_command' => await _cmd(spi, args),
        'read_file' => await _read(spi, args),
        'write_file' => await _write(spi, args),
        'list_directory' => await _list(spi, args),
        'system_status' => await _status(spi),
        'process_list' => await _proc(spi, args),
        'docker_status' => await _docker(spi),
        'service_status' => await _svc(spi, args),
        'firewall_status' => await _firewall(spi),
        'port_list' => await _ports(spi, args),
        'network_status' => await _network(spi),
        'disk_usage' => await _diskUsage(spi, args),
        'tunnel_status' => await _tunnel(spi),
        _ => _ToolRes('Unknown: $name', false),
      };
    } catch (e) {
      return _ToolRes('$e', false);
    }
  }

  Future<_ToolRes> _cmd(Spi spi, Map<String, dynamic> args) async {
    final c = args['command'] as String? ?? '';
    if (c.isEmpty) return const _ToolRes('Error: empty command', false);
    final client = await genClient(spi);
    try {
      final o = await client.execForOutput(c, stderr: true);
      return _ToolRes(o.trim(), true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _read(Spi spi, Map<String, dynamic> args) async {
    final p = args['path'] as String? ?? '';
    if (p.isEmpty) return const _ToolRes('Error: empty path', false);
    final client = await genClient(spi);
    try {
      final o = await client.execForOutput('cat ${shellSingleQuote(p)}');
      return _ToolRes(o, true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _write(Spi spi, Map<String, dynamic> args) async {
    final p = args['path'] as String? ?? '';
    final c = args['content'] as String? ?? '';
    if (p.isEmpty) return const _ToolRes('Error: empty path', false);
    final client = await genClient(spi);
    try {
      final b = base64Encode(utf8.encode(c));
      await client.execForOutput(
        'printf %s ${shellSingleQuote(b)} | base64 -d > ${shellSingleQuote(p)}',
      );
      return _ToolRes('Written: $p', true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _list(Spi spi, Map<String, dynamic> args) async {
    final p = args['path'] as String? ?? '.';
    final showHidden = args['show_hidden'] == true;
    final client = await genClient(spi);
    try {
      final flag = showHidden ? '-la' : '-l';
      final o = await client.execForOutput('ls $flag ${shellSingleQuote(p)}');
      return _ToolRes(o, true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _status(Spi spi) async {
    final client = await genClient(spi);
    try {
      final c = await client.execForOutput('cat /proc/loadavg || uptime');
      final m = await client.execForOutput('cat /proc/meminfo | head -10');
      final d = await client.execForOutput('df -h');
      return _ToolRes('=== CPU ===\n$c\n=== MEM ===\n$m\n=== DISK ===\n$d', true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _proc(Spi spi, Map<String, dynamic> args) async {
    final filter = (args['filter'] as String? ?? '').trim();
    final sortBy = args['sort_by'] as String? ?? 'cpu';
    final sort = switch (sortBy) {
      'memory' => '-%mem',
      'pid' => 'pid',
      _ => '-%cpu',
    };
    final cmd = filter.isEmpty
        ? 'ps aux --sort=$sort | head -30'
        : 'ps aux --sort=$sort | grep -i -- ${shellSingleQuote(filter)} | grep -v grep | head -30';
    final client = await genClient(spi);
    try {
      final o = await client.execForOutput(cmd);
      return _ToolRes(o, true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _docker(Spi spi) async {
    final client = await genClient(spi);
    try {
      await client.execForOutput('which docker');
      final o = await client.execForOutput('docker ps -a');
      return _ToolRes(o, true);
    } catch (_) {
      return const _ToolRes('Docker not installed', false);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _svc(Spi spi, Map<String, dynamic> args) async {
    final s = (args['service_name'] as String? ?? '').trim();
    final client = await genClient(spi);
    try {
      final o = s.isEmpty
          ? await client.execForOutput(
              'systemctl list-units --type=service --state=running | head -30',
            )
          : await client.execForOutput('systemctl status ${shellSingleQuote(s)}');
      return _ToolRes(o, true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _firewall(Spi spi) async {
    final client = await genClient(spi);
    try {
      final o = await client.execForOutput('''
printf '=== ufw ===\n'; (ufw status verbose 2>/dev/null || true)
printf '\n=== firewalld ===\n'; (firewall-cmd --state 2>/dev/null && firewall-cmd --list-all 2>/dev/null || true)
printf '\n=== nftables ===\n'; (nft list ruleset 2>/dev/null | head -120 || true)
printf '\n=== iptables ===\n'; (iptables -S 2>/dev/null | head -120 || true)
''', stderr: true);
      return _ToolRes(o.trim(), true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _ports(Spi spi, Map<String, dynamic> args) async {
    final filter = (args['filter'] as String? ?? '').trim();
    final client = await genClient(spi);
    try {
      final base = '(ss -tulpen 2>/dev/null || netstat -tulpen 2>/dev/null || lsof -i -P -n 2>/dev/null)';
      final cmd = filter.isEmpty ? base : '$base | grep -i -- ${shellSingleQuote(filter)}';
      final o = await client.execForOutput(cmd, stderr: true);
      return _ToolRes(o.trim(), true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _network(Spi spi) async {
    final client = await genClient(spi);
    try {
      final o = await client.execForOutput('''
printf '=== ip addr ===\n'; (ip -brief addr 2>/dev/null || ifconfig 2>/dev/null || true)
printf '\n=== route ===\n'; (ip route 2>/dev/null || route -n 2>/dev/null || true)
printf '\n=== dns ===\n'; (cat /etc/resolv.conf 2>/dev/null || true)
printf '\n=== connections summary ===\n'; (ss -ant state established 2>/dev/null | awk 'NR>1 {print $1}' | sort | uniq -c || true)
''', stderr: true);
      return _ToolRes(o.trim(), true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _diskUsage(Spi spi, Map<String, dynamic> args) async {
    final rawPath = (args['path'] as String? ?? '/').trim();
    final path = rawPath.isEmpty ? '/' : rawPath;
    final depth = args['depth'] is int ? args['depth'] as int : 1;
    final safeDepth = depth.clamp(0, 3);
    final client = await genClient(spi);
    try {
      final o = await client.execForOutput(
        'printf "=== df ===\\n"; df -h ${shellSingleQuote(path)} 2>/dev/null; '
        'printf "\\n=== du top ===\\n"; du -h -d $safeDepth ${shellSingleQuote(path)} 2>/dev/null | sort -hr | head -50',
        stderr: true,
      );
      return _ToolRes(o.trim(), true);
    } finally {
      client.close();
    }
  }

  Future<_ToolRes> _tunnel(Spi spi) async {
    final client = await genClient(spi);
    try {
      final o = await client.execForOutput('''
printf '=== tunnel processes ===\n'; ps aux | grep -Ei 'frpc|frps|ngrok|cloudflared|tailscale|zerotier|wireguard|wg-quick' | grep -v grep || true
printf '\n=== tunnel services ===\n'; (systemctl list-units --type=service --all | grep -Ei 'frpc|frps|ngrok|cloudflared|tailscale|zerotier|wireguard|wg-quick' || true)
printf '\n=== tunnel ports ===\n'; (ss -tulpen 2>/dev/null | grep -Ei 'frpc|frps|ngrok|cloudflared|tailscale|zerotier|wireguard|:7000|:7500|:7844|:51820' || true)
''', stderr: true);
      return _ToolRes(o.trim(), true);
    } finally {
      client.close();
    }
  }

  Directory get _localRoot {
    final workspace = (_activeWorkspacePath ?? '').trim();
    if (workspace.isNotEmpty) return Directory(workspace);
    return Directory(Paths.file.joinPath('agent'));
  }

  bool _isLocalTool(String name) => name.startsWith('local_');

  bool _isAbsolutePath(String path) {
    if (path.startsWith(Pfs.seperator)) return true;
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
  }

  Future<String> _resolveLocalPath(String rawPath) async {
    final raw = rawPath.trim();
    final root = _localRoot;
    if (raw.isEmpty) {
      if (!await root.exists()) await root.create(recursive: true);
      return root.path;
    }
    if (_isAbsolutePath(raw)) return raw;

    final parts = <String>[];
    for (final part in raw.split(RegExp(r'[\\/]'))) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    if (!await root.exists()) await root.create(recursive: true);
    if (parts.isEmpty) return root.path;
    return root.path.joinPath(parts.join(Pfs.seperator));
  }

  String _localName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  Future<_ToolRes> _localList(Map<String, dynamic> args) async {
    final path = await _resolveLocalPath(args['path'] as String? ?? '');
    final showHidden = args['show_hidden'] == true;
    final dir = Directory(path);
    if (!await dir.exists()) return _ToolRes('Error: directory not found: $path', false);
    final items = await dir.list().toList();
    final rows = <String>[];
    for (final item in items) {
      final name = _localName(item.path);
      if (!showHidden && name.startsWith('.')) continue;
      final stat = await item.stat();
      final type = switch (stat.type) {
        FileSystemEntityType.directory => 'dir ',
        FileSystemEntityType.file => 'file',
        FileSystemEntityType.link => 'link',
        _ => 'item',
      };
      rows.add('$type\t${stat.size}\t${stat.modified.toIso8601String()}\t$name');
    }
    rows.sort();
    return _ToolRes('Path: $path\nType\tSize\tModified\tName\n${rows.join('\n')}', true);
  }

  Future<_ToolRes> _localRead(Map<String, dynamic> args) async {
    final path = await _resolveLocalPath(args['path'] as String? ?? '');
    if (path.isEmpty) return const _ToolRes('Error: empty path', false);
    final file = File(path);
    if (!await file.exists()) return _ToolRes('Error: file not found: $path', false);
    final maxChars = args['max_chars'] is int ? args['max_chars'] as int : 20000;
    final text = await file.readAsString();
    if (text.length <= maxChars) return _ToolRes(text, true);
    return _ToolRes('${text.substring(0, maxChars)}\n\n[已截断：$path，总字符数 ${text.length}]', true);
  }

  Future<_ToolRes> _localWrite(Map<String, dynamic> args) async {
    final path = await _resolveLocalPath(args['path'] as String? ?? '');
    final content = args['content'] as String? ?? '';
    if (path.isEmpty) return const _ToolRes('Error: empty path', false);
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content);
    return _ToolRes('Written local file: $path (${content.length} chars)', true);
  }

  Future<_ToolRes> _localCreateDirectory(Map<String, dynamic> args) async {
    final path = await _resolveLocalPath(args['path'] as String? ?? '');
    if (path.isEmpty) return const _ToolRes('Error: empty path', false);
    await Directory(path).create(recursive: true);
    return _ToolRes('Created local directory: $path', true);
  }

  Future<_ToolRes> _localDelete(Map<String, dynamic> args) async {
    final path = await _resolveLocalPath(args['path'] as String? ?? '');
    if (path.isEmpty) return const _ToolRes('Error: empty path', false);
    if (path == _localRoot.path) {
      return const _ToolRes('Error: refusing to delete Agent root directory', false);
    }
    final entityType = await FileSystemEntity.type(path);
    if (entityType == FileSystemEntityType.notFound) {
      return _ToolRes('Error: path not found: $path', false);
    }
    final recursive = args['recursive'] == true;
    if (entityType == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: recursive);
    } else {
      await File(path).delete();
    }
    return _ToolRes('Deleted local path: $path', true);
  }

  String _checkDanger(String name, Map<String, dynamic> args) {
    if (name == 'run_command') {
      final c = args['command'] as String? ?? '';
      return detectDangerLevel(c);
    }
    if (name == 'write_file') return 'warning';
    if (name == 'local_write_file') return 'warning';
    if (name == 'local_create_directory') return 'warning';
    if (name == 'local_delete_path') return 'dangerous';
    if (name.startsWith('mcp_')) {
      final lower = name.toLowerCase();
      if (lower.contains('delete') || lower.contains('remove') || lower.contains('_rm_')) {
        return 'dangerous';
      }
      if (lower.contains('write') ||
          lower.contains('create') ||
          lower.contains('edit') ||
          lower.contains('update')) {
        return 'warning';
      }
    }
    return 'safe';
  }
}
