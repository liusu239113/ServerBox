import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart';
import 'package:surlor_ai/core/chan.dart';

@immutable
class McpServerRuntimeConfig {
  const McpServerRuntimeConfig({
    required this.id,
    required this.name,
    required this.command,
    required this.args,
    required this.enabled,
  });

  final String id;
  final String name;
  final String command;
  final String args;
  final bool enabled;
}

@immutable
class McpServerStatus {
  const McpServerStatus({
    required this.id,
    required this.name,
    required this.enabled,
    required this.running,
    required this.message,
  });

  final String id;
  final String name;
  final bool enabled;
  final bool running;
  final String message;
}

@immutable
class McpToolDefinition {
  const McpToolDefinition({
    required this.serverId,
    required this.serverName,
    required this.name,
    required this.description,
    required this.schema,
  });

  final String serverId;
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> schema;

  String get agentToolName => 'mcp_${serverId}_$name'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

  Map<String, dynamic> toOpenAiTool() {
    return {
      'type': 'function',
      'function': {
        'name': agentToolName,
        'description': '[MCP:${serverName}] $description',
        'parameters': schema.isEmpty
            ? {'type': 'object', 'properties': {}, 'required': []}
            : schema,
      },
    };
  }
}

class McpRuntimeService {
  McpRuntimeService._();

  static final instance = McpRuntimeService._();

  final Map<String, _McpProcess> _processes = {};
  final Map<String, McpToolDefinition> _toolsByAgentName = {};
  final _statusController = StreamController<List<McpServerStatus>>.broadcast();

  Stream<List<McpServerStatus>> get statuses => _statusController.stream;

  List<McpServerStatus> snapshot() {
    return _processes.values.map((p) => p.status).toList();
  }

  List<Map<String, dynamic>> openAiTools() {
    return _toolsByAgentName.values.map((tool) => tool.toOpenAiTool()).toList();
  }

  bool hasTool(String toolName) => _toolsByAgentName.containsKey(toolName);

  Future<String> callTool(String toolName, Map<String, dynamic> arguments) async {
    final definition = _toolsByAgentName[toolName];
    if (definition == null) {
      return 'MCP tool not found: $toolName';
    }
    final process = _processes[definition.serverId];
    if (process == null || !process.running) {
      return 'MCP server not running: ${definition.serverName}';
    }
    final result = await process.request('tools/call', {
      'name': definition.name,
      'arguments': arguments,
    });
    return const JsonEncoder.withIndent('  ').convert(result);
  }

  Future<void> sync(List<McpServerRuntimeConfig> configs) async {
    if (isAndroid && configs.any((c) => c.enabled)) {
      MethodChans.startService(force: true);
    }
    final wantedIds = configs.where((c) => c.enabled).map((c) => c.id).toSet();
    final stale = _processes.keys.where((id) => !wantedIds.contains(id)).toList();
    for (final id in stale) {
      await _stop(id);
    }

    for (final config in configs) {
      if (!config.enabled) continue;
      final existing = _processes[config.id];
      if (existing != null && existing.matches(config)) continue;
      await _stop(config.id);
      await _start(config);
    }
    _emit();
  }

  Future<void> stopAll() async {
    final ids = _processes.keys.toList();
    for (final id in ids) {
      await _stop(id);
    }
    _emit();
  }

  Future<void> _start(McpServerRuntimeConfig config) async {
    if (config.command.trim() == 'builtin-filesystem') {
      final mcp = _McpProcess.builtinFilesystem(config);
      _processes[config.id] = mcp;
      await mcp.initialize();
      final tools = await mcp.listTools();
      _toolsByAgentName.removeWhere((_, tool) => tool.serverId == config.id);
      for (final tool in tools) {
        _toolsByAgentName[tool.agentToolName] = tool;
      }
      return;
    }

    final parsed = _parseCommand(config.command, config.args);
    if (parsed == null) {
      _processes[config.id] = _McpProcess.failed(config, 'Command 为空');
      return;
    }
    try {
      final process = await Process.start(
        parsed.command,
        parsed.args,
        runInShell: Platform.isWindows,
      );
      final mcp = _McpProcess(config, process);
      _processes[config.id] = mcp;
      await mcp.initialize();
      final tools = await mcp.listTools();
      _toolsByAgentName.removeWhere((_, tool) => tool.serverId == config.id);
      for (final tool in tools) {
        _toolsByAgentName[tool.agentToolName] = tool;
      }
    } catch (e, s) {
      Loggers.app.warning('Failed to start MCP server ${config.name}', e, s);
      _processes[config.id] = _McpProcess.failed(config, e.toString());
    }
  }

