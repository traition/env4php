import 'dart:io';
import 'package:path/path.dart' as path;
import 'base_command.dart';
import 'command.dart';
import 'command_helper.dart';

/// 移动文件夹命令
/// movedir [source] [destination]
class MovedirCommand extends BaseCommand {
  @override
  String get name => 'movedir';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    if (context.args.length < 3) {
      return (false, 'movedir 命令需要两个参数: source 和 destination');
    }

    final source = context.args[1];
    final destination = context.args[2];

    // 解析 source 路径
    String sourcePath;
    if (source == '.temp') {
      sourcePath = path.join(context.storagePath, context.category, '.temp');
    } else if (path.isAbsolute(source)) {
      sourcePath = source;
    } else {
      sourcePath = path.join(context.currentWorkDir, source);
    }

    // 解析 destination 路径
    String destPath;
    if (destination == '.temp') {
      destPath = path.join(context.storagePath, context.category, '.temp');
    } else if (destination == '/') {
      // '/' 表示当前工作目录（对于附件命令，表示软件目录）
      destPath = context.currentWorkDir;
    } else {
      if (path.isAbsolute(destination)) {
        destPath = destination;
      } else {
        destPath = path.join(context.currentWorkDir, destination);
      }
    }

    // 检查路径安全性
    final sourceCheck = resolveAndCheckPath(sourcePath, context.currentWorkDir, context.storagePath);
    if (!sourceCheck.$2) {
      return (false, '源路径超出存储目录范围: ${sourceCheck.$1}');
    }
    sourcePath = sourceCheck.$1;

    final destCheck = resolveAndCheckPath(destPath, context.currentWorkDir, context.storagePath);
    if (!destCheck.$2) {
      return (false, '目标路径超出存储目录范围: ${destCheck.$1}');
    }
    destPath = destCheck.$1;

    final sourceDir = Directory(sourcePath);
    if (!await sourceDir.exists()) {
      return (false, '源目录不存在: $sourcePath');
    }

    // 如果目标文件夹不存在，则新建
    final destDir = Directory(destPath);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // 移动源文件夹下的文件到目标文件夹下
    await for (final entity in sourceDir.list()) {
      final destEntityPath = path.join(
        destPath,
        path.basename(entity.path),
      );

      if (entity is Directory) {
        // 如果是文件夹
        final destEntity = Directory(destEntityPath);
        if (await destEntity.exists()) {
          // 如果目标文件夹已存在，递归合并而不是删除
          await CommandHelper.mergeDirectory(Directory(entity.path), destEntity);
          // 合并后删除源文件夹
          await Directory(entity.path).delete(recursive: true);
        } else {
          // 如果目标文件夹不存在，直接移动
          await Directory(entity.path).rename(destEntityPath);
        }
      } else if (entity is File) {
        // 如果是文件
        final destEntity = File(destEntityPath);
        // 如果目标文件已存在，先删除再移动（覆盖）
        if (await destEntity.exists()) {
          await destEntity.delete();
        }
        await File(entity.path).rename(destEntityPath);
      }
    }

    // 移动完成后删除源文件夹
    await sourceDir.delete(recursive: true);

    // 更新当前工作目录
    if (destination == '/') {
      // '/' 表示当前工作目录，不需要更新
    } else if (destination != '.temp') {
      context.currentWorkDir = destPath;
    }

    context.onProgress?.call(
      '正在执行安装指令...',
      context.progress,
      '移动目录内容: $source -> $destPath',
    );
    return (true, null);
  }
}

