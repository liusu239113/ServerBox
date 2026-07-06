/// SSH client generation helper.
/// Re-exports genClient, Spi, and SSHClient extensions for AgentService.
library;
export 'package:dartssh2/dartssh2.dart' show SSHClient;
export 'package:surlor_ai/core/extension/ssh_client.dart';
export 'package:surlor_ai/core/utils/server.dart' show genClient;
export 'package:surlor_ai/data/model/server/server_private_info.dart' show Spi;
