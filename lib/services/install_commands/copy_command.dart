import 'dart:io';
import 'package:path/path.dart' as path;
import 'base_command.dart';
import 'command.dart';

/// 复制文件命令
/// copy [source] [destination]
class CopyCommand extends BaseCommand {
  @override
  String get name => 'copy';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    if (context.args.length < 3) {
      return (false, 'copy 命令需要两个参数: source 和 destination');
    }

    final source = context.args[1];
    final destination = context.args[2];

    // 解析 source 路径
    final sourcePath = resolvePath(source, context);
    final normalizedSourcePath = ensureAbsolutePath(sourcePath, path.join(context.storagePath, context.category));

    // 解析 destination 路径
    final destPath = resolvePath(destination, context);
    final normalizedDestPath = ensureAbsolutePath(destPath, path.join(context.storagePath, context.category));

    // 检查路径安全性
    if (!isPathWithinStorage(normalizedSourcePath, context.storagePath)) {
      return (false, '源路径超出存储目录范围: $normalizedSourcePath');
    }

    if (!isPathWithinStorage(normalizedDestPath, context.storagePath)) {
      return (false, '目标路径超出存储目录范围: $normalizedDestPath');
    }

    final sourceFile = File(normalizedSourcePath);
    if (!await sourceFile.exists()) {
      return (false, '源文件不存在: $normalizedSourcePath');
    }

    // 如果目标文件已存在，先删除
    final destFile = File(normalizedDestPath);
    if (await destFile.exists()) {
      await destFile.delete();
    }

    // 确保目标目录存在
    final destDir = Directory(path.dirname(normalizedDestPath));
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // 复制文件（与 move 的区别：使用 copy 而不是 rename）
    await sourceFile.copy(normalizedDestPath);

    context.onProgress?.call(
      '正在执行安装指令...',
      context.progress,
      '复制文件: $normalizedSourcePath -> $normalizedDestPath',
    );
    return (true, null);
  }
}

