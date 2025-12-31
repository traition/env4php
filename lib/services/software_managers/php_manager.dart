import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/software_model.dart';
import '../notification_service.dart';
import 'software_manager.dart';
import 'software_manager_helper.dart';

/// PHP 软件管理器
/// 注意：PHP 使用进程管理，需要跟踪 PID 和端口
class PhpManager extends SoftwareManager {
  @override
  String get supportedCate4 => 'php';

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

  /// 获取可用端口
  Future<int> _getAvailablePhpPort(String phpVersionId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'php_port_$phpVersionId';
    int port = prefs.getInt(key) ?? 9000;
    port += 1;

    // 检查端口是否被占用，如果被占用则自增
    while (await SoftwareManagerHelper.isPortInUse(port)) {
      port++;
    }

    // 保存端口
    await prefs.setInt(key, port);
    return port;
  }

  /// 确保PHP配置文件存在
  /// [port] 如果提供，则使用该端口更新配置；如果为null，则获取可用端口
  Future<void> _ensurePhpConfigExists(
    String nginxDir,
    String phpVersionId, [
    int? port,
  ]) async {
    final phpConfPath = path.join(
      nginxDir,
      'conf',
      'php',
      '$phpVersionId.conf',
    );
    final phpConfFile = File(phpConfPath);

    // 如果没有提供端口，获取可用端口
    final prefs = await SharedPreferences.getInstance();
    final portKey = 'php_port_$phpVersionId';
    port ??= prefs.getInt(portKey) ?? await _getAvailablePhpPort(phpVersionId);

    if (!await phpConfFile.exists()) {
      // 复制示例文件
      final examplePath = path.join(
        nginxDir,
        'conf',
        'php',
        'php.conf.example',
      );
      final exampleFile = File(examplePath);

      if (await exampleFile.exists()) {
        final content = await exampleFile.readAsString();
        // 替换 fastcgi_pass 行中的 #--# 为端口
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains('fastcgi_pass') && lines[i].contains('#--#')) {
            lines[i] = lines[i].replaceAll('#--#', port.toString());
            break;
          }
        }
        await phpConfFile.writeAsString(lines.join('\n'));
      }
    } else {
      // 如果文件已存在，更新 fastcgi_pass 行中的端口配置
      final content = await phpConfFile.readAsString();
      final lines = content.split('\n');
      // 查找包含 fastcgi_pass 的行并更新端口
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('fastcgi_pass')) {
          // 如果包含 #--# 占位符，替换它
          if (lines[i].contains('#--#')) {
            lines[i] = lines[i].replaceAll('#--#', port.toString());
            break;
          }
          // 否则，更新端口号（匹配 127.0.0.1:端口 格式）
          final portPattern = RegExp(r'127\.0\.0\.1:(\d+)');
          if (portPattern.hasMatch(lines[i])) {
            lines[i] = lines[i].replaceFirst(
              portPattern,
              '127.0.0.1:$port',
            );
            break;
          }
        }
      }
      await phpConfFile.writeAsString(lines.join('\n'));
    }
  }

  @override
  Future<(bool success, String? error)> start(Software server) async {
    try {
      // 检查是否有暂存的PID，如果有则先停止旧进程
      final existingPid = _processIds[server.id];
      if (existingPid != null) {
        if (kDebugMode) {
          print('[PHP启动] 发现暂存的PID: $existingPid，先停止旧进程');
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
            print('[PHP启动] 停止旧进程失败（可能进程已不存在）: $e');
          }
        }
        // 清除暂存的PID
        _processIds.remove(server.id);
      }

      final phpDir = await SoftwareManagerHelper.getPhpDirectory(server.id);
      if (phpDir == null) {
        await NotificationService.showError(
          title: '启动失败',
          message: 'PHP未安装或目录不存在',
        );
        return (false, 'PHP未安装或目录不存在');
      }

      final spawnerExe = path.join(phpDir, 'php-cgi-spawner.exe');
      final spawnerFile = File(spawnerExe);
      if (!await spawnerFile.exists()) {
        await NotificationService.showError(
          title: '启动失败',
          message: '找不到php-cgi-spawner.exe文件',
        );
        return (false, '找不到php-cgi-spawner.exe文件');
      }

      // 读取或创建端口配置
      final prefs = await SharedPreferences.getInstance();
      final portKey = 'php_port_${server.id}';
      int? port = prefs.getInt(portKey);

      if (port == null) {
        if (kDebugMode) {
          print('[PHP启动] 未找到端口配置，开始创建配置');
        }
        // 没有端口配置，需要创建
        final nginxDir = await SoftwareManagerHelper.getNginxDirectory();
        if (nginxDir == null) {
          if (kDebugMode) {
            print('[PHP启动失败] nginx未安装，无法创建PHP配置');
          }
          await NotificationService.showError(
            title: '启动失败',
            message: 'nginx未安装，无法创建PHP配置',
          );
          return (false, 'nginx未安装，无法创建PHP配置');
        }

        // 获取可用端口
        port = await _getAvailablePhpPort(server.id);
        if (kDebugMode) {
          print('[PHP启动] 获取到可用端口: $port');
        }
        // 确保PHP配置文件存在
        await _ensurePhpConfigExists(nginxDir, server.id);
      } else {
        if (kDebugMode) {
          print('[PHP启动] 使用已配置的端口: $port');
        }
      }

      // 执行启动命令: .\php-cgi-spawner.exe "php-cgi.exe -c php.ini" 运行端口 4
      final command = '$spawnerExe "php-cgi.exe -c php.ini" $port 4';
      print('[PHP启动] 执行命令: $command');

      final process = await Process.start(
        'powershell',
        ['-NoProfile', '-Command', command],
        runInShell: true,
        workingDirectory: phpDir,
      );

      // 消费 stdout（即使为空）
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        if (data.isNotEmpty) {
          print('[PHP启动] stdout: $data');
        }
      });

      // 消费 stderr
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        if (data.isNotEmpty) {
          print('[PHP启动] stderr: $data');
        }
      });

      // ★ 唯一的完成信号：等待命令执行完毕
      final exitCode = await process.exitCode;
      print('[PHP启动] PowerShell 命令执行完成，退出码: $exitCode');

      // 等待一小段时间让 php-cgi-spawner.exe 进程启动并绑定端口
      await Future.delayed(const Duration(milliseconds: 2000));

      // 检查端口是否被php-cgi-spawner.exe占用
      final processId = await SoftwareManagerHelper.getPortProcessId(
        port,
        spawnerExe,
      );

      if (processId != null && processId > 0) {
        // processId > 0 表示是PHP进程
        if (kDebugMode) {
          print('[PHP启动成功] 端口 $port 被php-cgi-spawner.exe占用，进程ID: $processId');
        }
        // 启动成功
        _processIds[server.id] = processId;
        await NotificationService.showSuccess(
          title: '启动成功',
          message: '${server.name} 已启动（端口: $port）',
        );
        return (true, null);
      } else if (processId == -1) {
        // processId == -1 表示端口被其他进程占用
        if (kDebugMode) {
          print('[PHP启动失败] 端口 $port 被其他进程占用');
        }
        final nginxDir = await SoftwareManagerHelper.getNginxDirectory();
        if (nginxDir == null) {
          if (kDebugMode) {
            print('[PHP启动失败] 端口被占用，但nginx未安装，无法重新分配端口');
          }
          await NotificationService.showError(
            title: '启动失败',
            message: '端口被占用，但nginx未安装，无法重新分配端口',
          );
          return (false, '端口被占用，但nginx未安装，无法重新分配端口');
        }

        // 重新获取可用端口
        final newPort = await _getAvailablePhpPort(server.id);
        if (kDebugMode) {
          print('[PHP启动] 重新分配端口: $port -> $newPort');
        }
        // 更新PHP配置文件
        await _ensurePhpConfigExists(nginxDir, server.id, newPort);

        await NotificationService.showError(
          title: '启动失败',
          message: '端口 $port 被占用，已重新分配端口为 $newPort，请重试',
        );
        return (false, '端口 $port 被占用，已重新分配端口为 $newPort');
      } else {
        // processId == null 表示端口未被占用
        if (kDebugMode) {
          print('[PHP启动失败] 端口 $port 未被占用，可能是PHP安装有问题或启动命令执行失败');
        }
        await NotificationService.showError(
          title: '启动失败',
          message: 'PHP启动失败，请检查PHP安装是否正确，或尝试重新安装PHP',
        );
        return (false, 'PHP启动失败，请检查PHP安装是否正确');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[PHP启动失败] 发生异常: $e');
        print('[PHP启动失败] 堆栈跟踪: $stackTrace');
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

      if (processId == null) {
        // 获取PHP目录和spawnerExe路径
        final phpDir = await SoftwareManagerHelper.getPhpDirectory(server.id);
        if (phpDir != null) {
          final spawnerExe = path.join(phpDir, 'php-cgi-spawner.exe');

          // 获取端口
          final prefs = await SharedPreferences.getInstance();
          final portKey = 'php_port_${server.id}';
          final port = prefs.getInt(portKey);

          if (port != null) {
            // 通过端口查找进程
            final foundPid = await SoftwareManagerHelper.getPortProcessId(
              port,
              spawnerExe,
            );
            if (foundPid != null && foundPid > 0) {
              processId = foundPid;
            }
          }
        }
      }

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
        print('[静默停止PHP] 发生异常: $e');
      }
      _processIds.remove(server.id);
      return (true, null); // 即使失败也返回成功
    }
  }

  @override
  Future<(bool success, String? error)> stop(Software server) async {
    try {
      int? processId = _processIds[server.id];

      // 如果没有暂存的PID，尝试通过端口查找进程
      if (processId == null) {
        if (kDebugMode) {
          print('[PHP停止] 未找到暂存的PID，尝试通过端口查找进程');
        }

        // 获取PHP目录和spawnerExe路径
        final phpDir = await SoftwareManagerHelper.getPhpDirectory(server.id);
        if (phpDir != null) {
          final spawnerExe = path.join(phpDir, 'php-cgi-spawner.exe');

          // 获取端口
          final prefs = await SharedPreferences.getInstance();
          final portKey = 'php_port_${server.id}';
          final port = prefs.getInt(portKey);

          if (port != null) {
            // 通过端口查找进程
            final foundPid = await SoftwareManagerHelper.getPortProcessId(
              port,
              spawnerExe,
            );
            if (foundPid != null && foundPid > 0) {
              processId = foundPid;
              if (kDebugMode) {
                print('[PHP停止] 通过端口找到进程ID: $processId');
              }
            }
          }
        }
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
        print('[PHP停止] 正在停止进程ID: $processId');
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
          print('[PHP停止] 进程树已成功终止');
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
          print('[PHP停止] taskkill退出码: ${result.exitCode}，进程可能已不存在');
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
        print('[PHP停止失败] 发生异常: $e');
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

