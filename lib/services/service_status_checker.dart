import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import 'config_service.dart';
import 'software_source_service.dart';
import 'software_managers/software_manager_factory.dart';
import 'software_managers/software_manager_helper.dart';

/// 服务状态检查器
/// 用于检查服务的实际运行状态
class ServiceStatusChecker {
  /// 检查服务是否实际运行
  /// [server] 服务器软件对象
  /// 返回 true 表示服务正在运行，false 表示未运行
  static Future<bool> checkServiceStatus(Software server) async {
    final cate4 = server.cate4?.toLowerCase();
    if (cate4 == null) return false;

    try {
      switch (cate4) {
        case 'nginx':
          return await _checkNginxStatus(server);
        case 'mysql':
        case 'pgsql':
          return await _checkWindowsServiceStatus(server);
        case 'redis':
        case 'rudis':
          return await _checkRedisStatus(server);
        case 'php':
          return await _checkPhpStatus(server);
        case 'mongodb':
          return await _checkMongodbStatus(server);
        default:
          // 对于其他类型的服务，尝试使用管理器检查
          final manager = SoftwareManagerFactory.getManager(server);
          if (manager != null) {
            // 如果管理器有 isRunning 方法，使用它
            // 否则返回 false（表示无法检查）
            return false;
          }
          return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[服务状态检查] 检查 ${server.name} 状态时发生错误: $e');
      }
      return false;
    }
  }

