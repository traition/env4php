import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/install_service.dart';

/// 更换PHP版本工具
class PhpVersionTool {
  /// 执行更换PHP版本操作
  static Future<void> execute(BuildContext context) async {
    // 1. 检查已安装的 PHP 版本
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('存储目录未设置，请先设置存储目录')));
      return;
    }

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法加载软件源')));
      return;
    }

    // 获取已安装的 PHP 软件列表
    final List<Software> installedPhp = [];
    for (final php in softwareSource.php) {
      final dir = Directory('$storagePath/php/${php.id}');
      if (await dir.exists()) {
        installedPhp.add(php);
      }
    }

    // 检查数量
    if (installedPhp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未安装 PHP，请先安装 2 个或以上版本的 PHP')),
      );
      return;
    }

    if (installedPhp.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('只安装了一个 PHP 版本，无法更改。请先安装 2 个或以上版本的 PHP'),
        ),
      );
      return;
    }

    // 2. 让用户选择 PHP 版本
    final selectedPhp = await showDialog<Software>(
      context: context,
      useRootNavigator: false, // 不在根 Navigator 中显示，只在 Container 区域显示
      builder: (context) => AlertDialog(
        title: const Text('选择 PHP 版本'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: installedPhp.length,
            itemBuilder: (context, index) {
              final php = installedPhp[index];
              return ListTile(
                title: Text(php.name),
                subtitle:
                    php.description != null ? Text(php.description!) : null,
                onTap: () => Navigator.of(context).pop(php),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selectedPhp == null) {
      // 用户取消了选择
      return;
    }

    // 3. 修改 php.bat 文件
    final selectedPhpPath = path.join(storagePath, 'php', selectedPhp.id);

    final updateResult = await InstallService.updatePhpBat(
      selectedPhpPath,
      storagePath,
      onProgress: (step, progress, logMessage) {
        // 可以在这里显示进度，但通常不需要
      },
    );

    if (!updateResult.$1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '替换失败: ${updateResult.$2 ?? "未知错误"}，请重新安装 PHP',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已成功将 PHP 版本切换为 ${selectedPhp.name}'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

