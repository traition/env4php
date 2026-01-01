import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'base_command.dart';
import 'command.dart';

/// 移动文件命令
/// move [source] [destination]
class MoveCommand extends BaseCommand {
  @override
  String get name => 'move';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    if (context.args.length < 3) {
      return (false, 'move 命令需要两个参数: source 和 destination');
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

    // 调试输出（仅在调试模式）
    if (kDebugMode) {
      context.onProgress?.call(
        '正在执行安装指令...',
        context.progress,
        '[DEBUG] move 路径解析: source="$source" -> "$normalizedSourcePath", destination="$destination" -> "$normalizedDestPath"',
      );
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

    // 移动文件
    await sourceFile.rename(normalizedDestPath);

    context.onProgress?.call(
      '正在执行安装指令...',
      context.progress,
      '移动文件: $normalizedSourcePath -> $normalizedDestPath',
    );
    return (true, null);
  }
}