  /// 检查 Nginx 是否运行
  static Future<bool> _checkNginxStatus(Software server) async {
    try {
      final nginxDir = await SoftwareManagerHelper.getNginxDirectory();
      if (nginxDir == null) return false;

      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) return false;

      // 使用 tasklist 检查 nginx.exe 进程是否存在
      final result = await Process.run(
        'tasklist',
        ['/FI', 'IMAGENAME eq nginx.exe', '/FO', 'CSV', '/NH'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        // 检查输出中是否包含 nginx.exe
        if (output.isNotEmpty && output.contains('nginx.exe')) {
          // 进一步验证：检查进程的可执行文件路径是否匹配
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains('nginx.exe')) {
              final parts = line.split(',');
              if (parts.length >= 2) {
                final pidStr = parts[1].replaceAll('"', '').trim();
                final pid = int.tryParse(pidStr);
                if (pid != null) {
                  // 使用 PowerShell 验证进程路径
                  try {
                    final psResult = await Process.run(
                      'powershell',
                      [
                        '-NoProfile',
                        '-Command',
                        '(Get-Process -Id $pid -ErrorAction SilentlyContinue).Path',
                      ],
                      runInShell: true,
                      environment: {'pid': pid.toString()},
                    );

                    if (psResult.exitCode == 0) {
                      final exePath = psResult.stdout.toString().trim();
                      if (exePath.isNotEmpty) {
                        final normalizedExePath = path.normalize(exePath);
                        final normalizedNginxExe = path.normalize(nginxExe);
                        if (normalizedExePath.toLowerCase() ==
                            normalizedNginxExe.toLowerCase()) {
                          return true;
                        }
                      }
                    }
                  } catch (e) {
                    // PowerShell 命令失败，但进程存在，假设是 nginx
                    if (kDebugMode) {
                      print('[服务状态检查] 验证 Nginx 进程路径失败: $e');
                    }
                    return true;
                  }
                }
              }
            }
          }
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[服务状态检查] 检查 Nginx 状态失败: $e');
      }
      return false;
    }
  }

  /// 检查 Windows 服务状态（MySQL、PostgreSQL 等）
  static Future<bool> _checkWindowsServiceStatus(Software server) async {
    try {
      // 根据服务类型确定服务名称
      String serviceName;
      if (server.cate4?.toLowerCase() == 'mysql') {
        serviceName = 'mysql';
      } else if (server.cate4?.toLowerCase() == 'pgsql') {
        serviceName = 'postgresql-x64-${server.id}'; // PostgreSQL 服务名格式
      } else {
        serviceName = server.id.toLowerCase();
      }

      // 使用 sc query 检查服务状态
      final result = await Process.run(
        'sc',
        ['query', serviceName],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        // 检查服务状态是否为 RUNNING
        if (output.contains('RUNNING')) {
          return true;
        }
      } else {
        // 如果服务不存在（退出码 1060），返回 false
        final errorOutput = result.stderr.toString();
        if (errorOutput.contains('1060') ||
            errorOutput.contains('指定的服务未安装') ||
            errorOutput.toLowerCase().contains('service does not exist')) {
          return false;
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[服务状态检查] 检查 Windows 服务状态失败: $e');
      }
      return false;
    }
  }

  /// 检查 Redis 是否运行
  static Future<bool> _checkRedisStatus(Software server) async {
    try {
      // 使用 tasklist 检查 redis-server.exe 进程是否存在
      final result = await Process.run(
        'tasklist',
        ['/FI', 'IMAGENAME eq redis-server.exe', '/FO', 'CSV', '/NH'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        if (output.isNotEmpty && output.contains('redis-server.exe')) {
          // 验证进程路径（可选，但更准确）
          final redisDir = await SoftwareManagerHelper.getSoftwareDirectory(
            server.id,
            'servers',
          );
          if (redisDir != null) {
            final redisExe = path.join(redisDir, 'redis-server.exe');
            final redisFile = File(redisExe);
            if (await redisFile.exists()) {
              // 尝试验证进程路径
              final lines = output.split('\n');
              for (final line in lines) {
                if (line.contains('redis-server.exe')) {
                  final parts = line.split(',');
                  if (parts.length >= 2) {
                    final pidStr = parts[1].replaceAll('"', '').trim();
                    final pid = int.tryParse(pidStr);
                    if (pid != null) {
                      try {
                        final psResult = await Process.run(
                          'powershell',
                          [
                            '-NoProfile',
                            '-Command',
                            '(Get-Process -Id $pid -ErrorAction SilentlyContinue).Path',
                          ],
                          runInShell: true,
                          environment: {'pid': pid.toString()},
                        );

                        if (psResult.exitCode == 0) {
                          final exePath = psResult.stdout.toString().trim();
                          if (exePath.isNotEmpty) {
                            final normalizedExePath = path.normalize(exePath);
                            final normalizedRedisExe = path.normalize(redisExe);
                            if (normalizedExePath.toLowerCase() ==
                                normalizedRedisExe.toLowerCase()) {
                              return true;
                            }
                          }
                        }
                      } catch (e) {
                        // PowerShell 命令失败，但进程存在，假设是 Redis
                        if (kDebugMode) {
                          print('[服务状态检查] 验证 Redis 进程路径失败: $e');
                        }
                        return true;
                      }
                    }
                  }
                }
              }
            }
          }
          // 如果无法验证路径，但进程存在，返回 true
          return true;
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[服务状态检查] 检查 Redis 状态失败: $e');
      }
      return false;
    }
  }

  /// 检查 PHP 是否运行
  /// PHP 通过 php-cgi-spawner 运行，检查进程或端口
  static Future<bool> _checkPhpStatus(Software server) async {
    try {
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) return false;

      final phpDir = Directory(path.join(storagePath, 'php', server.id));
      if (!await phpDir.exists()) return false;

      // PHP 通过 php-cgi-spawner 运行，检查进程
      // 或者检查端口（如果知道端口号）
      final result = await Process.run(
        'tasklist',
        ['/FI', 'IMAGENAME eq php-cgi-spawner.exe', '/FO', 'CSV', '/NH'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        if (output.isNotEmpty && output.contains('php-cgi-spawner.exe')) {
          // 进一步验证：检查进程的工作目录或命令行参数
          // 这里简化处理，如果进程存在就认为 PHP 在运行
          // 更准确的检查需要解析进程的命令行参数
          return true;
        }
      }

      // 也可以检查 PHP 端口（如果配置了端口）
      // 这里简化处理，主要依赖进程检查
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[服务状态检查] 检查 PHP 状态失败: $e');
      }
      return false;
    }
  }

  /// 检查 MongoDB 是否运行
  static Future<bool> _checkMongodbStatus(Software server) async {
    try {
      // MongoDB 通常作为 Windows 服务运行
      // 服务名通常是 MongoDB 或 MongoDB-{版本}
      final result = await Process.run(
        'sc',
        ['query', 'MongoDB'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        if (output.contains('RUNNING')) {
          return true;
        }
      }

      // 也可以检查 mongod.exe 进程
      final processResult = await Process.run(
        'tasklist',
        ['/FI', 'IMAGENAME eq mongod.exe', '/FO', 'CSV', '/NH'],
        runInShell: true,
      );

      if (processResult.exitCode == 0) {
        final output = processResult.stdout.toString();
        if (output.isNotEmpty && output.contains('mongod.exe')) {
          return true;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[服务状态检查] 检查 MongoDB 状态失败: $e');
      }
      return false;
    }
  }

  /// 检查所有已安装服务的实际状态
  /// 返回 Map<serverId, isRunning>
  static Future<Map<String, bool>> checkAllServicesStatus() async {
    final Map<String, bool> statusMap = {};

    try {
      final softwareSource = await SoftwareSourceService.getSource();
      if (softwareSource == null) return statusMap;

      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) return statusMap;

      // 检查所有服务器
      final List<Software> allServers = [];
      
      // 添加 servers 分类
      for (final server in softwareSource.servers) {
        final cate4 = server.cate4?.toLowerCase();
        if (cate4 != null &&
            ['nginx', 'mysql', 'pgsql', 'redis', 'rudis', 'mongodb']
                .contains(cate4)) {
          final dir = Directory('$storagePath/servers/${server.id}');
          if (await dir.exists()) {
            allServers.add(server);
          }
        }
      }

      // 添加 databases 分类
      for (final server in softwareSource.databases) {
        final cate4 = server.cate4?.toLowerCase();
        if (cate4 != null &&
            ['mysql', 'pgsql', 'mongodb'].contains(cate4)) {
          final dir = Directory('$storagePath/databases/${server.id}');
          if (await dir.exists()) {
            allServers.add(server);
          }
        }
      }

      // 添加 PHP 分类
      for (final server in softwareSource.php) {
        final dir = Directory('$storagePath/php/${server.id}');
        if (await dir.exists()) {
          allServers.add(server);
        }
      }

      // 并行检查所有服务的状态
      final List<Future<void>> checkTasks = [];
      for (final server in allServers) {
        checkTasks.add(
          checkServiceStatus(server).then((isRunning) {
            statusMap[server.id] = isRunning;
          }),
        );
      }

      await Future.wait(checkTasks);
    } catch (e) {
      if (kDebugMode) {
        print('[服务状态检查] 检查所有服务状态失败: $e');
      }
    }

    return statusMap;
  }
}

