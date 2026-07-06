/// Surlor AI - Agent engine
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:surlor_ai/data/model/ai/agent_tools.dart';
import 'package:surlor_ai/data/provider/ai/ask_ai.dart';
import 'package:surlor_ai/data/helper/gen_ssh.dart';

// Agent events
sealed class AgentEvent { const AgentEvent(); }

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

class _ToolRes { final String out; final bool ok; const _ToolRes(this.out, this.ok); }

/// Agent service
class AgentService {
  final _repo = AskAiRepository();

  Stream<AgentEvent> run({
    required String userMessage,
    required Spi? spi,
    Future<bool> Function(String, Map<String, dynamic>, String)? onConfirm,
    int maxTurns = 10,
    String? model,
    String? baseUrl,
    String? apiKey,
  }) async* {
    final conv = <Map<String, String>>[];
    conv.add({'role': 'system', 'content': agentSystemPrompt});
    if (spi != null) {
      conv.add({'role': 'system', 'content': 'Server: ${spi.name}\nIP: ${spi.ip}:${spi.port}\nUser: ${spi.user}'});
    }
    conv.add({'role': 'user', 'content': userMessage});

    var turn = 0;
    while (turn < maxTurns) {
      turn++;
      try {
        await for (final ev in _repo.askWithTools(
          conversation: conv,
          model: model,
          baseUrl: baseUrl,
          apiKey: apiKey,
          onToolCall: (name, args) async {
            final d = _checkDanger(name, args);
            if (d != 'safe' && onConfirm != null) {
              if (!await onConfirm(name, args, d)) {
                return '{"error": "cancelled"}';
              }
            }
            final r = await _runTool(name, args, spi);
            return r.out;
          },
        )) {
          if (ev is AgentInnerThink) { yield AgentThinking(ev.delta); }
          else if (ev is AgentInnerDone) {
            if (ev.toolResults.isNotEmpty) {
              conv.add({'role': 'assistant', 'content': ev.text});
              conv.add({'role': 'user', 'content': 'Tool results:\n${ev.toolResults.join('\n---\n')}\nContinue.'});
              break;
            } else {
              yield AgentCompleted(ev.text);
              return;
            }
          }
          else if (ev is AgentInnerErr) { yield AgentError(ev.msg, ev.err); return; }
        }
      } catch (e, s) { yield AgentError('Turn $turn error: $e', e); return; }
    }
    yield AgentError('Max turns reached', null);
  }

  Future<_ToolRes> _runTool(String name, Map<String, dynamic> args, Spi? spi) async {
    if (spi == null) return _ToolRes('Error: no server', false);
    try {
      return switch (name) {
        'run_command' => await _cmd(spi, args),
        'read_file' => await _read(spi, args),
        'write_file' => await _write(spi, args),
        'list_directory' => await _list(spi, args),
        'system_status' => await _status(spi),
        'process_list' => await _proc(spi, args),
        'docker_status' => await _docker(spi),
        'service_status' => await _svc(spi, args),
        _ => _ToolRes('Unknown: $name', false),
      };
    } catch (e) { return _ToolRes('$e', false); }
  }

  Future<_ToolRes> _cmd(Spi spi, Map<String, dynamic> args) async {
    final c = args['command'] as String? ?? '';
    if (c.isEmpty) return _ToolRes('Error: empty command', false);
    final client = await genClient(spi);
    try { final o = await client.execForOutput(c, stderr: true); return _ToolRes(o.trim(), true); }
    finally { client.close(); }
  }

  Future<_ToolRes> _read(Spi spi, Map<String, dynamic> args) async {
    final p = args['path'] as String? ?? '';
    if (p.isEmpty) return _ToolRes('Error: empty path', false);
    final client = await genClient(spi);
    try { final o = await client.execForOutput('cat "$p"'); return _ToolRes(o, true); }
    finally { client.close(); }
  }

  Future<_ToolRes> _write(Spi spi, Map<String, dynamic> args) async {
    final p = args['path'] as String? ?? '';
    final c = args['content'] as String? ?? '';
    if (p.isEmpty) return _ToolRes('Error: empty path', false);
    final client = await genClient(spi);
    try {
      final b = base64Encode(utf8.encode(c));
      await client.execForOutput("echo '$b' | base64 -d > '$p'");
      return _ToolRes('Written: $p', true);
    } finally { client.close(); }
  }

  Future<_ToolRes> _list(Spi spi, Map<String, dynamic> args) async {
    final p = args['path'] as String? ?? '.';
    final client = await genClient(spi);
    try { final o = await client.execForOutput('ls -la "$p"'); return _ToolRes(o, true); }
    finally { client.close(); }
  }

  Future<_ToolRes> _status(Spi spi) async {
    final client = await genClient(spi);
    try {
      final c = await client.execForOutput('cat /proc/loadavg || uptime');
      final m = await client.execForOutput('cat /proc/meminfo | head -10');
      final d = await client.execForOutput('df -h');
      return _ToolRes('=== CPU ===\n$c\n=== MEM ===\n$m\n=== DISK ===\n$d', true);
    } finally { client.close(); }
  }

  Future<_ToolRes> _proc(Spi spi, Map<String, dynamic> args) async {
    final client = await genClient(spi);
    try { final o = await client.execForOutput('ps aux --sort=-%cpu | head -20'); return _ToolRes(o, true); }
    finally { client.close(); }
  }

  Future<_ToolRes> _docker(Spi spi) async {
    final client = await genClient(spi);
    try {
      await client.execForOutput('which docker');
      final o = await client.execForOutput('docker ps -a');
      return _ToolRes(o, true);
    } catch (_) { return _ToolRes('Docker not installed', false); }
    finally { client.close(); }
  }

  Future<_ToolRes> _svc(Spi spi, Map<String, dynamic> args) async {
    final s = args['service_name'] as String? ?? '';
    final client = await genClient(spi);
    try {
      final o = s.isEmpty ? await client.execForOutput('systemctl list-units --type=service --state=running | head -20')
                       : await client.execForOutput('systemctl status $s');
      return _ToolRes(o, true);
    } finally { client.close(); }
  }

  String _checkDanger(String name, Map<String, dynamic> args) {
    if (name == 'run_command' || name == 'write_file') {
      final c = (args['command'] ?? args['path'] ?? '') as String;
      return detectDangerLevel(c);
    }
    return 'safe';
  }
}
