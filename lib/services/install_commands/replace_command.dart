import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'base_command.dart';
import 'command.dart';

/// 替换字符串命令
/// replace [filepath] [needle] [replace]
class ReplaceCommand extends BaseCommand {
  @override
  String get name => 'replace';

  /// 解析 replace 命令的参数，支持反引号（`）作为字符串定界符
  static (String filePath, String needle, String replace)? parseCommand(
    String command,
  ) {
    // 移除命令名 "replace"
    String remaining = command.substring('replace'.length).trim();
    if (remaining.isEmpty) {
      return null;
    }

    // 解析 filePath（第一个参数，不需要反引号）
    int filePathEnd = remaining.indexOf(' ');
    if (filePathEnd == -1) {
      return null;
    }
    String filePath = remaining.substring(0, filePathEnd);
    remaining = remaining.substring(filePathEnd).trim();

    // 解析 needle（第二个参数，可能用反引号包裹）
    String needle = '';
    if (remaining.startsWith('`')) {
      // 以反引号开头，找到匹配的结束反引号
      int endIndex = remaining.indexOf('`', 1);
      if (endIndex == -1) {
        return null; // 没有找到匹配的结束反引号
      }
      needle = remaining.substring(1, endIndex);
      remaining = remaining.substring(endIndex + 1).trim();
    } else {
      // 没有反引号，找到下一个空格或反引号
      int spaceIndex = remaining.indexOf(' ');
      int backtickIndex = remaining.indexOf('`');
      int endIndex = -1;
      if (spaceIndex != -1 && backtickIndex != -1) {
        endIndex = spaceIndex < backtickIndex ? spaceIndex : backtickIndex;
      } else if (spaceIndex != -1) {
        endIndex = spaceIndex;
      } else if (backtickIndex != -1) {
        endIndex = backtickIndex;
      } else {
        // 没有找到分隔符，整个剩余部分都是 needle
        needle = remaining;
        remaining = '';
      }
      if (endIndex != -1) {
        needle = remaining.substring(0, endIndex);
        remaining = remaining.substring(endIndex).trim();
      }
    }

    // 解析 replace（第三个参数，可能用反引号包裹）
    String replace;
    if (remaining.startsWith('`')) {
      // 以反引号开头，找到匹配的结束反引号
      int endIndex = remaining.indexOf('`', 1);
      if (endIndex == -1) {
        return null; // 没有找到匹配的结束反引号
      }
      replace = remaining.substring(1, endIndex);
    } else {
      // 没有反引号，使用剩余的所有内容
      replace = remaining;
    }

    return (filePath, needle, replace);
  }

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    // 解析 replace 命令的参数
    final parsed = parseCommand(context.command);
    if (parsed == null) {
      return (false, 'replace 命令解析失败，请检查命令格式');
    }

    String filePath = parsed.$1;
    String needle = parsed.$2;
    String replace = parsed.$3;

    // 解析文件路径
    String resolvedFilePath;
    String baseDirForCheck; // 用于路径安全检查的基准目录

    // 调试输出（仅在调试模式）
    if (kDebugMode) {
      context.onProgress?.call(
        '正在执行安装指令...',
        context.progress,
        '[DEBUG] replace 命令解析: filePath="$filePath", downloadPath="${context.downloadPath}", softwareDir="${context.softwareDir}"',
      );
    }

    if (path.isAbsolute(filePath)) {
      resolvedFilePath = filePath;
      baseDirForCheck = context.softwareDir;
    } else if (filePath.startsWith('.down')) {
      // .down 开头，将 .down 部分替换为分类目录（$storagePath/$category）
      final categoryDir = path.join(context.storagePath, context.category);
      String relativePath = filePath.substring('.down'.length);
      if (relativePath.isNotEmpty &&
          (relativePath[0] == '/' || relativePath[0] == '\\')) {
        relativePath = relativePath.substring(1);
      }
      resolvedFilePath = path.normalize(path.join(categoryDir, relativePath));
      baseDirForCheck = categoryDir;

      // 调试输出（仅在调试模式）
      if (kDebugMode) {
        context.onProgress?.call(
          '正在执行安装指令...',
          context.progress,
          '[DEBUG] .down 路径解析: filePath="$filePath", categoryDir="$categoryDir", relativePath="$relativePath", resolvedFilePath="$resolvedFilePath"',
        );
      }
    } else if (filePath.startsWith('.7ztemp')) {
      // .7ztemp 开头，相对于解压缩的目录（.7ztemp）
      final relativePath = filePath.substring('.7ztemp'.length);
      if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
        resolvedFilePath = path.join(
          context.tempDir,
          relativePath.substring(1),
        );
      } else {
        resolvedFilePath = path.join(context.tempDir, relativePath);
      }
      baseDirForCheck = context.tempDir;
    } else {
      // 其他情况，相对于软件安装路径
      resolvedFilePath = path.normalize(
        path.join(context.softwareDir, filePath),
      );
      baseDirForCheck = context.softwareDir;
    }

    // 确保 resolvedFilePath 是绝对路径
    if (!filePath.startsWith('.down') &&
        !path.isAbsolute(resolvedFilePath)) {
      resolvedFilePath = path.normalize(
        path.absolute(baseDirForCheck, resolvedFilePath),
      );
    }

    // 调试输出（仅在调试模式，.down 情况已在上面输出）
    if (kDebugMode && !filePath.startsWith('.down')) {
      context.onProgress?.call(
        '正在执行安装指令...',
        context.progress,
        '[DEBUG] replace 文件路径解析: $filePath -> $resolvedFilePath (基准: $baseDirForCheck)',
      );
    }

    // 检查路径安全性
    if (!isPathWithinStorage(resolvedFilePath, context.storagePath)) {
      return (false, '文件路径超出存储目录范围: $resolvedFilePath');
    }

    final file = File(resolvedFilePath);
    if (!await file.exists()) {
      return (false, '文件不存在: $resolvedFilePath');
    }

    // 读取文件内容
    String content = await file.readAsString();

    // 处理 replace 参数的特殊值
    String processedReplace = replace;
    // 将 replace 中的 !softPath! 替换为软件安装路径
    if (processedReplace.contains('!softPath!')) {
      // !softPath! 表示当前安装的软件预期的安装路径
      // 将 softwareDir 中的路径分隔符统一为 Windows 风格（\）
      final normalizedSoftwareDir = context.softwareDir.replaceAll('/', '\\');
      processedReplace = processedReplace.replaceAll(
        '!softPath!',
        normalizedSoftwareDir,
      );
    }

    // 将 processedReplace 中的所有 / 替换为 \（确保路径分隔符统一为 Windows 风格）
    processedReplace = processedReplace.replaceAll('/', '\\');

    // 执行替换（替换所有匹配的部分）
    if (!content.contains(needle)) {
      context.onProgress?.call(
        '正在执行安装指令...',
        context.progress,
        '警告: 文件中未找到匹配的字符串: $needle',
      );
    } else {
      content = content.replaceAll(needle, processedReplace);
      // 写回文件
      await file.writeAsString(content);
      context.onProgress?.call(
        '正在执行安装指令...',
        context.progress,
        '已替换文件中的字符串: $resolvedFilePath',
      );
    }
    return (true, null);
  }
}

