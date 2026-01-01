import 'dart:io';
import 'package:path/path.dart' as path;
import 'base_command.dart';
import 'command.dart';

/// 创建文件夹命令
/// newdir [path]
class NewdirCommand extends BaseCommand {
  @override
  String get name => 'newdir';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    if (context.args.length < 2) {
      return (false, 'newdir 命令需要一个参数: path');
    }

    final dirPath = context.args[1];

    // 解析路径
    String targetPath;
    if (dirPath.startsWith('.soft')) {
      // .soft 开头，指向软件目录
      String relativePath = dirPath.substring('.soft'.length);
      if (relativePath.isNotEmpty &&
          (relativePath[0] == '/' || relativePath[0] == '\\')) {
        relativePath = relativePath.substring(1);
      }
      targetPath = path.normalize(path.join(context.softwareDir, relativePath));
    } else if (path.isAbsolute(dirPath)) {
      // 绝对路径，直接使用
      targetPath = dirPath;
    } else {
      // 默认以软件的预期安装目录为基准
      targetPath = path.normalize(path.join(context.softwareDir, dirPath));
    }

    // 检查路径是否在存储目录内
    if (!isPathWithinStorage(targetPath, context.storagePath)) {
      return (false, '目标路径超出存储目录范围: $targetPath');
    }

    // 创建目录
    final targetDir = Directory(targetPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
      context.onProgress?.call('正在执行安装指令...', context.progress, '创建目录: $targetPath');
    } else {
      context.onProgress?.call('正在执行安装指令...', context.progress, '目录已存在: $targetPath');
    }
    return (true, null);
  }
}

