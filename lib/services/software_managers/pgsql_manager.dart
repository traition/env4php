import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../../models/software_model.dart';
import '../notification_service.dart';
import 'software_manager.dart';

/// PostgreSQL 软件管理器
class PgsqlManager extends InitializableSoftwareManager {
  @override
  String get supportedCate4 => 'pgsql';

  /// 检查 PostgreSQL 服务是否正在运行
  Future<bool> _isServiceRunning() async {
    try {
      final result = await Process.run('sc', [
        'query',
        'PostgreSQL',
      ], runInShell: true);

      if (result.exitCode != 0) {
        // 服务不存在或查询失败
        return false;
      }

      final output = result.stdout.toString();
      // 检查服务状态，如果包含 "RUNNING" 则表示服务正在运行
      return output.contains('RUNNING');
    } catch (e) {
      if (kDebugMode) {
        print('[PostgreSQL状态检查] 发生异常: $e');
      }
      return false;
    }
  }

  @override
  Future<(bool success, String? error)> start(Software server) async {
    try {
      // 先检查服务是否已经启动
      final isRunning = await _isServiceRunning();
      if (isRunning) {
        await NotificationService.showInfo(
          title: '提示',
          message: '${server.name} 服务已经启动',
        );
        return (true, null);
      }

      // 执行 net start PostgreSQL
      if (kDebugMode) {
        print('[PostgreSQL启动] 执行 net start PostgreSQL');
      }
      final result = await Process.run('net', [
        'start',
        'PostgreSQL',
      ], runInShell: true);

      if (result.exitCode == 0) {
        // 启动成功
        await NotificationService.showSuccess(
          title: '启动成功',
          message: '${server.name} 已启动',
        );
        return (true, null);
      } else {
        final errorOutput = result.stderr.toString();
        // 检查是否服务已经启动
        final output = result.stdout.toString() + errorOutput;
        if (output.toLowerCase().contains('already started') ||
            output.toLowerCase().contains('已经启动') ||
            output.toLowerCase().contains('is already running')) {
          await NotificationService.showInfo(
            title: '提示',
            message: '${server.name} 服务已经启动',
          );
          return (true, null);
        } else {
          await NotificationService.showError(
            title: '启动失败',
            message: '启动 ${server.name} 失败: $errorOutput',
          );
          return (false, '启动失败: $errorOutput');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[PostgreSQL启动失败] 发生异常: $e');
      }
      await NotificationService.showError(
        title: '启动失败',
        message: '启动 ${server.name} 时发生错误: $e',
      );
      return (false, '启动失败: $e');
    }
  }

  @override
  Future<(bool success, String? error)> stopSilently(Software server) async {
    try {
      // 先检查服务是否已经停止
      final isRunning = await _isServiceRunning();
      if (!isRunning) {
        return (true, null);
      }

      // 执行 net stop PostgreSQL
      if (kDebugMode) {
        print('[PostgreSQL停止] 执行 net stop PostgreSQL');
      }
      final result = await Process.run('net', [
        'stop',
        'PostgreSQL',
      ], runInShell: true);

      if (result.exitCode == 0) {
        return (true, null);
      } else {
        final errorOutput = result.stderr.toString();
        // 检查是否服务已经停止
        final output = result.stdout.toString() + errorOutput;
        if (output.toLowerCase().contains('not started') ||
            output.toLowerCase().contains('尚未启动') ||
            output.toLowerCase().contains('is not running') ||
            output.toLowerCase().contains('not running')) {
          return (true, null);
        } else {
          return (false, '停止失败: $errorOutput');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[PostgreSQL停止失败] 发生异常: $e');
      }
      return (false, '停止失败: $e');
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
      if (errorOutput.toLowerCase().contains('not started') ||
          errorOutput.toLowerCase().contains('尚未启动') ||
          errorOutput.toLowerCase().contains('is not running') ||
          errorOutput.toLowerCase().contains('not running')) {
        await NotificationService.showInfo(
          title: '提示',
          message: '${server.name} 服务已经停止',
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
    String pgsqlDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 执行 initdb.exe -D "pgsql目录\data" -E UTF-8 -U postgres
      onProgress?.call('正在初始化 PostgreSQL...', 0.98, '执行 initdb.exe 初始化数据库...');
      final initdbExe = path.join(pgsqlDir, 'bin', 'initdb.exe');
      final initdbFile = File(initdbExe);

      if (!await initdbFile.exists()) {
        return (false, '未找到 initdb.exe 文件: $initdbExe');
      }

      final dataDir = path.join(pgsqlDir, 'data');
      final initdbResult = await Process.run(
        initdbExe,
        ['-D', dataDir, '-E', 'UTF-8', '-U', 'postgres'],
        runInShell: true,
        workingDirectory: pgsqlDir,
      );

      if (initdbResult.exitCode != 0) {
        final errorOutput = initdbResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'PostgreSQL 初始化警告',
            0.98,
            'initdb 初始化输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（某些情况下可能已经初始化成功）
      } else {
        onProgress?.call('PostgreSQL 初始化', 0.98, 'initdb 初始化完成');
      }

      // 步骤2: 执行 pg_ctl.exe register -D "pgsql目录\data" -N PostgreSQL
      onProgress?.call(
        '正在注册 PostgreSQL 服务...',
        0.985,
        '执行 pg_ctl.exe register...',
      );
      final pgCtlExe = path.join(pgsqlDir, 'bin', 'pg_ctl.exe');
      final pgCtlFile = File(pgCtlExe);

      if (!await pgCtlFile.exists()) {
        return (false, '未找到 pg_ctl.exe 文件: $pgCtlExe');
      }

      final registerResult = await Process.run(
        pgCtlExe,
        ['register', '-D', dataDir, '-N', 'PostgreSQL'],
        runInShell: true,
        workingDirectory: pgsqlDir,
      );

      if (registerResult.exitCode != 0) {
        final errorOutput = registerResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'PostgreSQL 服务注册警告',
            0.985,
            'pg_ctl register 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（服务可能已经注册）
      } else {
        onProgress?.call('PostgreSQL 服务注册', 0.985, 'pg_ctl register 完成');
      }

      // 步骤3: 执行 sc config PostgreSQL start= demand
      onProgress?.call(
        '正在配置 PostgreSQL 服务...',
        0.99,
        '执行 sc config PostgreSQL start= demand...',
      );
      final configResult = await Process.run('sc', [
        'config',
        'PostgreSQL',
        'start=',
        'demand',
      ], runInShell: true);

      if (configResult.exitCode != 0) {
        final errorOutput = configResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'PostgreSQL 服务配置警告',
            0.99,
            'sc config 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续（服务可能已经配置）
      } else {
        onProgress?.call('PostgreSQL 服务配置', 0.99, 'sc config 完成');
      }

      return (true, null);
    } catch (e) {
      return (false, 'PostgreSQL 初始化失败: $e');
    }
  }
}

