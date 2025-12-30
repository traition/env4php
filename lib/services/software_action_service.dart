import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/notification_service.dart';
import '../utils/software_menu_helper.dart';
import '../pages/software_management_page.dart' show LogViewerDialog;

/// 软件操作服务类
/// 提供统一的软件管理操作，供控制台页面和软件管理页面共同使用
class SoftwareActionService {
  /// 获取软件目录路径
  static Future<String?> getSoftwareDirectory(
    Software software, {
    SoftwareSource? softwareSource,
  }) async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    // 如果没有提供软件源，则从服务中获取
    final source = softwareSource ?? await SoftwareSourceService.getSource();
    if (source == null) return null;

    // 确定软件类别
    String category;
    if (source.servers.any((s) => s.id == software.id)) {
      category = 'servers';
    } else if (source.databases.any((s) => s.id == software.id)) {
      category = 'databases';
    } else if (source.php.any((s) => s.id == software.id)) {
      category = 'php';
    } else {
      category = 'tools';
    }

    final softwareDir = Directory('$storagePath/$category/${software.id}');
    if (!await softwareDir.exists()) return null;

    return softwareDir.path;
  }

  /// 编辑 nginx.conf
  static Future<void> editNginxConfig(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'conf', 'nginx.conf'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'nginx.conf 文件不存在: ${configFile.path}',
      );
      return;
    }

    // 使用 PowerShell 执行 explorer 命令打开文件
    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('打开文件失败: $e');
      }
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e\n文件路径: ${configFile.path}',
      );
    }
  }

  /// 查看 error.log
  static Future<void> viewErrorLog(
    Software software, {
    required BuildContext context,
    required GlobalKey<NavigatorState>? navigatorKey,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final logFile = File(path.join(softwareDir, 'logs', 'error.log'));
    if (!await logFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'error.log 文件不存在',
      );
      return;
    }

    // 显示文本查看器对话框
    final pageContext = navigatorKey?.currentContext ?? context;
    await showDialog(
      context: pageContext,
      useRootNavigator: false,
      builder: (context) => LogViewerDialog(logFile: logFile),
    );
  }

  /// 编辑 redis 配置
  static Future<void> editRedisConfig(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'redis.windows.conf'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'redis.windows.conf 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 编辑 rudis 配置
  static Future<void> editRudisConfig(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(
      path.join(softwareDir, 'rudis-server.properties'),
    );
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'rudis-server.properties 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 编辑 mysql.ini
  static Future<void> editMysqlIni(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'mysql.ini'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'mysql.ini 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 编辑 mongodb 配置
  static Future<void> editMongodbConfig(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'mongod.cfg'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'mongod.cfg 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 编辑 postgresql.conf
  static Future<void> editPgsqlConf(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'data', 'postgresql.conf'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'postgresql.conf 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 编辑 pg_hba.conf
  static Future<void> editPgsqlHba(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'data', 'pg_hba.conf'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'pg_hba.conf 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 编辑 pg_ident.conf
  static Future<void> editPgsqlIdent(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'data', 'pg_ident.conf'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'pg_ident.conf 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 设为 php-cli 版本
  static Future<void> setPhpCliVersion(
    Software software, {
    required BuildContext context,
  }) async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) {
      await NotificationService.showError(
        title: '错误',
        message: '存储目录未设置',
      );
      return;
    }

    final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
    final phpBatFile = File(phpBatPath);
    if (!await phpBatFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'php.bat 文件不存在',
      );
      return;
    }

    final phpExePath = path.join(storagePath, 'php', software.id, 'php.exe');
    final phpExeFile = File(phpExePath);
    if (!await phpExeFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'PHP 可执行文件不存在: $phpExePath',
      );
      return;
    }

    try {
      final content = '@echo off\n"$phpExePath" %*\n';
      await phpBatFile.writeAsString(content);
      await NotificationService.showSuccess(
        title: '设置成功',
        message: '已将 ${software.name} 设为默认 PHP CLI 版本',
      );
    } catch (e) {
      await NotificationService.showError(
        title: '设置失败',
        message: '设置 PHP CLI 版本时发生错误: $e',
      );
    }
  }

  /// 编辑 php.ini
  static Future<void> editPhpIni(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    final configFile = File(path.join(softwareDir, 'php.ini'));
    if (!await configFile.exists()) {
      await NotificationService.showError(
        title: '错误',
        message: 'php.ini 文件不存在: ${configFile.path}',
      );
      return;
    }

    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      final command = 'explorer "$filePath"';
      final result = await Process.run(
        'powershell',
        ['-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '无法打开文件: $e',
      );
    }
  }

  /// 安装 PHP 扩展（占位函数）
  static void installPhpExtension(
    Software software, {
    required BuildContext context,
  }) {
    NotificationService.showInfo(
      title: '提示',
      message: '安装扩展（功能待实现）',
    );
  }

  /// 打开软件目录
  static Future<void> openSoftwareDirectory(
    Software software, {
    required BuildContext context,
    SoftwareSource? softwareSource,
  }) async {
    final softwareDir = await getSoftwareDirectory(
      software,
      softwareSource: softwareSource,
    );
    if (softwareDir == null) {
      await NotificationService.showError(
        title: '错误',
        message: '无法获取软件目录',
      );
      return;
    }

    // 在 Windows 上使用 explorer 打开目录
    try {
      final dir = Directory(softwareDir);
      if (!await dir.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '目录不存在: $softwareDir',
        );
        return;
      }
      final dirPath = softwareDir.replaceAll('/', '\\');
      final result = await Process.run('explorer', [dirPath], runInShell: true);
      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('打开目录失败: $e');
      }
      await NotificationService.showError(
        title: '错误',
        message: '无法打开目录: $e\n目录路径: $softwareDir',
      );
    }
  }

  /// 统一处理菜单操作
  static Future<void> handleMenuAction(
    SoftwareMenuAction action,
    Software software, {
    required BuildContext context,
    GlobalKey<NavigatorState>? navigatorKey,
    SoftwareSource? softwareSource,
  }) async {
    try {
      switch (action) {
        case SoftwareMenuAction.editNginxConfig:
          await editNginxConfig(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.viewLog:
          await viewErrorLog(
            software,
            context: context,
            navigatorKey: navigatorKey,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.editRedisConfig:
          await editRedisConfig(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.editRudisConfig:
          await editRudisConfig(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.editMysqlIni:
          await editMysqlIni(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.editMongodbConfig:
          await editMongodbConfig(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.editPgsqlConf:
          await editPgsqlConf(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.editPgsqlHba:
          await editPgsqlHba(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.editPgsqlIdent:
          await editPgsqlIdent(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.setPhpCliVersion:
          await setPhpCliVersion(software, context: context);
          break;
        case SoftwareMenuAction.editPhpIni:
          await editPhpIni(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        case SoftwareMenuAction.installPhpExtension:
          installPhpExtension(software, context: context);
          break;
        case SoftwareMenuAction.openDirectory:
          await openSoftwareDirectory(
            software,
            context: context,
            softwareSource: softwareSource,
          );
          break;
        default:
          if (kDebugMode) {
            print('未实现的菜单操作: $action');
          }
          break;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('处理菜单操作时发生错误: $e');
        print('堆栈跟踪: $stackTrace');
      }
      await NotificationService.showError(
        title: '操作失败',
        message: '执行操作时发生错误: $e',
      );
    }
  }
}