  Future<void> _stop(String id) async {
    _toolsByAgentName.removeWhere((_, tool) => tool.serverId == id);
    final process = _processes.remove(id);
    await process?.close();
  }

  _ParsedCommand? _parseCommand(String command, String args) {
    final cmd = command.trim();
    if (cmd.isEmpty) return null;
    return _ParsedCommand(cmd, _splitShellArgs(args));
  }

  List<String> _splitShellArgs(String input) {
    final args = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var escaping = false;

    void flush() {
      if (current.isEmpty) return;
      args.add(current.toString());
      current.clear();
    }

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (escaping) {
        current.write(ch);
        escaping = false;
        continue;
      }
      if (ch == r'\' && !inSingle) {
        escaping = true;
        continue;
      }
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
        continue;
      }
      if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (!inSingle && !inDouble && ch.trim().isEmpty) {
        flush();
        continue;
      }
      current.write(ch);
    }
    if (escaping) current.write(r'\');
    flush();
    return args;
  }

  void _emit() {
    if (_statusController.isClosed) return;
    _statusController.add(snapshot());
  }
}

class _ParsedCommand {
  const _ParsedCommand(this.command, this.args);

  final String command;
  final List<String> args;
}

class _McpProcess {
  _McpProcess(this.config, this.process)
      : _builtinFilesystemRoot = null,
        _status = McpServerStatus(
          id: config.id,
          name: config.name,
          enabled: config.enabled,
          running: true,
          message: '启动中',
        ) {
    final proc = process!;
    _stdoutSub = proc.stdout.listen(_onStdoutBytes);
    _stderrSub = proc.stderr.transform(utf8.decoder).listen((chunk) {
      _stderr.write(chunk);
      if (_stderr.length > 4000) {
        final text = _stderr.toString();
        _stderr
          ..clear()
          ..write(text.substring(text.length - 4000));
      }
    });
    proc.exitCode.then((code) {
      _closed = true;
      _status = McpServerStatus(
        id: config.id,
        name: config.name,
        enabled: config.enabled,
        running: false,
        message: '已退出：$code ${_stderr.toString().trim()}'.trim(),
      );
      McpRuntimeService.instance._emit();
    });
  }

  _McpProcess.failed(this.config, String message)
      : process = null,
        _builtinFilesystemRoot = null,
        _closed = true,
        _status = McpServerStatus(
          id: config.id,
          name: config.name,
          enabled: config.enabled,
          running: false,
          message: message,
        );

  _McpProcess.builtinFilesystem(this.config)
      : process = null,
        _builtinFilesystemRoot = _resolveBuiltinFilesystemRoot(config.args),
        _closed = false,
        _status = McpServerStatus(
          id: config.id,
          name: config.name,
          enabled: config.enabled,
          running: true,
          message: '内置文件系统 MCP 已启动',
        );

  final McpServerRuntimeConfig config;
  final Process? process;
  final Directory? _builtinFilesystemRoot;
  final StringBuffer _stderr = StringBuffer();
  final StringBuffer _lineBuffer = StringBuffer();
  final List<int> _stdoutBuffer = [];
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  int _nextId = 1;
  bool _closed = false;
  late McpServerStatus _status;

  McpServerStatus get status => _status;

  bool get running => !_closed && (process != null || _builtinFilesystemRoot != null);

  bool matches(McpServerRuntimeConfig next) {
    return config.command == next.command &&
        config.args == next.args &&
        config.name == next.name &&
        config.enabled == next.enabled &&
        running;
  }

