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

  /// 列出手机/App 本地目录内容
  localListDirectory,

  /// 读取手机/App 本地文本文件
  localReadFile,

  /// 写入/创建手机/App 本地文本文件
  localWriteFile,

  /// 创建手机/App 本地目录
  localCreateDirectory,

  /// 删除手机/App 本地文件或目录
  localDeletePath,

  /// 获取服务器防火墙状态
  firewallStatus,

  /// 获取服务器监听端口
  portList,

  /// 获取服务器网络连接和网卡概览
  networkStatus,

  /// 获取服务器目录空间占用概览
  diskUsage,

  /// 探测常见内网穿透服务状态
  tunnelStatus,
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

  // 9. 手机/App 本地目录列表
  {
    "type": "function",
    "function": {
      "name": "local_list_directory",
      "description": "列出手机或当前 App 可访问的本地目录内容。"
          "如果 path 为空，会列出 Agent 默认工作目录。"
          "注意：Android 受系统沙盒限制，只能访问 App 可访问路径或用户已授权/导入的文件。",
      "parameters": {
        "type": "object",
        "required": [],
        "properties": {
          "path": {
            "type": "string",
            "description": "本地目录路径。为空时使用 Agent 默认工作目录",
          },
          "show_hidden": {
            "type": "boolean",
            "description": "是否显示隐藏文件",
          },
        },
      },
    },
  },

  // 10. 读取手机/App 本地文件
  {
    "type": "function",
    "function": {
      "name": "local_read_file",
      "description": "读取手机或当前 App 可访问的本地文本文件内容。"
          "不要用于读取二进制文件、大文件或系统隐私目录。",
      "parameters": {
        "type": "object",
        "required": ["path"],
        "properties": {
          "path": {"type": "string", "description": "本地文本文件路径"},
          "max_chars": {
            "type": "integer",
            "description": "最多读取字符数，默认 20000",
          },
        },
      },
    },
  },

  // 11. 写入手机/App 本地文件
  {
    "type": "function",
    "function": {
      "name": "local_write_file",
      "description": "在手机或当前 App 可访问路径写入/创建文本文件，会覆盖已有内容。"
          "写入前必须向用户说明目标路径和风险。",
      "parameters": {
        "type": "object",
        "required": ["path", "content"],
        "properties": {
          "path": {"type": "string", "description": "本地文件路径"},
          "content": {"type": "string", "description": "要写入的完整文本内容"},
          "description": {
            "type": "string",
            "description": "说明写入目的和内容摘要",
          },
        },
      },
    },
  },

  // 12. 创建手机/App 本地目录
  {
    "type": "function",
    "function": {
      "name": "local_create_directory",
      "description": "在手机或当前 App 可访问路径创建目录，支持递归创建父目录。",
      "parameters": {
        "type": "object",
        "required": ["path"],
        "properties": {
          "path": {"type": "string", "description": "要创建的本地目录路径"},
        },
      },
    },
  },

  // 13. 删除手机/App 本地路径
  {
    "type": "function",
    "function": {
      "name": "local_delete_path",
      "description": "删除手机或当前 App 可访问的本地文件/目录。"
          "这是破坏性操作，必须获得用户明确确认。",
      "parameters": {
        "type": "object",
        "required": ["path"],
        "properties": {
          "path": {"type": "string", "description": "要删除的本地文件或目录路径"},
          "recursive": {
            "type": "boolean",
            "description": "删除目录时是否递归删除内部内容",
          },
          "description": {
            "type": "string",
            "description": "说明删除原因和影响范围",
          },
        },
      },
    },
  },

  // 14. 防火墙状态
  {
    "type": "function",
    "function": {
      "name": "firewall_status",
      "description": "读取服务器防火墙状态，包括 ufw、firewalld、iptables/nftables 规则摘要。只读。",
      "parameters": {"type": "object", "required": [], "properties": {}},
    },
  },

  // 15. 监听端口
  {
    "type": "function",
    "function": {
      "name": "port_list",
      "description": "列出服务器监听端口、协议、进程信息。可用于排查端口暴露和服务监听。只读。",
      "parameters": {
        "type": "object",
        "required": [],
        "properties": {
          "filter": {"type": "string", "description": "按端口或进程名过滤"},
        },
      },
    },
  },

  // 16. 网络状态
  {
    "type": "function",
    "function": {
      "name": "network_status",
      "description": "获取服务器网卡、IP、路由、DNS 和连接摘要。只读。",
      "parameters": {"type": "object", "required": [], "properties": {}},
    },
  },

  // 17. 目录空间占用
  {
    "type": "function",
    "function": {
      "name": "disk_usage",
      "description": "获取服务器指定目录下的空间占用，用于可视化定位大文件/大目录。只读。",
      "parameters": {
        "type": "object",
        "required": [],
        "properties": {
          "path": {"type": "string", "description": "目录路径，默认 /"},
          "depth": {"type": "integer", "description": "du 深度，默认 1"},
        },
      },
    },
  },

  // 18. 内网穿透状态
  {
    "type": "function",
    "function": {
      "name": "tunnel_status",
      "description": "探测常见内网穿透/代理服务状态，例如 frpc/frps、ngrok、cloudflared、tailscale、zerotier。只读。",
      "parameters": {"type": "object", "required": [], "properties": {}},
    },
  },
];

/// Agent 系统提示词（中文优化）
const String agentSystemPrompt = '''你是 Surlor AI，一个专业的移动端 AI Agent 与服务器运维智能助手。

## 核心能力
- 通过 SSH 连接服务器，执行命令、读写服务器文件
- 监控服务器状态（CPU、内存、磁盘、进程、Docker 等）
- 提供专业运维面板能力：防火墙、监听端口、网络、目录空间、Docker、systemd 服务、内网穿透状态巡检
- 操作手机/App 可访问的本地文件：列目录、读文件、写文件、创建目录、删除路径
- 帮助排查问题、优化配置、自动化运维和整理本地资料

## 本地文件规则
- `local_*` 工具操作的是手机或当前 App 可访问的本地文件系统，不是服务器
- Android/iOS 受系统沙盒限制，不能绕过系统权限访问未授权目录
- 如果用户没有给路径，优先使用 Agent 默认工作目录
- 写入、覆盖、删除本地文件前，必须说明路径和影响并获得确认

## 工作原则
1. **先了解再行动**：遇到问题时，先收集信息再给出方案
2. **安全第一**：破坏性操作前必须说明风险并获得用户确认
3. **目标明确**：区分服务器操作和手机本地操作，不要混用路径
4. **解释清晰**：每个操作都告诉用户你在做什么、为什么这样做
5. **分步进行**：复杂任务拆解为多个步骤，每步确认后再继续

## 响应风格
- 使用简洁的中文
- 重要信息用表格或列表呈现
- 命令、路径和配置用 markdown 代码块包裹
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
