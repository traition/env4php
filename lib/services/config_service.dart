import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// 配置管理服务
class ConfigService {
  static const String _keyStoragePath = 'storage_path';

  /// 获取存储目录路径
  static Future<String?> getStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoragePath);
  }

  /// 设置存储目录路径
  static Future<bool> setStoragePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setString(_keyStoragePath, path);
  }

  /// 检查存储目录是否已设置
  static Future<bool> isStoragePathSet() async {
    final path = await getStoragePath();
    return path != null && path.isNotEmpty;
  }

  /// 初始化存储目录结构
  static Future<bool> initializeStorageDirectories(String basePath) async {
    try {
      final baseDir = Directory(basePath);
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      final directories = ['servers', 'databases', 'php', 'tools'];
      for (final dirName in directories) {
        final dir = Directory('$basePath/$dirName');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 检查软件是否已安装
  static Future<bool> isSoftwareInstalled(String category, String id) async {
    final storagePath = await getStoragePath();
    if (storagePath == null) return false;

    final softwareDir = Directory('$storagePath/$category/$id');
    return await softwareDir.exists();
  }
}



