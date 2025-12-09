import 'dart:io';
import 'package:path/path.dart' as path;

/// 解压服务
class ExtractService {
  /// 获取 7za.exe 的路径
  /// 返回软件目录下的 assets\7z\7za_2501.exe
  static Future<String> get7zaPath() async {
    // 获取可执行文件所在的目录
    final executablePath = Platform.resolvedExecutable;
    final executableDir = path.dirname(executablePath);
    
    // 构建 7za.exe 的路径：软件目录/assets/7z/7za_2501.exe
    final exePath = path.join(executableDir, 'assets', '7z', '7za_2501.exe');
    final exeFile = File(exePath);

    // 检查文件是否存在
    if (await exeFile.exists()) {
      return exePath;
    }

    // 如果不存在，尝试使用相对路径（开发时）
    final relativePath = 'lib/assets/7z/7za_2501.exe';
    final relativeFile = File(relativePath);
    if (await relativeFile.exists()) {
      return relativePath;
    }

    // 如果都不存在，抛出异常
    throw Exception('7za.exe 不存在于: $exePath 或 $relativePath');
  }

  /// 解压文件
  /// [archivePath] 压缩包路径
  /// [outputDir] 输出目录
  /// [format] 压缩格式 (zip, 7z, tar, gz, bz2 等)
  static Future<bool> extractFile(
    String archivePath,
    String outputDir, {
    String? format,
  }) async {
    try {
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        return false;
      }

      // 确保输出目录存在
      final outputDirectory = Directory(outputDir);
      if (!await outputDirectory.exists()) {
        await outputDirectory.create(recursive: true);
      }

      // 获取 7za.exe 路径（软件目录下的 assets\7z\7za_2501.exe）
      final exePath = await get7zaPath();
      return await _extractWith7za(exePath, archivePath, outputDir);
    } catch (e) {
      return false;
    }
  }

  /// 使用 7za.exe 解压
  static Future<bool> _extractWith7za(
    String exePath,
    String archivePath,
    String outputDir,
  ) async {
    try {
      // 7za.exe x archive.zip -o输出目录 -y
      final result = await Process.run(
        exePath,
        [
          'x',
          archivePath,
          '-o$outputDir',
          '-y', // 自动确认覆盖
        ],
        runInShell: true,
      );

      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 检查目录中是否只有一个文件夹（不包括文件）
  /// 返回文件夹路径，如果有多个或没有则返回 null
  static Future<String?> getSingleFolder(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return null;
    }

    final List<String> folders = [];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        folders.add(entity.path);
      }
    }

    if (folders.length == 1) {
      return folders.first;
    }

    return null;
  }
}
