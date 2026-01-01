import 'command.dart';
import 'unpack_command.dart';
import 'skip_command.dart';
import 'movedir_command.dart';
import 'newdir_command.dart';
import 'del_command.dart';
import 'move_command.dart';
import 'copy_command.dart';
import 'addbin2path_command.dart';
import 'replace_command.dart';

/// 命令工厂
/// 根据命令名称创建对应的命令实例
class CommandFactory {
  static final Map<String, Command> _commands = {
    'unpack': UnpackCommand(),
    'skip': SkipCommand(),
    'movedir': MovedirCommand(),
    'newdir': NewdirCommand(),
    'del': DelCommand(),
    'move': MoveCommand(),
    'copy': CopyCommand(),
    'addbin2path': Addbin2pathCommand(),
    'replace': ReplaceCommand(),
  };

  /// 根据命令名称获取命令实例
  /// [commandName] 命令名称（小写）
  /// 返回命令实例，如果不存在则返回 null
  static Command? getCommand(String commandName) {
    return _commands[commandName.toLowerCase()];
  }

  /// 检查命令是否存在
  /// [commandName] 命令名称（小写）
  /// 返回是否存在
  static bool hasCommand(String commandName) {
    return _commands.containsKey(commandName.toLowerCase());
  }

  /// 获取所有支持的命令名称
  /// 返回命令名称列表
  static List<String> getSupportedCommands() {
    return _commands.keys.toList();
  }
}

