import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/service_status_checker.dart';
import '../models/software_model.dart';
import '../services/notification_service.dart';
import '../services/software_managers/software_manager_factory.dart';

/// 重置MySQL root密码工具
class MysqlPasswordResetTool {
  /// 执行重置MySQL root密码操作
  static Future<void> execute(BuildContext context) async {
    try {
      // 1. 检查MySQL是否安装
      final mysqlInfo = await _findInstalledMysql();
      if (mysqlInfo == null) {
        await NotificationService.showError(
          title: '错误',
          message: '未找到已安装的MySQL',
        );
        return;
      }

      final mysqlDir = mysqlInfo.mysqlDir;
      final mysqlSoftware = mysqlInfo.mysqlSoftware;

      // 2. 检查MySQL是否正在运行
      final isRunning = await ServiceStatusChecker.checkServiceStatus(
        mysqlSoftware,
      );

      if (isRunning) {
        // MySQL正在运行，提示用户需要停止
        final shouldContinue = await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: const Text('MySQL正在运行'),
            content: const Text(
              '重置MySQL密码需要先停止MySQL服务。\n\n'
              '是否继续？继续后将停止MySQL服务并重置密码。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续'),
              ),
            ],
          ),
        );

        if (shouldContinue != true) {
          return; // 用户取消
        }

        // 停止MySQL服务（使用现有的管理器方法）
        await NotificationService.showInfo(
          title: '正在停止MySQL',
          message: '正在停止MySQL服务...',
        );

        final manager = SoftwareManagerFactory.getManager(mysqlSoftware);
        if (manager == null) {
          await NotificationService.showError(
            title: '错误',
            message: '无法获取MySQL管理器',
          );
          return;
        }

        final stopResult = await manager.stopSilently(mysqlSoftware);
        if (!stopResult.$1) {
          await NotificationService.showError(
            title: '停止失败',
            message: stopResult.$2 ?? '无法停止MySQL服务，请手动停止后再试',
          );
          return;
        }

        // 等待服务完全停止
        await Future.delayed(const Duration(seconds: 2));
      }

      // 3. 让用户输入新密码
      final newPassword = await _showPasswordInputDialog(context);
      if (newPassword == null || newPassword.isEmpty) {
        return; // 用户取消或未输入密码
      }

      // 验证密码格式（只允许数字、字母和特殊符号）
      if (!_isValidPassword(newPassword)) {
        await NotificationService.showError(
          title: '密码格式错误',
          message: '密码只能包含数字、字母和特殊符号',
        );
        return;
      }

      // 4. 执行密码重置流程
      await _resetPassword(context, mysqlDir, newPassword, mysqlSoftware.id);
    } catch (e) {
      await NotificationService.showError(
        title: '重置失败',
        message: '重置MySQL密码时发生错误: $e',
      );
    }
  }

  /// 查找已安装的MySQL
  /// 返回 (MySQL目录路径, MySQL软件对象) 或 null
  static Future<({String mysqlDir, Software mysqlSoftware})?>
  _findInstalledMysql() async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return null;

    // 检查servers和databases分类中的MySQL
    final allMysql = <Software>[];
    allMysql.addAll(
      softwareSource.servers.where((s) => s.cate4?.toLowerCase() == 'mysql'),
    );
    allMysql.addAll(
      softwareSource.databases.where((s) => s.cate4?.toLowerCase() == 'mysql'),
    );

    // 查找第一个已安装的MySQL
    for (final mysql in allMysql) {
      final serversDir = Directory(path.join(storagePath, 'servers', mysql.id));
      final databasesDir = Directory(
        path.join(storagePath, 'databases', mysql.id),
      );

      if (await serversDir.exists()) {
        return (mysqlDir: serversDir.path, mysqlSoftware: mysql);
      } else if (await databasesDir.exists()) {
        return (mysqlDir: databasesDir.path, mysqlSoftware: mysql);
      }
    }

    return null;
  }

  /// 显示密码输入对话框
  static Future<String?> _showPasswordInputDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    return showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('输入新密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: '新密码',
                  hintText: '只能包含数字、字母和特殊符号',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final password = passwordController.text.trim();
                if (password.isNotEmpty) {
                  Navigator.of(context).pop(password);
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 验证密码格式（只允许数字、字母和特殊符号）
  static bool _isValidPassword(String password) {
    // 只允许可见字符（排除控制字符）
    // ASCII 可打印字符范围：0x20-0x7E（包括空格、数字、字母、标点符号等）
    final strictRegex = RegExp(r'^[\x20-\x7E]+$');
    return strictRegex.hasMatch(password) && password.isNotEmpty;
  }

  /// 结束所有 mysqld 进程
  static Future<void> _killAllMysqldProcesses() async {
    try {
      if (kDebugMode) {
        print('[MySQL密码重置] 正在结束所有 mysqld 进程...');
      }

      // 使用 taskkill 强制结束所有 mysqld.exe 进程
      final result = await Process.run('taskkill', [
        '/F',
        '/IM',
        'mysqld.exe',
        '/T',
      ], runInShell: true);

      if (kDebugMode) {
        if (result.exitCode == 0) {
          print('[MySQL密码重置] 成功结束所有 mysqld 进程');
        } else {
          // 退出码 128 表示没有找到进程，这是正常的
          if (result.exitCode != 128) {
            print('[MySQL密码重置] 结束 mysqld 进程时退出码: ${result.exitCode}');
            if (result.stderr.toString().isNotEmpty) {
              print('[MySQL密码重置] stderr: ${result.stderr}');
            }
          } else {
            print('[MySQL密码重置] 没有找到运行中的 mysqld 进程');
          }
        }
      }

      // 等待进程完全结束
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      if (kDebugMode) {
        print('[MySQL密码重置] 结束 mysqld 进程时发生错误: $e');
      }
    }
  }

  /// 执行密码重置
  static Future<void> _resetPassword(
    BuildContext context,
    String mysqlDir,
    String newPassword,
    String mysqlId,
  ) async {
    Process? mysqldProcess;

    try {
      // 在开始之前，先结束所有可能存在的 mysqld 进程
      await _killAllMysqldProcesses();

      await NotificationService.showInfo(
        title: '正在重置密码',
        message: '正在启动MySQL服务...',
      );

      // 4. 启动 mysqld --skip-grant-tables --shared-memory
      final mysqldExe = path.join(mysqlDir, 'bin', 'mysqld.exe');
      final mysqldFile = File(mysqldExe);
      if (!await mysqldFile.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '找不到mysqld.exe文件: $mysqldExe',
        );
        return;
      }

      if (kDebugMode) {
        print('[MySQL密码重置] 启动 mysqld: $mysqldExe');
      }

      // 启动 mysqld 进程（保持运行）
      mysqldProcess = await Process.start(
        mysqldExe,
        ['--skip-grant-tables', '--shared-memory'],
        workingDirectory: path.join(mysqlDir, 'bin'),
        mode: ProcessStartMode.normal,
      );

      // 等待 mysqld 启动（等待几秒）
      await Future.delayed(const Duration(seconds: 3));

      // 检查进程是否还在运行（使用非阻塞方式）
      try {
        final exitCode = await mysqldProcess.exitCode.timeout(
          const Duration(milliseconds: 100),
        );
        // 如果能在100ms内获取退出码，说明进程已退出
        final stderr = await mysqldProcess.stderr
            .transform(const SystemEncoding().decoder)
            .join();
        await NotificationService.showError(
          title: '启动失败',
          message: 'mysqld 启动失败（退出码: $exitCode）: $stderr',
        );
        return;
      } on TimeoutException {
        // 超时说明进程仍在运行，这是正常的
        if (kDebugMode) {
          print('[MySQL密码重置] mysqld 进程正在运行');
        }
      }

      if (kDebugMode) {
        print('[MySQL密码重置] mysqld 已启动');
      }

      // 5. 执行 mysql -u root 并输入SQL命令
      final mysqlExe = path.join(mysqlDir, 'bin', 'mysql.exe');
      final mysqlFile = File(mysqlExe);
      if (!await mysqlFile.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '找不到mysql.exe文件: $mysqlExe',
        );
        return;
      }

      if (kDebugMode) {
        print('[MySQL密码重置] 执行 mysql -u root');
      }

      // 启动 mysql 进程
      final mysqlProcess = await Process.start(
        mysqlExe,
        ['-u', 'root'],
        workingDirectory: path.join(mysqlDir, 'bin'),
        mode: ProcessStartMode.normal,
      );

      // 构建SQL命令（转义单引号）
      final escapedPassword = newPassword.replaceAll("'", "''");
      final sqlCommands = [
        'FLUSH PRIVILEGES;',
        "ALTER USER 'root'@'localhost' IDENTIFIED BY '$escapedPassword';",
        'EXIT;',
      ];

      // 将SQL命令写入mysql进程的stdin
      final stdin = mysqlProcess.stdin;
      for (final sql in sqlCommands) {
        if (kDebugMode) {
          print('[MySQL密码重置] 执行SQL: $sql');
        }
        stdin.writeln(sql);
      }
      await stdin.flush();
      await stdin.close();

      // 等待mysql进程完成
      final mysqlExitCode = await mysqlProcess.exitCode;
      final mysqlStdout = await mysqlProcess.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final mysqlStderr = await mysqlProcess.stderr
          .transform(const SystemEncoding().decoder)
          .join();

      if (kDebugMode) {
        print('[MySQL密码重置] mysql 退出码: $mysqlExitCode');
        if (mysqlStdout.isNotEmpty) {
          print('[MySQL密码重置] mysql stdout: $mysqlStdout');
        }
        if (mysqlStderr.isNotEmpty) {
          print('[MySQL密码重置] mysql stderr: $mysqlStderr');
        }
      }

      // 检查是否有错误
      if (mysqlStderr.isNotEmpty &&
          !mysqlStderr.contains('Warning') &&
          !mysqlStderr.contains('Note')) {
        await NotificationService.showError(
          title: '重置失败',
          message: '执行SQL命令时发生错误: $mysqlStderr',
        );
        return;
      }

      // 6. 停止所有 mysqld 进程
      if (kDebugMode) {
        print('[MySQL密码重置] 停止所有 mysqld 进程');
      }
      try {
        // 先尝试正常停止当前进程
        mysqldProcess.kill();
        try {
          await mysqldProcess.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // 超时，继续执行强制结束
        }
      } catch (e) {
        if (kDebugMode) {
          print('[MySQL密码重置] 停止 mysqld 时发生错误: $e');
        }
      }

      // 强制结束所有 mysqld 进程（确保没有残留）
      await _killAllMysqldProcesses();

      // 更新 SharedPreferences 中的 MySQL 服务状态为停止
      await _updateMysqlServiceStatus(mysqlId, false);

      // 完成
      await NotificationService.showSuccess(
        title: '重置成功',
        message: 'MySQL root密码已成功重置',
      );
    } catch (e) {
      // 确保停止所有 mysqld 进程
      try {
        mysqldProcess?.kill();
      } catch (_) {
        // 忽略错误
      }

      // 强制结束所有 mysqld 进程（确保没有残留）
      await _killAllMysqldProcesses();

      // 更新 SharedPreferences 中的 MySQL 服务状态为停止
      await _updateMysqlServiceStatus(mysqlId, false);

      await NotificationService.showError(
        title: '重置失败',
        message: '重置MySQL密码时发生错误: $e',
      );
    }
  }

  /// 更新 MySQL 服务在 SharedPreferences 中的状态
  static Future<void> _updateMysqlServiceStatus(
    String mysqlId,
    bool isRunning,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('server_running_status_$mysqlId', isRunning);
      if (kDebugMode) {
        print('[MySQL密码重置] 已更新 MySQL 服务状态: $mysqlId = $isRunning');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[MySQL密码重置] 更新 MySQL 服务状态失败: $e');
      }
    }
  }
}
