import 'dart:io';
import 'package:path/path.dart' as path;
import 'base_command.dart';
import 'command.dart';

/// 添加目录到 PATH 命令
/// addbin2path [dir]
class Addbin2pathCommand extends BaseCommand {
  @override
  String get name => 'addbin2path';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    // 如果dir为空或未定义，则将存储目录\bin加入PATH
    String dirPath;
    if (context.args.length < 2 || context.args[1].isEmpty) {
      // dir 为空或未定义，使用存储目录\bin
      dirPath = path.join(context.storagePath, 'bin');
    } else {
      dirPath = context.args[1];
    }

    // 解析路径并检查是否在存储目录内
    final (resolvedDirPath, dirWithin) = resolveAndCheckPath(
      dirPath,
      context.currentWorkDir,
      context.storagePath,
    );

    if (!dirWithin) {
      return (false, '目录路径超出存储目录范围: $resolvedDirPath');
    }

    dirPath = resolvedDirPath;

    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      // 如果目录不存在，创建它
      await dir.create(recursive: true);
      context.onProgress?.call('正在执行安装指令...', context.progress, '已创建目录: $dirPath');
    }

    // 检查 PATH 中是否已存在该路径
    final normalizedPath = path.normalize(dirPath);
    final pathEnvResult = await Process.run('powershell', [
      '-Command',
      '[Environment]::GetEnvironmentVariable("PATH", "User")',
    ], runInShell: true);

    String currentPath = '';
    if (pathEnvResult.exitCode == 0) {
      currentPath = pathEnvResult.stdout.toString().trim();
    }

    // 检查路径是否已存在（不区分大小写，处理路径分隔符）
    final normalizedCurrentPath = currentPath.replaceAll('\\', '/');
    final normalizedTargetPath = normalizedPath.replaceAll('\\', '/');
    final pathParts = normalizedCurrentPath.split(';');
    bool pathExists = pathParts.any(
      (part) =>
          part.trim().replaceAll('\\', '/').toLowerCase() ==
          normalizedTargetPath.toLowerCase(),
    );

    if (pathExists) {
      context.onProgress?.call(
        '正在执行安装指令...',
        context.progress,
        'PATH 中已存在该路径，跳过: $normalizedPath',
      );
    } else {
      // 使用 setx 命令添加到用户环境变量 PATH
      final result = await Process.run('setx', [
        'PATH',
        '$currentPath;$normalizedPath',
      ], runInShell: true);

      if (result.exitCode != 0) {
        // setx 可能返回非零退出码但实际成功，检查输出
        final output =
            result.stdout.toString() + result.stderr.toString();
        if (!output.toLowerCase().contains('success')) {
          return (false, '添加环境变量失败: ${result.stderr}');
        }
      }

      // 记录已添加的路径
      context.addedPaths.add(normalizedPath);

      context.onProgress?.call(
        '正在执行安装指令...',
        context.progress,
        '已添加目录到系统环境变量 PATH: $normalizedPath',
      );
    }
    return (true, null);
  }
}

