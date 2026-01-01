import 'base_command.dart';
import 'command.dart';

/// 跳过命令
/// 不执行任何操作，直接跳过
class SkipCommand extends BaseCommand {
  @override
  String get name => 'skip';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    context.onProgress?.call('正在执行安装指令...', context.progress, '跳过此步骤');
    return (true, null);
  }
}

