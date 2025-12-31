import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../../models/software_model.dart';
import '../notification_service.dart';
import 'software_manager.dart';

/// MongoDB 软件管理器
class MongodbManager extends InitializableSoftwareManager {
  @override
  String get supportedCate4 => 'mongodb';

  /// 检查 MongoDB 服务是否正在运行
  Future<bool> _isServiceRunning() async {
    try {
      final result = await Process.run('sc', [
        'query',
        'MongoDB',
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
        print('[MongoDB状态检查] 发生异常: $e');
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

      // 执行 net start MongoDB
      if (kDebugMode) {
        print('[MongoDB启动] 执行 net start MongoDB');
      }
      final result = await Process.run('net', [
        'start',
        'MongoDB',
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
        print('[MongoDB启动失败] 发生异常: $e');
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

      // 执行 net stop MongoDB
      if (kDebugMode) {
        print('[MongoDB停止] 执行 net stop MongoDB');
      }
      final result = await Process.run('net', [
        'stop',
        'MongoDB',
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
        print('[MongoDB停止失败] 发生异常: $e');
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
    String mongodbDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 执行 mongod --config "mongodb目录\mongod.cfg" --install --serviceName "MongoDB"
      onProgress?.call('正在注册 MongoDB 服务...', 0.98, '执行 mongod --install...');
      // 先检查根目录，如果不存在再检查 bin 目录
      String mongodExe = path.join(mongodbDir, 'mongod.exe');
      File mongodFile = File(mongodExe);

      if (!await mongodFile.exists()) {
        // 如果根目录不存在，检查 bin 目录
        mongodExe = path.join(mongodbDir, 'bin', 'mongod.exe');
        mongodFile = File(mongodExe);
        if (!await mongodFile.exists()) {
          return (false, '未找到 mongod.exe 文件（已检查根目录和 bin 目录）');
        }
      }

      final mongodCfg = path.join(mongodbDir, 'mongod.cfg');
      final mongodCfgFile = File(mongodCfg);

      if (!await mongodCfgFile.exists()) {
        return (false, '未找到 mongod.cfg 文件: $mongodCfg');
      }

      final installResult = await Process.run(
        mongodExe,
        ['--config', mongodCfg, '--install', '--serviceName', 'MongoDB'],
        runInShell: true,
        workingDirectory: mongodbDir,
      );

      if (installResult.exitCode != 0) {
        final errorOutput = installResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'MongoDB 服务注册警告',
            0.98,
            'mongod --install 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（服务可能已经注册）
      } else {
        onProgress?.call('MongoDB 服务注册', 0.98, 'mongod --install 完成');
      }

      // 步骤2: 执行 sc config MongoDB start= demand
      onProgress?.call(
        '正在配置 MongoDB 服务...',
        0.99,
        '执行 sc config MongoDB start= demand...',
      );
      final configResult = await Process.run('sc', [
        'config',
        'MongoDB',
        'start=',
        'demand',
      ], runInShell: true);

      if (configResult.exitCode != 0) {
        final errorOutput = configResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'MongoDB 服务配置警告',
            0.99,
            'sc config 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续（服务可能已经配置）
      } else {
        onProgress?.call('MongoDB 服务配置', 0.99, 'sc config 完成');
      }

      return (true, null);
    } catch (e) {
      return (false, 'MongoDB 初始化失败: $e');
    }
  }
}