  Future<void> initialize() async {
    final root = _builtinFilesystemRoot;
    if (root != null) {
      if (!await root.exists()) await root.create(recursive: true);
      _status = McpServerStatus(
        id: config.id,
        name: config.name,
        enabled: config.enabled,
        running: true,
        message: '内置文件系统 MCP 已启动：${root.path}',
      );
      return;
    }

    final result = await request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'Surlor AI Android', 'version': '1.0'},
    });
    notify('notifications/initialized', {});
    _status = McpServerStatus(
      id: config.id,
      name: config.name,
      enabled: config.enabled,
      running: true,
      message: '已启动 ${result['serverInfo'] ?? ''}'.trim(),
    );
  }

  Future<List<McpToolDefinition>> listTools() async {
    if (_builtinFilesystemRoot != null) {
      return [
        McpToolDefinition(
          serverId: config.id,
          serverName: config.name,
          name: 'list_directory',
          description: '列出用户选择的本地项目目录中的文件和文件夹。',
          schema: const {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': '相对项目根目录的路径，空值表示根目录'},
              'show_hidden': {'type': 'boolean', 'description': '是否显示隐藏文件'},
            },
            'required': [],
          },
        ),
        McpToolDefinition(
          serverId: config.id,
          serverName: config.name,
          name: 'read_file',
          description: '读取用户选择的本地项目目录中的文本文件。',
          schema: const {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': '相对项目根目录的文件路径'},
              'max_chars': {'type': 'integer', 'description': '最多读取字符数，默认 20000'},
            },
            'required': ['path'],
          },
        ),
        McpToolDefinition(
          serverId: config.id,
          serverName: config.name,
          name: 'write_file',
          description: '写入用户选择的本地项目目录中的文本文件，会覆盖已有内容。',
          schema: const {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': '相对项目根目录的文件路径'},
              'content': {'type': 'string', 'description': '要写入的文本内容'},
            },
            'required': ['path', 'content'],
          },
        ),
      ];
    }

    final result = await request('tools/list', {});
    final rawTools = result['tools'];
    if (rawTools is! List) return const [];
    return rawTools.whereType<Map>().map((raw) {
      final map = Map<String, dynamic>.from(raw);
      final schema = map['inputSchema'];
      return McpToolDefinition(
        serverId: config.id,
        serverName: config.name,
        name: map['name'] as String? ?? 'tool',
        description: map['description'] as String? ?? 'MCP tool',
        schema: schema is Map ? Map<String, dynamic>.from(schema) : const {},
      );
    }).toList();
  }

  Future<Map<String, dynamic>> request(String method, Map<String, dynamic> params) async {
    final root = _builtinFilesystemRoot;
    if (root != null) {
      return _builtinRequest(root, method, params);
    }

    final proc = process;
    if (proc == null || _closed) {
      throw StateError('MCP server is not running');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params.isNotEmpty) 'params': params,
    };
    final encoded = jsonEncode(payload);
    final bytes = utf8.encode(encoded);
    proc.stdin.add(utf8.encode('Content-Length: ${bytes.length}\r\n\r\n'));
    proc.stdin.add(bytes);
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('MCP request timeout: $method');
      },
    );
  }

  Future<Map<String, dynamic>> _builtinRequest(
    Directory root,
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_closed) throw StateError('MCP server is not running');
    if (method == 'initialize') {
      return {
        'serverInfo': {'name': config.name, 'version': 'builtin'},
        'capabilities': {'tools': {}},
      };
    }
    if (method == 'tools/list') {
      return {'tools': [for (final tool in await listTools()) {'name': tool.name, 'description': tool.description, 'inputSchema': tool.schema}]};
    }
    if (method != 'tools/call') {
      return {'error': 'Unsupported builtin MCP method: $method'};
    }
    final toolName = params['name'] as String? ?? '';
    final arguments = params['arguments'];
    final args = arguments is Map ? Map<String, dynamic>.from(arguments) : <String, dynamic>{};
    return switch (toolName) {
      'list_directory' => await _builtinList(root, args),
      'read_file' => await _builtinRead(root, args),
      'write_file' => await _builtinWrite(root, args),
      _ => {'error': 'Unknown builtin MCP tool: $toolName'},
    };
  }

  Future<Map<String, dynamic>> _builtinList(Directory root, Map<String, dynamic> args) async {
    final path = await _resolveBuiltinPath(root, args['path'] as String? ?? '');
    final dir = Directory(path);
    if (!await dir.exists()) return {'error': 'directory not found: $path'};
    final showHidden = args['show_hidden'] == true;
    final rows = <Map<String, dynamic>>[];
    await for (final entity in dir.list()) {
      final name = _basename(entity.path);
      if (!showHidden && name.startsWith('.')) continue;
      final stat = await entity.stat();
      rows.add({
        'name': name,
        'path': entity.path,
        'type': stat.type.name,
        'size': stat.size,
        'modified': stat.modified.toIso8601String(),
      });
    }
    rows.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return {'root': root.path, 'path': path, 'items': rows};
  }

  Future<Map<String, dynamic>> _builtinRead(Directory root, Map<String, dynamic> args) async {
    final path = await _resolveBuiltinPath(root, args['path'] as String? ?? '');
    final file = File(path);
    if (!await file.exists()) return {'error': 'file not found: $path'};
    final maxChars = args['max_chars'] is int ? args['max_chars'] as int : 20000;
    final text = await file.readAsString();
    return {
      'path': path,
      'content': text.length <= maxChars ? text : text.substring(0, maxChars),
      'truncated': text.length > maxChars,
      'total_chars': text.length,
    };
  }

  Future<Map<String, dynamic>> _builtinWrite(Directory root, Map<String, dynamic> args) async {
    final path = await _resolveBuiltinPath(root, args['path'] as String? ?? '');
    final content = args['content'] as String? ?? '';
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content);
    return {'path': path, 'written_chars': content.length};
  }

  Future<String> _resolveBuiltinPath(Directory root, String rawPath) async {
    if (!await root.exists()) await root.create(recursive: true);
    final raw = rawPath.trim();
    if (raw.isEmpty || raw == '.') return root.path;
    final parts = <String>[];
    for (final part in raw.split(RegExp(r'[\\/]'))) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    if (parts.isEmpty) return root.path;
    return root.path.joinPath(parts.join(Pfs.seperator));
  }

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

  void notify(String method, Map<String, dynamic> params) {
    final proc = process;
    if (proc == null || _closed) return;
    final payload = {
      'jsonrpc': '2.0',
      'method': method,
      if (params.isNotEmpty) 'params': params,
    };
    final encoded = jsonEncode(payload);
    final bytes = utf8.encode(encoded);
    proc.stdin.add(utf8.encode('Content-Length: ${bytes.length}\r\n\r\n'));
    proc.stdin.add(bytes);
  }

  void _onStdoutBytes(List<int> bytes) {
    _stdoutBuffer.addAll(bytes);
    while (true) {
      final headerEnd = _findHeaderEnd(_stdoutBuffer);
      if (headerEnd < 0) {
        final text = utf8.decode(_stdoutBuffer, allowMalformed: true);
        if (text.toLowerCase().startsWith('content-length:') || !text.contains('\n')) {
          return;
        }
        _drainLineDelimitedJson();
        return;
      }
      final header = utf8.decode(_stdoutBuffer.sublist(0, headerEnd));
      final match = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(header);
      if (match == null) {
        _stdoutBuffer.removeRange(0, headerEnd + 4);
        _drainLineDelimitedJson();
        continue;
      }
      final length = int.tryParse(match.group(1) ?? '');
      if (length == null) {
        _stdoutBuffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + length;
      if (_stdoutBuffer.length < bodyEnd) return;
      final body = utf8.decode(_stdoutBuffer.sublist(bodyStart, bodyEnd));
      _stdoutBuffer.removeRange(0, bodyEnd);
      _handleJsonMessage(body);
    }
  }

  int _findHeaderEnd(List<int> bytes) {
    for (var i = 0; i <= bytes.length - 4; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  void _drainLineDelimitedJson() {
    if (_stdoutBuffer.isEmpty) return;
    final text = utf8.decode(_stdoutBuffer, allowMalformed: true);
    final lines = text.split('\n');
    _stdoutBuffer.clear();
    if (!text.endsWith('\n')) {
      _lineBuffer.write(lines.removeLast());
    }
    for (final line in lines) {
      final full = '${_lineBuffer.toString()}$line';
      _lineBuffer.clear();
      _handleJsonMessage(full);
    }
  }

  void _handleJsonMessage(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = json['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final error = json['error'];
    if (error != null) {
      completer.completeError(Exception(error.toString()));
      return;
    }
    final result = json['result'];
    completer.complete(result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{});
  }

  Future<void> close() async {
    _closed = true;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(StateError('MCP server stopped'));
    }
    _pending.clear();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    process?.kill();
  }

  static Directory _resolveBuiltinFilesystemRoot(String args) {
    final trimmed = args.trim();
    if (trimmed.isEmpty || trimmed == '<workspace>') {
      return Directory(Paths.file.joinPath('agent'));
    }
    return Directory(trimmed);
  }
}
