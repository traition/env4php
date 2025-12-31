import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../config_service.dart';
import '../software_source_service.dart';
import '../../models/software_model.dart';
import '../../utils/nginx_project_helper.dart';

/// phpMyAdmin 软件管理器（仅初始化）
/// 注意：phpMyAdmin 不需要启动/停止/重启功能，只需要初始化
class PhpmyadminManager {
  String get supportedCate4 => 'phpmyadmin';

  /// 初始化 phpMyAdmin（在安装完成后调用）
  Future<(bool success, String? error)> initialize(
    String phpmyadminDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 检查是否安装了 PHP 和 nginx
      onProgress?.call('正在检查依赖...', 0.98, '检查 PHP 和 nginx 是否已安装...');

      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) {
        return (false, '存储目录未设置');
      }

      final softwareSource = await SoftwareSourceService.getSource();
      if (softwareSource == null) {
        return (false, '无法获取软件源');
      }

      // 检查 nginx 是否安装
      final nginx = softwareSource.servers.firstWhere(
        (s) => s.cate4?.toLowerCase() == 'nginx',
        orElse: () => Software(
          id: '',
          name: '',
          byte: 0,
          downloadURL: '',
          commands: [],
          attachments: [],
        ),
      );

      if (nginx.id.isEmpty) {
        return (false, 'nginx 未安装，请先安装 nginx');
      }

      final nginxDir = Directory('$storagePath/servers/${nginx.id}');
      if (!await nginxDir.exists()) {
        return (false, 'nginx 未安装，请先安装 nginx');
      }

      // 检查 PHP 是否安装
      final phpDir = Directory('$storagePath/php');
      if (!await phpDir.exists()) {
        return (false, 'PHP 未安装，请先安装 PHP');
      }

      bool hasPhp = false;
      await for (final entity in phpDir.list()) {
        if (entity is Directory) {
          hasPhp = true;
          break;
        }
      }

      if (!hasPhp) {
        return (false, 'PHP 未安装，请先安装 PHP');
      }

      // 步骤2: 检查是否已有同名项目
      onProgress?.call('正在检查项目...', 0.985, '检查是否已有同名项目...');

      final projectName = 'phpmyadmin';
      final servsDir = Directory(path.join(nginxDir.path, 'servs'));
      if (await servsDir.exists()) {
        final projectConfFile = File(
          path.join(servsDir.path, '$projectName.conf'),
        );
        if (await projectConfFile.exists()) {
          return (false, '项目名称 "$projectName" 已存在');
        }
      }

      // 步骤3: 获取默认 PHP 版本
      onProgress?.call('正在获取 PHP 版本...', 0.99, '获取默认 PHP 版本...');

      final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
      final phpBatFile = File(phpBatPath);
      String? defaultPhpVersionId;

