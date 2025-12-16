import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../services/hosts_service.dart';
import '../services/notification_service.dart';

/// Nginx项目配置数据类
class NginxProjectConfig {
  final String projectName;
  final Map<String, dynamic> nginxConfig;
  final List<String> databases;
  final String? phpVersionId;
  final String? framework;
  final String? rewriteRule;

  NginxProjectConfig({
    required this.projectName,
    required this.nginxConfig,
    required this.databases,
    this.phpVersionId,
    this.framework,
    this.rewriteRule,
  });
}

/// Nginx项目创建辅助类
class NginxProjectHelper {
  /// 准备nginx项目的基础环境
  /// 返回 (nginxDir, servsDir, projectConfFile, lines) 或 null
  static Future<({
    String nginxDir,
    Directory servsDir,
    File projectConfFile,
    List<String> lines,
  })?> prepareNginxProjectEnvironment(
    String projectName,
    String nginxDir,
  ) async {
    try {
      final servsDir = Directory(path.join(nginxDir, 'servs'));
      if (!await servsDir.exists()) {
        await servsDir.create(recursive: true);
      }

      // 读取example文件
      final exampleFile = File(path.join(nginxDir, 'dont_delete.conf.example'));
      if (!await exampleFile.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '找不到dont_delete.conf.example文件',
        );
        return null;
      }

      final projectConfFile = File(
        path.join(servsDir.path, '$projectName.conf'),
      );
      final content = await exampleFile.readAsString();
      final lines = content.split('\n');

      return (
        nginxDir: nginxDir,
        servsDir: servsDir,
        projectConfFile: projectConfFile,
        lines: lines,
      );
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '准备nginx项目环境失败: $e',
      );
      return null;
    }
  }

  /// 修改nginx配置文件的端口
  static void updatePort(List<String> lines, String port) {
    if (lines.length >= 2) {
      lines[1] = lines[1].replaceAll(
        RegExp(r'listen\s+\d+'),
        'listen $port',
      );
    }
  }

  /// 处理SSL配置
  /// 返回是否成功，如果返回false表示用户取消或失败
  static Future<bool> handleSslConfig(
    List<String> lines,
    Map<String, dynamic> nginxConfig,
    String projectName,
    Directory servsDir,
    Future<bool> Function(String certPath, String keyPath) generateCert,
  ) async {
    if (nginxConfig['enableSsl'] != true) {
      return true; // 未启用SSL，直接返回成功
    }

    final sslPort = nginxConfig['sslPort'] ?? '443';

    // 修改SSL端口并取消注释
    if (lines.length >= 3) {
      lines[2] = lines[2]
          .replaceAll('#listen', 'listen')
          .replaceAll('#--#', sslPort);
    }
    if (lines.length >= 4) {
      lines[3] = lines[3].replaceAll('#http2', 'http2');
    }

    final certPath = path.join(servsDir.path, '$projectName.pem');
    final keyPath = path.join(servsDir.path, '$projectName.key');

    // 处理证书
    if (nginxConfig['useSelfSignedCert'] == true) {
      // 生成自签证书
      final certGenerated = await generateCert(certPath, keyPath);
      if (!certGenerated) {
        return false; // 用户取消或生成失败
      }
    } else {
      // 写入用户提供的证书和密钥内容
      final userCertContent = nginxConfig['certPath'] as String?;
      final userKeyContent = nginxConfig['keyPath'] as String?;
      if (userCertContent != null && userCertContent.isNotEmpty) {
        await File(certPath).writeAsString(userCertContent);
      }
      if (userKeyContent != null && userKeyContent.isNotEmpty) {
        await File(keyPath).writeAsString(userKeyContent);
      }
    }

    // 修改SSL配置行
    if (lines.length >= 15) {
      lines[14] = lines[14]
          .replaceAll('#ssl_certificate', 'ssl_certificate')
          .replaceAll('#--#', '$projectName.pem');
    }
    if (lines.length >= 16) {
      lines[15] = lines[15]
          .replaceAll('#ssl_certificate_key', 'ssl_certificate_key')
          .replaceAll('#--#', '$projectName.key');
    }
    // 取消其他SSL相关行的注释
    if (lines.length >= 17) lines[16] = lines[16].replaceAll('#', '');
    if (lines.length >= 18) lines[17] = lines[17].replaceAll('#', '');
    if (lines.length >= 21) lines[20] = lines[20].replaceAll('#', '');
    if (lines.length >= 22) lines[21] = lines[21].replaceAll('#', '');
    if (lines.length >= 23) lines[22] = lines[22].replaceAll('#', '');

    return true;
  }

  /// 修改server_name
  static void updateServerName(List<String> lines, String serverName) {
    if (lines.length >= 5) {
      lines[4] = lines[4].replaceAll('#--#', serverName);
    }
  }

  /// 修改root路径
  static void updateRootPath(List<String> lines, String rootPath) {
    if (lines.length >= 8) {
      final normalizedPath = rootPath.replaceAll('\\', '/');
      lines[7] = lines[7].replaceAll('#--#', normalizedPath);
    }
  }

  /// 修改项目名称行（第49、50行）
  static void updateProjectNameLines(List<String> lines, String projectName) {
    if (lines.length >= 49) {
      lines[48] = lines[48].replaceAll('#--#', projectName);
    }
    if (lines.length >= 50) {
      lines[49] = lines[49].replaceAll('#--#', projectName);
    }
  }

  /// 修改PHP include行
  static void updatePhpInclude(List<String> lines, String phpVersionId) {
    if (lines.length >= 12) {
      lines[11] = lines[11].replaceAll('#--#', '$phpVersionId.conf');
    }
  }

  /// 注释PHP include行（用于静态项目）
  static void commentPhpInclude(List<String> lines) {
    if (lines.length >= 12) {
      if (!lines[11].trim().startsWith('#')) {
        lines[11] = '#${lines[11]}';
      }
    }
  }

  /// 创建守护进程项目的subconf文件
  static Future<void> createDaemonSubconf(
    String projectName,
    String framework,
    Map<String, dynamic> nginxConfig,
    String nginxDir,
    Directory servsDir,
  ) async {
    final subconfFile = File(
      path.join(servsDir.path, '$projectName.subconf'),
    );

    if (framework == 'other' &&
        (nginxConfig['customRules'] as String?)?.isEmpty != false) {
      // 没有框架配置也没有自定义规则，创建空文件
      await subconfFile.writeAsString('');
      return;
    }

    final preconfFile = File(
      path.join(nginxDir, 'conf', 'preconf', '$framework.conf'),
    );
    if (!await preconfFile.exists()) {
      await subconfFile.writeAsString('');
      return;
    }

    var subconfContent = await preconfFile.readAsString();
    final subconfLines = subconfContent.split('\n');

    // 取消注释开头的连续#行
    int commentEndIndex = 0;
    for (int i = 0; i < subconfLines.length; i++) {
      if (subconfLines[i].trim().startsWith('#')) {
        subconfLines[i] = subconfLines[i].replaceFirst('#', '');
        commentEndIndex = i + 1;
      } else {
        break;
      }
    }

    // 插入upstream配置
    final upstreamPorts = (nginxConfig['upstreamPorts'] as String).split(',');
    final upstreamLines = upstreamPorts
        .map((port) => '  server 127.0.0.1:${port.trim()};')
        .toList();
    subconfLines.insert(commentEndIndex, upstreamLines.join('\n'));

    // 添加自定义规则
    final customRules = nginxConfig['customRules'] as String?;
    if (customRules != null && customRules.isNotEmpty) {
      subconfLines.add(customRules);
    }

    await subconfFile.writeAsString(subconfLines.join('\n'));
  }

  /// 创建普通PHP项目的subconf文件（伪静态规则）
  static Future<void> createNormalPhpSubconf(
    String projectName,
    String? rewriteRule,
    String nginxDir,
    Directory servsDir,
  ) async {
    final subconfFile = File(
      path.join(servsDir.path, '$projectName.subconf'),
    );

    if (rewriteRule != null && rewriteRule.isNotEmpty) {
      final rewriteConfFile = File(
        path.join(nginxDir, 'conf', 'preconf', '$rewriteRule.conf'),
      );
      if (await rewriteConfFile.exists()) {
        final rewriteContent = await rewriteConfFile.readAsString();
        await subconfFile.writeAsString(rewriteContent);
      } else {
        await subconfFile.writeAsString('');
      }
    } else {
      await subconfFile.writeAsString('');
    }
  }

  /// 创建静态项目的subconf文件（自定义规则）
  static Future<void> createStaticSubconf(
    String projectName,
    String? customRules,
    Directory servsDir,
  ) async {
    final subconfFile = File(
      path.join(servsDir.path, '$projectName.subconf'),
    );
    await subconfFile.writeAsString(customRules ?? '');
  }

  /// 修改include conf/preconf行
  static void updatePreconfInclude(List<String> lines, String projectName) {
    if (lines.length >= 26) {
      lines[25] = lines[25].replaceAll('#--#', 'servs/$projectName.subconf');
    }
  }

  /// 添加数据库配置
  static void addDatabaseConfig(List<String> lines, List<String> databases) {
    final dbConfigLines = <String>['# ENV4PHP_CONF_DONT_EDIT'];
    for (final dbId in databases) {
      dbConfigLines.add('# $dbId');
    }
    lines.addAll(dbConfigLines);
  }

  /// 完成项目创建后的通用操作
  /// 返回是否成功
  static Future<bool> finalizeProjectCreation(
    String nginxDir,
    File projectConfFile,
    List<String> lines,
    String projectName,
    String serverName,
    Future<({bool success, String output})> Function(String nginxDir)
        checkNginxConfig,
    Future<void> Function(String output) showNginxConfigErrorDialog,
    Future<bool> Function() isNginxRunning,
    Future<void> Function() reloadNginx,
  ) async {
    try {
      // 写入配置文件
      await projectConfFile.writeAsString(lines.join('\n'));

      // 检查nginx配置
      final configResult = await checkNginxConfig(nginxDir);
      if (!configResult.success) {
        await showNginxConfigErrorDialog(configResult.output);
        return false;
      }

      // 检查并更新hosts文件
      if (serverName.isNotEmpty) {
        await _checkAndUpdateHosts(serverName);
      }

      await NotificationService.showSuccess(
        title: '创建成功',
        message: '项目 $projectName 创建成功',
      );

      // 如果nginx正在运行，重新加载配置
      if (await isNginxRunning()) {
        await reloadNginx();
      }

      return true;
    } catch (e) {
      await NotificationService.showError(
        title: '创建失败',
        message: '创建项目失败: $e',
      );
      return false;
    }
  }

  /// 检查并更新hosts文件
  static Future<void> _checkAndUpdateHosts(String serverName) async {
    try {
      // 检查是否以.localhost结尾
      if (serverName.endsWith('.localhost')) {
        return; // 以.localhost结尾，无需处理
      }

      // 检查是否为IPv4或IPv6地址
      if (HostsService.isIPv4(serverName) || HostsService.isIPv6(serverName)) {
        return; // 是IP地址，无需处理
      }

      // 不是.localhost结尾，也不是IP地址，需要更新hosts文件
      final success = await HostsService.ensureDomainPointsToLocalhost(
        serverName,
      );
      if (!success) {
        if (kDebugMode) {
          print('更新hosts文件失败: $serverName');
        }
        // 不显示错误，静默处理，避免影响项目创建流程
      }
    } catch (e) {
      if (kDebugMode) {
        print('检查并更新hosts文件时发生错误: $e');
      }
      // 不显示错误，静默处理
    }
  }
}

