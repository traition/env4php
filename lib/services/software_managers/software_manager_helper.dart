import 'dart:io';
import 'package:path/path.dart' as path;
import '../config_service.dart';
import '../software_source_service.dart';
import '../../models/software_model.dart';

/// 软件管理器辅助类
/// 提供通用的辅助方法供各个管理器使用
class SoftwareManagerHelper {
  /// 获取 nginx 目录
  static Future<String?> getNginxDirectory() async {
    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return null;

    // 查找nginx软件
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

    if (nginx.id.isEmpty) return null;

    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    final nginxDir = Directory('$storagePath/servers/${nginx.id}');
    if (!await nginxDir.exists()) return null;

    return nginxDir.path;
  }

  /// 获取软件目录（支持 servers 和 databases 目录）
  static Future<String?> getSoftwareDirectory(
    String softwareId,
    String category,
  ) async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    // 可能在servers或databases目录下
    final serversDir = Directory(path.join(storagePath, 'servers', softwareId));
    final databasesDir = Directory(
      path.join(storagePath, 'databases', softwareId),
    );

    if (await serversDir.exists()) {
      return serversDir.path;
    } else if (await databasesDir.exists()) {
      return databasesDir.path;
    }
    return null;
  }

  /// 获取 PHP 目录
  static Future<String?> getPhpDirectory(String phpId) async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    final phpDir = Directory(path.join(storagePath, 'php', phpId));
    if (!await phpDir.exists()) return null;

    return phpDir.path;
  }

  /// 检查端口是否被占用
  static Future<bool> isPortInUse(int port) async {
    try {
      final result = await Process.run(
        'netstat',
        ['-ano'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        for (final line in lines) {
          // 查找包含端口号的行（格式：TCP    0.0.0.0:端口号   0.0.0.0:0    LISTENING）
          if (line.contains(':$port ') || line.contains(':$port\n')) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 获取端口对应的进程ID和可执行文件路径
  /// [port] 端口号
  /// [expectedExe] 期望的可执行文件路径（用于验证）
  /// 返回进程ID，如果端口未被占用返回null，如果被其他进程占用返回-1
  static Future<int?> getPortProcessId(int port, String expectedExe) async {
    try {
      // 步骤1: 使用 netstat 获取 PID
      final netstatResult = await Process.run(
        'netstat',
        ['-ano'],
        runInShell: true,
      );

      if (netstatResult.exitCode != 0) {
        return null;
      }

      final output = netstatResult.stdout.toString();
      final lines = output.split('\n');
      int? pid;

      for (final line in lines) {
        // 查找包含端口号的行
        if (line.contains(':$port ') || line.contains(':$port\n')) {
          // 提取PID（行末的数字）
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty) {
            final lastPart = parts.last;
            final parsedPid = int.tryParse(lastPart);
            if (parsedPid != null) {
              pid = parsedPid;
              break;
            }
          }
        }
      }

      if (pid == null) {
        return null; // 端口未被占用
      }

      // 步骤2: 使用 PowerShell 获取进程的可执行文件路径
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
            // 规范化路径进行比较
            final normalizedExePath = path.normalize(exePath);
            final normalizedExpectedExe = path.normalize(expectedExe);
            if (normalizedExePath.toLowerCase() ==
                normalizedExpectedExe.toLowerCase()) {
              return pid; // 是期望的进程
            } else {
              return -1; // 被其他进程占用
            }
          }
        }
      } catch (e) {
        // PowerShell 命令失败，尝试直接返回 PID
        return pid;
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}

