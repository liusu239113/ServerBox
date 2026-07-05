/// Surlor AI Agent 工具定义
///
/// 定义 Agent 可以执行的所有操作（工具），
/// 遵循 OpenAI function calling 格式。
library;

/// Agent 可用的工具类型
enum AiToolType {
  /// 执行 SSH 命令并返回结果
  runCommand,

  /// 读取服务器文件内容
  readFile,

  /// 写入/创建服务器文件
  writeFile,

  /// 列出目录内容
  listDir,

  /// 获取系统状态概览 (CPU, 内存, 磁盘等)
  getSystemStatus,

  /// 获取进程列表
  getProcessList,

  /// 获取 Docker 状态 (如果有)
  getDockerStatus,

  /// 获取 systemd 服务状态
  getServiceStatus,
}

// ──────────────────── 内置工具定义（OpenAI function calling 格式）───────────────────

/// 所有 Agent 可用工具的定义
const List<Map<String, dynamic>> builtinAgentTools = [
  // 1. 执行命令
  {
    "type": "function",
    "function": {
      "name": "run_command",
      "description": "在服务器上执行 Shell 命令并返回输出结果。"
          "用于获取系统信息、管理服务、操作文件等。"
          "注意：修改性命令（rm、shutdown、apt install 等）需要用户确认。",
      "parameters": {
        "type": "object",
        "required": ["command"],
        "properties": {
          "command": {
            "type": "string",
            "description": "要执行的完整 Shell 命令",
          },
          "description": {
            "type": "string",
            "description": "简要说明这个命令要做什么",
          },
          "danger_level": {
            "type": "string",
            "enum": ["safe", "warning", "dangerous"],
            "description": "操作危险等级。"
                "safe: 只读操作。"
                "warning: 可能影响系统。"
                "dangerous: 破坏性操作。",
          },
        },
      },
    },
  },

  // 2. 读取文件
  {
    "type": "function",
    "function": {
      "name": "read_file",
      "description": "读取服务器上的文本文件内容",
      "parameters": {
        "type": "object",
        "required": ["path"],
        "properties": {
          "path": {"type": "string", "description": "文件的绝对路径"},
          "max_lines": {
            "type": "integer",
            "description": "最多读取行数，默认 200",
          },
        },
      },
    },
  },

  // 3. 写入文件
  {
    "type": "function",
    "function": {
      "name": "write_file",
      "description": "在服务器上写入或创建文本文件。会覆盖已有内容。",
      "parameters": {
        "type": "object",
        "required": ["path", "content"],
        "properties": {
          "path": {"type": "string", "description": "要写入的文件路径"},
          "content": {"type": "string", "description": "要写入的完整内容"},
          "description": {
            "type": "string",
            "description": "说明写入目的和内容摘要",
          },
        },
      },
    },
  },

  // 4. 列出目录
  {
    "type": "function",
    "function": {
      "name": "list_directory",
      "description": "列出指定目录下的文件和子目录",
      "parameters": {
        "type": "object",
        "required": ["path"],
        "properties": {
          "path": {"type": "string", "description": "目录路径"},
          "show_hidden": {
            "type": "boolean",
            "description": "是否显示隐藏文件",
          },
        },
      },
    },
  },

  // 5. 系统状态总览
  {
    "type": "function",
    "function": {
      "name": "system_status",
      "description":
          "获取服务器整体运行状态：CPU、内存、磁盘、网络、负载、运行时间",
      "parameters": {
        "type": "object",
        "required": [],
        "properties": {},
      },
    },
  },

  // 6. 进程列表
  {
    "type": "function",
    "function": {
      "name": "process_list",
      "description": "获取服务器进程列表",
      "parameters": {
        "type": "object",
        "required": [],
        "properties": {
          "filter": {"type": "string", "description": "按进程名过滤"},
          "sort_by": {
            "type": "string",
            "enum": ["cpu", "memory", "pid"],
          },
        },
      },
    },
  },

  // 7. Docker 状态
  {
    "type": "function",
    "function": {
      "name": "docker_status",
      "description": "获取 Docker 容器和镜像状态",
      "parameters": {
        "type": "object",
        "required": [],
        "properties": {},
      },
    },
  },

  // 8. Systemd 服务
  {
    "type": "function",
    "function": {
      "name": "service_status",
      "description": "查询 systemd 服务状态",
      "parameters": {
        "type": "object",
        "required": [],
        "properties": {
          "service_name": {"type": "string", "description": "服务名"},
        },
      },
    },
  },
];

/// Agent 系统提示词（中文优化）
const String agentSystemPrompt = '''你是 Surlor AI，一个专业的服务器运维智能助手。

## 核心能力
- 通过 SSH 连接服务器，执行命令、读写文件
- 监控服务器状态（CPU、内存、磁盘、进程、Docker 等）
- 帮助排查问题、优化配置、自动化运维

## 工作原则
1. **先了解再行动**：遇到问题时，先收集信息再给出方案
2. **安全第一**：破坏性操作前必须说明风险并获得用户确认
3. **解释清晰**：每个操作都告诉用户你在做什么、为什么这样做
4. **分步进行**：复杂任务拆解为多个步骤，每步确认后再继续

## 响应风格
- 使用简洁的中文
- 重要信息用表格或列表呈现
- 命令和配置用 markdown 代码块包裹
''';

/// 根据命令判断危险级别
String detectDangerLevel(String command) {
  final cmdLower = command.toLowerCase();

  const dangerousKeywords = [
    'rm -rf', 'shutdown', 'reboot', 'mkfs', 'dd if=', 'format',
    'drop table', 'truncate', 'delete from',
    '> /dev/sda', 'chmod -R 777 /',
  ];

  const warningKeywords = [
    'apt-get install', 'yum install', 'pip install', 'npm i',
    'systemctl stop', 'systemctl restart', 'kill -9',
    'iptables', 'ufw', 'userdel', 'passwd',
  ];

  for (final kw in dangerousKeywords) {
    if (cmdLower.contains(kw)) return 'dangerous';
  }
  for (final kw in warningKeywords) {
    if (cmdLower.contains(kw)) return 'warning';
  }
  return 'safe';
}
