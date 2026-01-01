import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import 'config_service.dart';
import 'software_source_service.dart';

/// 工具启动器服务
/// 用于管理工具栏软件的启动逻辑
class ToolLauncherService {
  /// 工具 exe 路径配置映射（根据 cate4 配置）
  /// key: 工具 cate4（小写），value: 相对于软件目录的 exe 路径
  /// 特殊值说明：
  /// - 空字符串表示在软件目录中查找 exe 文件
  /// - pgAdmin4 需要特殊处理（在 pgsql 目录下）
  static const Map<String, String> _toolExePathsByCate4 = {
    'tiny_rdm': 'Tiny RDM.exe',
    'mongodb_compass': 'MongoDBCompass.exe',
    'dbeaver': 'dbeaver.exe',
    'heidisql': 'heidisql.exe', // 空字符串表示在目录中查找 exe
    'pgadmin4': 'pgAdmin 4/runtime/pgAdmin4.exe', // 特殊处理：在 pgsql 目录下
  };

  /// 获取工具的 exe 完整路径
  /// [tool] 工具软件对象
  /// 返回 exe 完整路径，如果未配置或文件不存在返回 null
  static Future<String?> getToolExePath(Software tool) async {
    // 获取 cate4（使用 id 作为后备）
    final cate4 = tool.cate4?.toLowerCase() ?? tool.id.toLowerCase();

    // 检查是否配置了该工具
    final exePath = _toolExePathsByCate4[cate4];
    if (exePath == null) {
      if (kDebugMode) {
        print('[工具启动] 工具 ${tool.id} (cate4: $cate4) 未配置 exe 路径');
      }
      return null;
    }

    // 获取存储路径
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    String fullPath;

    // pgAdmin4 特殊处理：在 pgsql 目录下
    if (cate4 == 'pgadmin4') {
      // 查找 pgsql 安装目录
      final softwareSource = await SoftwareSourceService.getSource();
      if (softwareSource == null) return null;

      final pgsql = softwareSource.databases.firstWhere(
        (s) => s.cate4?.toLowerCase() == 'pgsql',
        orElse: () => Software(
          id: '',
          name: '',
          byte: 0,
          downloadURL: '',
          commands: [],
          attachments: [],
        ),
      );

      if (pgsql.id.isEmpty) return null;

      // 检查 pgsql 目录（可能在 servers 或 databases 目录下）
      final serversDir = Directory('$storagePath/servers/${pgsql.id}');
      final databasesDir = Directory('$storagePath/databases/${pgsql.id}');

      String? pgsqlDir;
      if (await serversDir.exists()) {
        pgsqlDir = serversDir.path;
      } else if (await databasesDir.exists()) {
        pgsqlDir = databasesDir.path;
      }

      if (pgsqlDir == null) return null;

      // 构建 pgAdmin4 的完整路径
      fullPath = path.join(pgsqlDir, exePath);
    } else {
      // 其他工具在 tools 目录下
      final toolDir = path.join(storagePath, 'tools', tool.id);

      // heidisql 特殊处理：如果配置为空字符串，在目录中查找 exe 文件
      if (exePath.isEmpty) {
        // 在目录中查找 exe 文件（通常是目录名加 .exe，或 HeidiSQL.exe）
        final possibleNames = [
          '${tool.id}.exe',
          'HeidiSQL.exe',
          'heidisql.exe',
        ];

        String? foundPath;
        for (final name in possibleNames) {
          final possiblePath = path.join(toolDir, name);
          if (await File(possiblePath).exists()) {
            foundPath = possiblePath;
            break;
          }
        }

        // 如果没找到，尝试查找目录中第一个 exe 文件
        if (foundPath == null) {
          try {
            final dir = Directory(toolDir);
            if (await dir.exists()) {
              await for (final entity in dir.list()) {
                if (entity is File) {
                  final ext = path.extension(entity.path).toLowerCase();
                  if (ext == '.exe') {
                    foundPath = entity.path;
                    break;
                  }
                }
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('[工具启动] 查找 exe 文件失败: $e');
            }
          }
        }

        if (foundPath == null) {
          if (kDebugMode) {
            print('[工具启动] 无法在目录中找到 exe 文件: $toolDir');
          }
          return null;
        }

        fullPath = foundPath;
      } else {
        // 使用配置的路径
        fullPath = path.join(toolDir, exePath);
      }
    }

    final file = File(fullPath);
    if (await file.exists()) {
      return fullPath;
    }

    if (kDebugMode) {
      print('[工具启动] 工具 ${tool.id} 的 exe 文件不存在: $fullPath');
    }
    return null;
  }

  /// 检查工具进程是否正在运行
  /// [exePath] exe 完整路径
  /// 返回进程ID，如果未运行返回 null
  static Future<int?> checkProcessRunning(String exePath) async {
    try {
      final exeName = path.basename(exePath);

      // 使用 tasklist 命令查找进程
      final result = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq $exeName',
        '/FO',
        'CSV',
        '/NH',
      ], runInShell: true);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        if (output.isNotEmpty && output.contains(exeName)) {
          // 解析进程ID
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains(exeName)) {
              final parts = line.split(',');
              if (parts.length >= 2) {
                final pidStr = parts[1].replaceAll('"', '').trim();
                final pid = int.tryParse(pidStr);
                if (pid != null) {
                  // 进一步验证：检查进程的可执行文件路径是否匹配
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
                      final processExePath = psResult.stdout.toString().trim();
                      if (processExePath.isNotEmpty) {
                        // 规范化路径进行比较
                        final normalizedProcessPath = path.normalize(
                          processExePath,
                        );
                        final normalizedExePath = path.normalize(exePath);
                        if (normalizedProcessPath.toLowerCase() ==
                            normalizedExePath.toLowerCase()) {
                          return pid;
                        }
                      }
                    }
                  } catch (e) {
                    // PowerShell 命令失败，但进程存在，返回 PID
                    if (kDebugMode) {
                      print('[工具启动] 验证进程路径失败: $e');
                    }
                    return pid;
                  }
                }
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[工具启动] 检查进程运行状态失败: $e');
      }
      return null;
    }
  }

  /// 让窗口在任务栏中闪烁
  /// [exePath] exe 完整路径
  /// [pid] 进程ID（可选，如果不提供则通过进程查找）
  /// 返回是否成功
  static Future<bool> flashWindowInTaskbar(String exePath, [int? pid]) async {
    try {
      // 如果未提供 PID，先查找进程
      int? processId = pid;
      if (processId == null) {
        processId = await checkProcessRunning(exePath);
        if (processId == null) {
          if (kDebugMode) {
            print('[工具启动] 无法找到进程，无法闪烁窗口');
          }
          return false;
        }
      }

      // 使用 PowerShell 让窗口在任务栏中闪烁
      // 使用 FlashWindowEx API
      final psScript =
          '''
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public struct FLASHWINFO{public uint cbSize;public IntPtr hwnd;public uint dwFlags;public uint uCount;public uint dwTimeout;}public class Win32{[DllImport("user32.dll")]public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);}'
\$process = Get-Process -Id $processId -ErrorAction SilentlyContinue
if (\$process -and \$process.MainWindowHandle -ne [IntPtr]::Zero) {
  \$hwnd = \$process.MainWindowHandle
  \$flashInfo = New-Object FLASHWINFO
  \$flashInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][FLASHWINFO])
  \$flashInfo.hwnd = \$hwnd
  \$flashInfo.dwFlags = 0x00000003  # FLASHW_ALL | FLASHW_TIMERNOFG
  \$flashInfo.uCount = 5  # 闪烁5次
  \$flashInfo.dwTimeout = 0
  \$result = [Win32]::FlashWindowEx([ref]\$flashInfo)
  if (\$result) {
    exit 0
  }
}
exit 1
''';

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        psScript,
      ], runInShell: true);

      if (result.exitCode == 0) {
        if (kDebugMode) {
          print('[工具启动] 成功闪烁窗口（PID: $processId）');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('[工具启动] 闪烁窗口失败: ${result.stderr}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[工具启动] 闪烁窗口时发生错误: $e');
      }
      return false;
    }
  }

  /// 启动工具
  /// [exePath] exe 完整路径
  /// 返回是否成功
  static Future<bool> startTool(String exePath) async {
    try {
      final file = File(exePath);
      if (!await file.exists()) {
        if (kDebugMode) {
          print('[工具启动] exe 文件不存在: $exePath');
        }
        return false;
      }

      // 将路径中的 / 替换为 \（Windows 路径格式）
      final normalizedExePath = exePath.replaceAll('/', '\\');

      // 直接使用 explorer 命令启动程序
      if (kDebugMode) {
        print('[工具启动] 执行命令:');
        print('  explorer "$normalizedExePath"');
      }

      // 执行 explorer 命令
      final processFuture = Process.run('explorer', [
        normalizedExePath,
      ], runInShell: false);

      // 监听 PowerShell 输出并同步输出到调试控制台
      processFuture
          .then((result) {
            if (kDebugMode) {
              if (result.stdout.toString().trim().isNotEmpty) {
                print('[工具启动] PowerShell 标准输出: ${result.stdout}');
              }
              if (result.stderr.toString().trim().isNotEmpty) {
                print('[工具启动] PowerShell 错误输出: ${result.stderr}');
              }
              print(
                '[工具启动] PowerShell 启动命令已结束: $exePath (退出码: ${result.exitCode})',
              );
            }
          })
          .catchError((error) {
            if (kDebugMode) {
              print('[工具启动] PowerShell 启动命令错误: $error');
            }
          });

      // 同时持续监控检查进程是否启动
      const timeout = Duration(seconds: 5);
      const checkInterval = Duration(milliseconds: 200);
      final startTime = DateTime.now();

      if (kDebugMode) {
        print('[工具启动] 已启动进程，等待进程运行...');
      }

      // 持续检查进程是否启动
      while (DateTime.now().difference(startTime) < timeout) {
        // 检查进程是否真的启动了
        final pid = await checkProcessRunning(exePath);
        if (pid != null) {
          if (kDebugMode) {
            print('[工具启动] 成功启动工具: $exePath (PID: $pid)');
          }
          // 进程已启动，PowerShell 输出已在上面监听
          return true;
        }

        // 等待一段时间后再次检查
        await Future.delayed(checkInterval);
      }

      // 超时后检查最后一次
      final pid = await checkProcessRunning(exePath);
      if (pid != null) {
        if (kDebugMode) {
          print('[工具启动] 成功启动工具: $exePath (PID: $pid)');
        }
        // 进程已启动，PowerShell 输出已在上面监听
        return true;
      }

      // 超时且进程未启动
      if (kDebugMode) {
        print('[工具启动] 启动超时，进程未启动: $exePath');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[工具启动] 启动工具失败: $e');
      }
      return false;
    }
  }

  /// 启动或激活工具
  /// [tool] 工具软件对象
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> launchTool(Software tool) async {
    try {
      // 跳过 composer 和 phpmyadmin
      if (tool.cate4?.toLowerCase() == 'composer' ||
          tool.id.toLowerCase() == 'composer' ||
          tool.cate4?.toLowerCase() == 'phpmyadmin' ||
          tool.id.toLowerCase() == 'phpmyadmin') {
        return (false, '该工具不支持通过工具栏启动');
      }

      // 获取 exe 路径
      final exePath = await getToolExePath(tool);
      if (exePath == null) {
        return (false, '工具 ${tool.name} 未配置 exe 路径或文件不存在');
      }

      // 检查进程是否正在运行
      final pid = await checkProcessRunning(exePath);
      if (pid != null) {
        // 进程已运行，直接返回提示信息
        return (true, 'WINDOW_ALREADY_RUNNING');
      } else {
        // 进程未运行，启动它
        final success = await startTool(exePath);
        if (success) {
          return (true, null);
        } else {
          return (false, '启动失败');
        }
      }
    } catch (e) {
      return (false, '启动工具时发生错误: $e');
    }
  }
}
