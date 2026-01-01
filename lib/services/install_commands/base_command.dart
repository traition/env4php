import 'package:path/path.dart' as path;
import 'command.dart';

/// 命令基类
/// 提供通用的辅助方法
abstract class BaseCommand implements Command {
  /// 检查路径是否在存储目录范围内
  bool isPathWithinStorage(String targetPath, String storagePath) {
    try {
      final normalizedTarget = path.normalize(path.absolute(targetPath));
      final normalizedStorage = path.normalize(path.absolute(storagePath));
      return normalizedTarget.startsWith(normalizedStorage);
    } catch (e) {
      return false;
    }
  }

  /// 解析路径并检查是否在存储目录范围内
  (String resolvedPath, bool isWithinStorage) resolveAndCheckPath(
    String pathStr,
    String baseDir,
    String storagePath,
  ) {
    String resolvedPath;
    if (path.isAbsolute(pathStr)) {
      resolvedPath = path.normalize(pathStr);
    } else {
      resolvedPath = path.normalize(path.absolute(baseDir, pathStr));
    }
    final isWithin = isPathWithinStorage(resolvedPath, storagePath);
    return (resolvedPath, isWithin);
  }

  /// 解析路径（支持特殊前缀）
  /// [pathStr] 路径字符串
  /// [context] 命令上下文
  /// [isAttachment] 是否为附件命令
  String resolvePath(
    String pathStr,
    CommandContext context, {
    bool isAttachment = false,
  }) {
    final categoryDir = path.join(context.storagePath, context.category);

    if (pathStr.startsWith('.down')) {
      // .down 开头，指向分类目录
      String relativePath = pathStr.substring('.down'.length);
      if (relativePath.isNotEmpty &&
          (relativePath[0] == '/' || relativePath[0] == '\\')) {
        relativePath = relativePath.substring(1);
      }
      return path.normalize(path.join(categoryDir, relativePath));
    } else if (pathStr.startsWith('.soft')) {
      // .soft 开头，指向软件目录
      String relativePath = pathStr.substring('.soft'.length);
      if (relativePath.isNotEmpty &&
          (relativePath[0] == '/' || relativePath[0] == '\\')) {
        relativePath = relativePath.substring(1);
      }
      return path.normalize(path.join(context.softwareDir, relativePath));
    } else if (pathStr.startsWith('.7ztemp')) {
      // .7ztemp 开头，指向临时目录
      String relativePath = pathStr.substring('.7ztemp'.length);
      if (relativePath.isNotEmpty &&
          (relativePath[0] == '/' || relativePath[0] == '\\')) {
        relativePath = relativePath.substring(1);
      }
      return path.normalize(path.join(context.tempDir, relativePath));
    } else if (pathStr.startsWith('bin')) {
      // bin 开头，指向存储目录\bin
      String relativePath = pathStr.substring('bin'.length);
      if (relativePath.isNotEmpty &&
          (relativePath[0] == '/' || relativePath[0] == '\\')) {
        relativePath = relativePath.substring(1);
      }
      return path.normalize(
        path.join(context.storagePath, 'bin', relativePath),
      );
    } else if (pathStr == '.temp') {
      // .temp 指向存储目录下的子分类文件夹下的 .temp 文件夹
      return path.join(context.storagePath, context.category, '.temp');
    } else if (pathStr == '/') {
      // '/' 表示当前工作目录（对于附件命令，表示软件目录）
      return isAttachment ? context.softwareDir : context.currentWorkDir;
    } else if (path.isAbsolute(pathStr)) {
      return path.normalize(pathStr);
    } else {
      // 默认相对路径相对于分类目录（对于附件命令，相对于软件目录）
      if (isAttachment) {
        return path.normalize(path.join(context.softwareDir, pathStr));
      } else {
        return path.join(categoryDir, pathStr);
      }
    }
  }

  /// 确保路径是绝对路径
  String ensureAbsolutePath(String pathStr, String baseDir) {
    if (path.isAbsolute(pathStr)) {
      return path.normalize(pathStr);
    } else {
      return path.normalize(path.absolute(baseDir, pathStr));
    }
  }
}