      if (await phpBatFile.exists()) {
        try {
          final content = await phpBatFile.readAsString();
          final lines = content.split('\n');
          if (lines.length >= 2) {
            final match = RegExp(r'"([^"]+)"').firstMatch(lines[1]);
            if (match != null) {
              final phpExePath = match.group(1);
              if (phpExePath != null) {
                final phpExeDir = path.dirname(phpExePath);
                defaultPhpVersionId = path.basename(phpExeDir);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('获取默认 PHP 版本失败: $e');
          }
        }
      }

      // 如果没有默认版本，尝试获取第一个已安装的 PHP 版本
      if (defaultPhpVersionId == null) {
        await for (final entity in phpDir.list()) {
          if (entity is Directory) {
            final phpId = path.basename(entity.path);
            final php = softwareSource.php.firstWhere(
              (s) => s.id == phpId,
              orElse: () => Software(
                id: '',
                name: '',
                byte: 0,
                downloadURL: '',
                commands: [],
                attachments: [],
              ),
            );
            if (php.id.isNotEmpty) {
              defaultPhpVersionId = php.id;
              break;
            }
          }
        }
      }

      if (defaultPhpVersionId == null) {
        return (false, '未找到可用的 PHP 版本');
      }

      // 步骤4: 创建普通 PHP 项目
      onProgress?.call('正在创建项目...', 0.995, '创建 phpMyAdmin 项目...');

      // 准备 nginx 项目环境
      final env = await NginxProjectHelper.prepareNginxProjectEnvironment(
        projectName,
        nginxDir.path,
      );
      if (env == null) {
        return (false, '准备 nginx 项目环境失败');
      }

      final lines = env.lines;

      // 配置 nginx 项目参数
      final nginxConfig = <String, dynamic>{
        'port': '80',
        'serverName': 'phpmyadmin.localhost',
        'root': phpmyadminDir.replaceAll('\\', '/'),
        'enableSsl': false,
        'rewriteRule': null,
      };

      // 修改端口
      NginxProjectHelper.updatePort(lines, nginxConfig['port'] as String);

      // 处理 SSL（不启用）
      final sslSuccess = await NginxProjectHelper.handleSslConfig(
        lines,
        nginxConfig,
        projectName,
        env.servsDir,
        (certPath, keyPath) async => false, // 不生成证书
      );
      if (!sslSuccess) {
        return (false, '处理 SSL 配置失败');
      }

      // 修改 server_name
      NginxProjectHelper.updateServerName(
        lines,
        nginxConfig['serverName'] as String? ?? '',
      );

      // 修改 root 路径
      NginxProjectHelper.updateRootPath(
        lines,
        nginxConfig['root'] as String? ?? '',
      );

      // 修改项目名称行
      NginxProjectHelper.updateProjectNameLines(lines, projectName);

      // 确保 PHP 配置文件存在
      onProgress?.call('正在检查 PHP 配置...', 0.995, '检查 PHP nginx 配置文件...');
      final phpConfigResult = await _ensurePhpConfigExists(
        nginxDir.path,
        defaultPhpVersionId,
      );
      if (!phpConfigResult.$1) {
        return (false, phpConfigResult.$2 ?? 'PHP 配置文件检查失败');
      }

      // 修改 PHP include 行
      NginxProjectHelper.updatePhpInclude(lines, defaultPhpVersionId);

      // 创建 subconf 文件（无伪静态规则）
      await NginxProjectHelper.createNormalPhpSubconf(
        projectName,
        null, // 无伪静态规则
        nginxDir.path,
        env.servsDir,
      );

      // 修改 include conf/preconf 行
      NginxProjectHelper.updatePreconfInclude(lines, projectName);

      // 添加数据库配置（不选择相关软件，传入空列表）
      NginxProjectHelper.addDatabaseConfig(lines, []);

      // 完成项目创建
      final serverName = nginxConfig['serverName'] as String? ?? '';
      final success = await NginxProjectHelper.finalizeProjectCreation(
        nginxDir.path,
        env.projectConfFile,
        lines,
        projectName,
        serverName,
        NginxProjectHelper.checkNginxConfig,
        _showNginxConfigErrorDialog,
        _isNginxRunning,
        _reloadNginx,
      );

      if (!success) {
        return (false, '创建项目失败');
      }

      return (true, null);
    } catch (e) {
      return (false, 'phpMyAdmin 初始化失败: $e');
    }
  }

  /// 确保 PHP 配置文件存在（用于普通 PHP 项目）
  Future<(bool success, String? error)> _ensurePhpConfigExists(
    String nginxDir,
    String phpVersionId,
  ) async {
    try {
      final phpConfPath = path.join(
        nginxDir,
        'conf',
        'php',
        '$phpVersionId.conf',
      );
      final phpConfFile = File(phpConfPath);

      if (!await phpConfFile.exists()) {
        // 复制示例文件
        final examplePath = path.join(
          nginxDir,
          'conf',
          'php',
          'php.conf.example',
        );
        final exampleFile = File(examplePath);

        if (!await exampleFile.exists()) {
          return (false, 'PHP 配置示例文件不存在: $examplePath');
        }

        final content = await exampleFile.readAsString();
        // 替换 fastcgi_pass 行中的 #--# 为默认端口（普通 PHP 项目通常使用 9000）
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains('fastcgi_pass') && lines[i].contains('#--#')) {
            lines[i] = lines[i].replaceAll('#--#', '9000');
            break;
          }
        }
        await phpConfFile.writeAsString(lines.join('\n'));
      }
      // 如果文件已存在，不需要更新（普通 PHP 项目不需要动态端口）

      return (true, null);
    } catch (e) {
      return (false, '确保 PHP 配置文件存在失败: $e');
    }
  }

  /// 显示 nginx 配置错误对话框（用于 NginxProjectHelper）
  static Future<void> _showNginxConfigErrorDialog(String output) async {
    // 在安装服务中，我们只记录错误，不显示对话框
    if (kDebugMode) {
      print('nginx 配置检查失败: $output');
    }
  }

  /// 检查 nginx 是否正在运行（用于 NginxProjectHelper）
  static Future<bool> _isNginxRunning() async {
    // 简化实现，总是返回 false（不自动重新加载）
    return false;
  }

  /// 重新加载 nginx（用于 NginxProjectHelper）
  static Future<void> _reloadNginx() async {
    // 在安装服务中，不自动重新加载 nginx
    if (kDebugMode) {
      print('跳过 nginx 重新加载（安装过程中）');
    }
  }
}

