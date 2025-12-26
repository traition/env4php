import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import '../models/software_model.dart';
import 'software_source_service.dart';

/// 图标服务，用于统一获取软件图标路径
class IconService {
  /// 获取软件图标路径
  ///
  /// [software] 软件对象
  /// [softwareSource] 软件源对象（可选，如果不提供则自动加载）
  ///
  /// 返回图标文件路径，如果不存在则返回 null
  static Future<String?> getIconPath(
    Software software, {
    SoftwareSource? softwareSource,
  }) async {
    try {
      // 获取应用可执行文件目录
      final executablePath = Platform.resolvedExecutable;
      final executableDir = path.dirname(executablePath);
      final iconsDir = path.join(executableDir, 'assets', 'icons');

      // 确定图标文件名
      String? iconFileName;

      // 如果没有提供软件源，则加载
      final source = softwareSource ?? await SoftwareSourceService.getSource();

      if (source != null) {
        // 判断软件分类
        String? category;
        if (source.servers.any((s) => s.id == software.id)) {
          category = 'servers';
        } else if (source.databases.any((s) => s.id == software.id)) {
          category = 'databases';
        } else if (source.php.any((s) => s.id == software.id)) {
          category = 'php';
        } else if (source.tools.any((s) => s.id == software.id)) {
          category = 'tools';
        }

        if (category == 'php') {
          // PHP 分类直接使用 php.png
          iconFileName = 'php.png';
        } else if (software.cate4 != null && software.cate4!.isNotEmpty) {
          // 其他分类使用 cate4 值作为文件名
          iconFileName = '${software.cate4}.png';
        } else {
          // 没有 cate4 值，不显示图标
          return null;
        }
      } else {
        // 无法加载软件源，使用 cate4 作为后备方案
        if (software.cate4 != null && software.cate4!.isNotEmpty) {
          iconFileName = '${software.cate4}.png';
        } else {
          return null;
        }
      }

      // 构建完整路径
      final iconPath = path.join(iconsDir, iconFileName);
      final iconFile = File(iconPath);

      // 检查文件是否存在
      if (await iconFile.exists()) {
        return iconPath;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[IconService] 获取图标路径失败: $e');
      }
      // 出错时返回 null，不显示图标
      return null;
    }
  }
}
