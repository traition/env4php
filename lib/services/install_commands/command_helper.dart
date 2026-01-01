import 'dart:io';
import 'package:path/path.dart' as path;

/// 命令辅助类
/// 提供命令执行过程中需要的共享方法
class CommandHelper {
  /// 递归合并文件夹：将源文件夹的内容合并到目标文件夹
  /// 如果目标文件夹中已存在同名文件，则覆盖；如果存在同名文件夹，则递归合并
  static Future<void> mergeDirectory(
    Directory sourceDir,
    Directory destDir,
  ) async {
    // 确保目标文件夹存在
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // 遍历源文件夹中的所有内容
    await for (final entity in sourceDir.list()) {
      final entityName = path.basename(entity.path);
      final destEntityPath = path.join(destDir.path, entityName);

      if (entity is File) {
        // 如果是文件，直接覆盖（如果目标文件存在）
        final destFile = File(destEntityPath);
        if (await destFile.exists()) {
          await destFile.delete();
        }
        await File(entity.path).copy(destFile.path);
      } else if (entity is Directory) {
        // 如果是文件夹，递归合并（只处理源目录中存在的文件，保留目标目录中的其他文件）
        final destSubDir = Directory(destEntityPath);
        await mergeDirectory(Directory(entity.path), destSubDir);
      }
    }
    // 注意：不会删除目标目录中不在源目录中的文件，只覆盖同名文件
  }

  /// 撤销已添加到 PATH 的路径
  static Future<void> rollbackAddedPaths(
    List<String> addedPaths,
    Function(String step, double progress, String? logMessage)? onProgress,
  ) async {
    if (addedPaths.isEmpty) return;

    onProgress?.call('正在撤销 PATH 修改...', 0.0, '开始撤销已添加的 PATH 路径...');

    try {
      // 获取当前 PATH
      final pathEnvResult = await Process.run('powershell', [
        '-Command',
        '[Environment]::GetEnvironmentVariable("PATH", "User")',
      ], runInShell: true);

      String currentPath = '';
      if (pathEnvResult.exitCode == 0) {
        currentPath = pathEnvResult.stdout.toString().trim();
      }

      // 移除所有已添加的路径
      String normalizedCurrentPath = currentPath.replaceAll('\\', '/');
      for (final addedPath in addedPaths) {
        final normalizedAddedPath = addedPath.replaceAll('\\', '/');
        final pathParts = normalizedCurrentPath.split(';');
        pathParts.removeWhere(
          (part) =>
              part.trim().replaceAll('\\', '/').toLowerCase() ==
              normalizedAddedPath.toLowerCase(),
        );
        normalizedCurrentPath = pathParts.join(';');
      }

      // 更新 PATH
      if (normalizedCurrentPath != currentPath.replaceAll('\\', '/')) {
        final result = await Process.run('setx', [
          'PATH',
          normalizedCurrentPath,
        ], runInShell: true);

        if (result.exitCode == 0) {
          onProgress?.call(
            '正在撤销 PATH 修改...',
            0.0,
            '已撤销 ${addedPaths.length} 个 PATH 路径',
          );
        } else {
          onProgress?.call('正在撤销 PATH 修改...', 0.0, '警告: 撤销 PATH 修改时可能失败');
        }
      }
    } catch (e) {
      onProgress?.call('正在撤销 PATH 修改...', 0.0, '警告: 撤销 PATH 修改时发生错误: $e');
    }
  }
}

