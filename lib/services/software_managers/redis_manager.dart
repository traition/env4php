import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../../models/software_model.dart';
import '../notification_service.dart';
import 'software_manager.dart';
import 'software_manager_helper.dart';

/// Redis 软件管理器
/// 注意：Redis 使用进程管理，需要跟踪 PID
class RedisManager extends SoftwareManager {
  @override
  String get supportedCate4 => 'redis';

  /// 进程ID存储（由调用者管理）
  final Map<String, int> _processIds = {};

  /// 设置进程ID（由调用者调用）
  void setProcessId(String serverId, int pid) {
    _processIds[serverId] = pid;
  }

  /// 获取进程ID
  int? getProcessId(String serverId) {
    return _processIds[serverId];
  }

  /// 清除进程ID
  void clearProcessId(String serverId) {
    _processIds.remove(serverId);
  }

  /// 获取 Redis 目录
  Future<String?> _getRedisDirectory(String redisId) async {
    return await SoftwareManagerHelper.getSoftwareDirectory(redisId, 'servers');
  }

  /// 通过进程名查找进程ID
  Future<int?> _findProcessIdByName() async {
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq redis-server.exe',
        '/FO',
        'CSV',
        '/NH',
      ], runInShell: true);

      final output = result.stdout.toString();
      if (output.isNotEmpty && output.contains('redis-server.exe')) {
        // 解析PID（CSV格式："进程名","PID","会话名","会话#","内存使用"）
        final lines = output.split('\n');
        for (final line in lines) {
          if (line.contains('redis-server.exe')) {
            final parts = line.split(',');
            if (parts.length >= 2) {
              final pidStr = parts[1].replaceAll('"', '').trim();
              final pid = int.tryParse(pidStr);
              if (pid != null) {
                if (kDebugMode) {
                  print('[Redis] 通过进程名找到进程ID: $pid');
                }
                return pid;
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[Redis] 查找进程ID失败: $e');
      }
      return null;
    }
  }

  @override
  Future<(bool success, String? error)> start(Software server) async {
    try {
      // 检查是否有暂存的PID，如果有则先停止旧进程
      final existingPid = _processIds[server.id];
      if (existingPid != null) {
        if (kDebugMode) {
          print('[Redis启动] 发现暂存的PID: $existingPid，先停止旧进程');
        }
        try {
          await Process.run('taskkill', [
            '/F',
            '/T',
            '/PID',
            existingPid.toString(),
          ], runInShell: true);
        } catch (e) {
          if (kDebugMode) {
            print('[Redis启动] 停止旧进程失败（可能进程已不存在）: $e');
          }
        }
        // 清除暂存的PID
        _processIds.remove(server.id);
      }

      final redisDir = await _getRedisDirectory(server.id);
      if (redisDir == null) {
        await NotificationService.showError(
          title: '启动失败',
          message: 'Redis未安装或目录不存在',
        );
        return (false, 'Redis未安装或目录不存在');
      }

      final redisServerExe = path.join(redisDir, 'redis-server.exe');
      final redisServerFile = File(redisServerExe);
      if (!await redisServerFile.exists()) {
        await NotificationService.showError(
          title: '启动失败',
          message: '找不到redis-server.exe文件: $redisServerExe',
        );
        return (false, '找不到redis-server.exe文件: $redisServerExe');
      }

      final redisConf = path.join(redisDir, 'redis.windows.conf');
      final redisConfFile = File(redisConf);
      if (!await redisConfFile.exists()) {
        await NotificationService.showError(
          title: '启动失败',
          message: '找不到redis.windows.conf文件: $redisConf',
        );
        return (false, '找不到redis.windows.conf文件: $redisConf');
      }

      // 执行启动命令: redis-server.exe redis.windows.conf
      if (kDebugMode) {
        print('[Redis启动] 执行命令: $redisServerExe $redisConf');
      }

      final process = await Process.start(
        redisServerExe,
        [redisConf],
        workingDirectory: redisDir,
        mode: ProcessStartMode.normal,
      );

      // 记录进程ID
      final pid = process.pid;
      if (kDebugMode) {
        print('[Redis启动] 进程ID: $pid');
      }

      // 监听输出以判断启动是否成功
      bool startupSuccess = false;
      bool startupFailed = false;

      // 消费 stdout
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        if (data.contains('Ready to accept connections')) {
          startupSuccess = true;
        }
        if (data.contains('Could not create server TCP listening socket')) {
          startupFailed = true;
        }
      });

      // 消费 stderr
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        if (kDebugMode) {
          print('[Redis启动] stderr: $data');
        }
        if (data.contains('Could not create server TCP listening socket')) {
          startupFailed = true;
        }
      });

      // 等待一段时间以便 Redis 启动并输出日志
      await Future.delayed(const Duration(seconds: 3));

      if (startupSuccess) {
        // 启动成功
        _processIds[server.id] = pid;
        await NotificationService.showSuccess(
          title: '启动成功',
          message: '${server.name} 已启动（进程ID: $pid）',
        );
        return (true, null);
      } else if (startupFailed) {
        // 启动失败
        // 杀死进程
        try {
          await Process.run('taskkill', [
            '/F',
            '/T',
            '/PID',
            pid.toString(),
          ], runInShell: true);
        } catch (e) {
          if (kDebugMode) {
            print('[Redis启动失败] 清理进程失败: $e');
          }
        }

        await NotificationService.showError(
          title: '启动失败',
          message: 'Redis启动失败: 端口被占用',
        );
        return (false, 'Redis启动失败: 端口被占用');
      } else {
        // 未检测到明确的成功或失败信号，暂存PID并提示用户
        _processIds[server.id] = pid;
        await NotificationService.showInfo(
          title: '启动完成',
          message: '${server.name} 启动命令已执行（进程ID: $pid）',
        );
        return (true, null);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[Redis启动失败] 发生异常: $e');
        print('[Redis启动失败] 堆栈跟踪: $stackTrace');
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
      int? processId = _processIds[server.id];

      // 尝试通过进程名查找
      processId ??= await _findProcessIdByName();

      if (processId == null) {
        _processIds.remove(server.id);
        return (true, null);
      }

      await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        processId.toString(),
      ], runInShell: true);

      _processIds.remove(server.id);
      return (true, null);
    } catch (e) {
      if (kDebugMode) {
        print('[静默停止Redis] 发生异常: $e');
      }
      _processIds.remove(server.id);
      return (true, null); // 即使失败也返回成功，因为进程可能已经停止
    }
  }

  @override
  Future<(bool success, String? error)> stop(Software server) async {
    try {
      int? processId = _processIds[server.id];

      if (processId == null) {
        // 尝试通过进程名查找
        if (kDebugMode) {
          print('[Redis停止] 未找到暂存的PID，尝试通过进程名查找');
        }
        processId = await _findProcessIdByName();
      }

      if (processId == null) {
        // 仍然找不到PID，可能进程已经停止
        _processIds.remove(server.id);
        await NotificationService.showInfo(
          title: '提示',
          message: '${server.name} 进程可能已经停止',
        );
        return (true, null);
      }

      if (kDebugMode) {
        print('[Redis停止] 正在停止进程ID: $processId');
      }

      // 使用 taskkill 结束进程树
      final result = await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        processId.toString(),
      ], runInShell: true);

      if (result.exitCode == 0) {
        if (kDebugMode) {
          print('[Redis停止] 进程树已成功终止');
        }
        _processIds.remove(server.id);
        await NotificationService.showSuccess(
          title: '停止成功',
          message: '${server.name} 已停止',
        );
        return (true, null);
      } else {
        // 进程可能已经不存在
        if (kDebugMode) {
          print('[Redis停止] taskkill退出码: ${result.exitCode}，进程可能已不存在');
        }
        _processIds.remove(server.id);
        await NotificationService.showInfo(
          title: '提示',
          message: '${server.name} 进程可能已经停止',
        );
        return (true, null);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Redis停止失败] 发生异常: $e');
      }
      _processIds.remove(server.id);
      await NotificationService.showError(
        title: '停止失败',
        message: '停止 ${server.name} 时发生错误: $e',
      );
      return (false, '停止失败: $e');
    }
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
}
