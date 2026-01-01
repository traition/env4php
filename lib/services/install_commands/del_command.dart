import 'dart:io';
import 'base_command.dart';
import 'command.dart';

/// 删除命令
/// del [target]
class DelCommand extends BaseCommand {
  @override
  String get name => 'del';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    if (context.args.length < 2) {
      return (false, 'del 命令需要一个参数: target');
    }

    final target = context.args[1];

    if (target == 'all') {
      // 删除当前工作目录下的所有文件
      // 检查当前工作目录是否在存储目录内
      if (!isPathWithinStorage(context.currentWorkDir, context.storagePath)) {
        return (false, '工作目录超出存储目录范围: ${context.currentWorkDir}');
      }

      final workDir = Directory(context.currentWorkDir);
      if (await workDir.exists()) {
        await for (final entity in workDir.list()) {
          if (entity is Directory) {
            await entity.delete(recursive: true);
          } else if (entity is File) {
            await entity.delete();
          }
        }
      }
      context.onProgress?.call('正在执行安装指令...', context.progress, '删除所有文件');
    } else {
      // 删除指定文件/目录
      final targetPath = resolvePath(target, context);
      final (resolvedPath, targetWithin) = resolveAndCheckPath(
        targetPath,
        context.currentWorkDir,
        context.storagePath,
      );

      if (!targetWithin) {
        return (false, '目标路径超出存储目录范围: $resolvedPath');
      }

      final targetEntity = FileSystemEntity.typeSync(resolvedPath);
      if (targetEntity == FileSystemEntityType.directory) {
        await Directory(resolvedPath).delete(recursive: true);
      } else if (targetEntity == FileSystemEntityType.file) {
        await File(resolvedPath).delete();
      }
      context.onProgress?.call('正在执行安装指令...', context.progress, '删除: $resolvedPath');
    }
    return (true, null);
  }
}

