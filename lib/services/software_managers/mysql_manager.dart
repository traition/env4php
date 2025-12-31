import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../../models/software_model.dart';
import '../config_service.dart';
import '../notification_service.dart';
import 'software_manager.dart';

/// MySQL 软件管理器
class MysqlManager extends InitializableSoftwareManager {
  @override
  String get supportedCate4 => 'mysql';

  /// 获取 MySQL 安装目录
  Future<String?> _getMysqlDirectory(String mysqlId) async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    // MySQL可能在servers或databases目录下
    final serversDir = Directory(path.join(storagePath, 'servers', mysqlId));
    final databasesDir = Directory(
      path.join(storagePath, 'databases', mysqlId),
    );

    if (await serversDir.exists()) {
      return serversDir.path;
    } else if (await databasesDir.exists()) {
      return databasesDir.path;
    }
    return null;
  }

  @override
  Future<(bool success, String? error)> start(Software server) async {
    try {
      final mysqlDir = await _getMysqlDirectory(server.id);
      if (mysqlDir == null) {
        return (false, 'MySQL未安装或目录不存在');
      }

      // 步骤1: 先执行 sc stop mysql（停止服务）
      if (kDebugMode) {
        print('[MySQL启动] 执行 sc stop mysql');
      }
      final stopResult = await Process.run('sc', [
        'stop',
        'mysql',
      ], runInShell: true);

      // 忽略停止失败的错误（服务可能未运行）
      if (stopResult.exitCode != 0) {
        if (kDebugMode) {
          print('[MySQL启动] sc stop mysql 退出码: ${stopResult.exitCode}');
        }
      } else {
        if (kDebugMode) {
          print('[MySQL启动] MySQL服务已停止');
        }
        // 等待一小段时间确保服务完全停止
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 步骤2: 尝试启动服务
      if (kDebugMode) {
        print('[MySQL启动] 执行 sc start mysql');
      }
      final startResult = await Process.run('sc', [
        'start',
        'mysql',
      ], runInShell: true);

      // 检查是否报错 "[SC] OpenService 失败 1060:指定的服务未安装。"
      final errorOutput = startResult.stderr.toString();
      if (errorOutput.contains('1060') ||
          errorOutput.contains('指定的服务未安装') ||
          errorOutput.toLowerCase().contains('service does not exist')) {
        // 服务未安装，需要安装服务
        if (kDebugMode) {
          print('[MySQL启动] MySQL服务未安装，开始安装服务');
        }

        final mysqldExe = path.join(mysqlDir, 'bin', 'mysqld.exe');
        final mysqldFile = File(mysqldExe);
        if (!await mysqldFile.exists()) {
          return (false, '找不到mysqld.exe文件: $mysqldExe');
        }

        // 执行 mysqld -install
        if (kDebugMode) {
          print('[MySQL启动] 执行 mysqld -install');
        }
        final installResult = await Process.run(
          mysqldExe,
          ['-install'],
          runInShell: true,
          workingDirectory: mysqlDir,
        );

        if (installResult.exitCode != 0) {
          final installError = installResult.stderr.toString();
          return (false, '安装MySQL服务失败: $installError');
        }

        if (kDebugMode) {
          print('[MySQL启动] MySQL服务安装成功');
        }

        // 等待一小段时间确保服务安装完成
        await Future.delayed(const Duration(milliseconds: 500));

        // 再次尝试启动服务
        if (kDebugMode) {
          print('[MySQL启动] 再次执行 sc start mysql');
        }
        final retryStartResult = await Process.run('sc', [
          'start',
          'mysql',
        ], runInShell: true);

        if (retryStartResult.exitCode == 0) {
          return (true, null);
        } else {
          final retryError = retryStartResult.stderr.toString();
          return (false, '启动MySQL服务失败: $retryError');
        }
      } else if (startResult.exitCode == 0) {
        // 启动成功
        return (true, null);
      } else {
        // 启动失败
        return (false, '启动MySQL服务失败: $errorOutput');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[MySQL启动失败] 发生异常: $e');
      }
      return (false, '启动 ${server.name} 时发生错误: $e');
    }
  }

  @override
  Future<(bool success, String? error)> stopSilently(Software server) async {
    try {
      // 执行 sc stop mysql
      if (kDebugMode) {
        print('[MySQL停止] 执行 sc stop mysql');
      }
      final result = await Process.run('sc', [
        'stop',
        'mysql',
      ], runInShell: true);

      if (result.exitCode == 0) {
        return (true, null);
      } else {
        final errorOutput = result.stderr.toString();
        // 如果服务未运行或服务尚未启动，也视为成功
        if (errorOutput.contains('1062') ||
            errorOutput.contains('服务尚未启动') ||
            errorOutput.toLowerCase().contains('service does not exist') ||
            errorOutput.contains('指定的服务未安装') ||
            errorOutput.toLowerCase().contains('not running')) {
          return (true, null);
        } else {
          return (false, '停止 ${server.name} 失败: $errorOutput');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[MySQL停止失败] 发生异常: $e');
      }
      return (false, '停止 ${server.name} 时发生错误: $e');
    }
  }

  @override
  Future<(bool success, String? error)> stop(Software server) async {
    final result = await stopSilently(server);
    if (result.$1) {
      await NotificationService.showSuccess(
        title: '停止成功',
        message: '${server.name} 已停止',
      );
    } else {
      final errorOutput = result.$2 ?? '未知错误';
      // 检查是否是"服务未运行"的情况
      if (errorOutput.contains('1062') ||
          errorOutput.contains('服务尚未启动') ||
          errorOutput.toLowerCase().contains('service does not exist') ||
          errorOutput.contains('指定的服务未安装') ||
          errorOutput.toLowerCase().contains('not running')) {
        await NotificationService.showInfo(
          title: '提示',
          message: '${server.name} 服务未运行',
        );
        return (true, null);
      } else {
        await NotificationService.showError(
          title: '停止失败',
          message: result.$2 ?? '停止失败',
        );
      }
    }
    return result;
  }

  @override
  Future<(bool success, String? error)> restart(Software server) async {
    // 先停止
    final stopResult = await stop(server);
    if (!stopResult.$1) {
      return stopResult;
    }
    // 等待一小段时间
    await Future.delayed(const Duration(milliseconds: 500));
    // 再启动
    return await start(server);
  }

  @override
  Future<(bool success, String? error)> initialize(
    String mysqlDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 执行 mysqld --initialize-insecure
      onProgress?.call(
        '正在初始化 MySQL...',
        0.98,
        '执行 mysqld --initialize-insecure...',
      );
      final mysqldExe = path.join(mysqlDir, 'bin', 'mysqld.exe');
      final mysqldFile = File(mysqldExe);

      if (!await mysqldFile.exists()) {
        return (false, '未找到 mysqld.exe 文件: $mysqldExe');
      }

      final result = await Process.run(
        mysqldExe,
        ['--initialize-insecure'],
        runInShell: true,
        workingDirectory: mysqlDir,
      );

      if (result.exitCode != 0) {
        final errorOutput = result.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call('MySQL 初始化警告', 0.98, 'mysqld 初始化输出: $errorOutput');
        }
        // 即使退出码非0，也继续执行后续步骤（某些情况下可能已经初始化成功）
      } else {
        onProgress?.call('MySQL 初始化', 0.98, 'mysqld 初始化完成');
      }

      // 步骤1.5: 执行 mysqld -install
      onProgress?.call('正在安装 MySQL 服务...', 0.982, '执行 mysqld install...');
      final installResult = await Process.run(
        mysqldExe,
        ['--install-manual'],
        runInShell: true,
        workingDirectory: mysqlDir,
      );

      if (installResult.exitCode != 0) {
        final errorOutput = installResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'MySQL 服务安装警告',
            0.982,
            'mysqld -install 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（服务可能已经安装）
      } else {
        onProgress?.call('MySQL 服务安装', 0.982, 'mysqld 服务安装完成');
      }

      return (true, null);
    } catch (e) {
      return (false, 'MySQL 初始化失败: $e');
    }
  }
}

