import 'dart:io';
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

/// 重置PostgreSQL postgres密码工具
class PostgresqlPasswordResetTool {
  /// 执行重置PostgreSQL postgres密码操作
  static Future<void> execute(BuildContext context) async {
    try {
      // 1. 检查PostgreSQL是否安装
      final pgsqlInfo = await _findInstalledPostgresql();
      if (pgsqlInfo == null) {
        await NotificationService.showError(
          title: '错误',
          message: '未找到已安装的PostgreSQL',
        );
        return;
      }

      final pgsqlDir = pgsqlInfo.pgsqlDir;
      final pgsqlSoftware = pgsqlInfo.pgsqlSoftware;

      // 2. 检查PostgreSQL是否正在运行
      final isRunning = await ServiceStatusChecker.checkServiceStatus(
        pgsqlSoftware,
      );

      String? newPassword;
      if (isRunning) {
        // PostgreSQL正在运行，提示用户需要停止
        final shouldContinue = await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: const Text('PostgreSQL正在运行'),
            content: const Text(
              '重置PostgreSQL密码需要先停止PostgreSQL服务。\n\n'
              '是否继续？继续后将停止PostgreSQL服务并重置密码。',
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

        // 让用户输入新密码
        newPassword = await _showPasswordInputDialog(context);
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

        // 停止PostgreSQL服务（使用现有的管理器方法）
        await NotificationService.showInfo(
          title: '正在停止PostgreSQL',
          message: '正在停止PostgreSQL服务...',
        );

        final manager = SoftwareManagerFactory.getManager(pgsqlSoftware);
        if (manager == null) {
          await NotificationService.showError(
            title: '错误',
            message: '无法获取PostgreSQL管理器',
          );
          return;
        }

        final stopResult = await manager.stopSilently(pgsqlSoftware);
        if (!stopResult.$1) {
          await NotificationService.showError(
            title: '停止失败',
            message: stopResult.$2 ?? '无法停止PostgreSQL服务，请手动停止后再试',
          );
          return;
        }

        // 等待服务完全停止
        await Future.delayed(const Duration(seconds: 2));
      } else {
        // PostgreSQL未运行，直接让用户输入新密码
        newPassword = await _showPasswordInputDialog(context);
        if (newPassword == null || newPassword.isEmpty) {
          return; // 用户取消或未输入密码
        }

        // 验证密码格式
        if (!_isValidPassword(newPassword)) {
          await NotificationService.showError(
            title: '密码格式错误',
            message: '密码只能包含数字、字母和特殊符号',
          );
          return;
        }
      }

      // 执行密码重置流程
      await _resetPassword(context, pgsqlDir, newPassword, pgsqlSoftware);
    } catch (e) {
      await NotificationService.showError(
        title: '重置失败',
        message: '重置PostgreSQL密码时发生错误: $e',
      );
    }
  }

  /// 查找已安装的PostgreSQL
  /// 返回 (PostgreSQL目录路径, PostgreSQL软件对象) 或 null
  static Future<({String pgsqlDir, Software pgsqlSoftware})?>
  _findInstalledPostgresql() async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return null;

    // 检查servers和databases分类中的PostgreSQL
    final allPgsql = <Software>[];
    allPgsql.addAll(
      softwareSource.servers.where((s) => s.cate4?.toLowerCase() == 'pgsql'),
    );
    allPgsql.addAll(
      softwareSource.databases.where((s) => s.cate4?.toLowerCase() == 'pgsql'),
    );

    // 查找第一个已安装的PostgreSQL
    for (final pgsql in allPgsql) {
      final serversDir = Directory(path.join(storagePath, 'servers', pgsql.id));
      final databasesDir = Directory(
        path.join(storagePath, 'databases', pgsql.id),
      );

      if (await serversDir.exists()) {
        return (pgsqlDir: serversDir.path, pgsqlSoftware: pgsql);
      } else if (await databasesDir.exists()) {
        return (pgsqlDir: databasesDir.path, pgsqlSoftware: pgsql);
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

  /// 执行密码重置
  static Future<void> _resetPassword(
    BuildContext context,
    String pgsqlDir,
    String newPassword,
    Software pgsqlSoftware,
  ) async {
    final pgHbaConfPath = path.join(pgsqlDir, 'data', 'pg_hba.conf');
    final pgHbaConfBakPath = path.join(pgsqlDir, 'data', 'pg_hba.conf.bak');
    final pgHbaConfFile = File(pgHbaConfPath);
    final pgHbaConfBakFile = File(pgHbaConfBakPath);

    try {
      await NotificationService.showInfo(
        title: '正在重置密码',
        message: '正在准备重置PostgreSQL密码...',
      );

      // 3. 备份 pg_hba.conf 文件
      if (!await pgHbaConfFile.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '找不到 pg_hba.conf 文件: $pgHbaConfPath',
        );
        return;
      }

      if (kDebugMode) {
        print('[PostgreSQL密码重置] 备份 pg_hba.conf 文件');
      }

      // 如果备份文件已存在，先删除
      if (await pgHbaConfBakFile.exists()) {
        await pgHbaConfBakFile.delete();
      }

      // 重命名文件
      await pgHbaConfFile.rename(pgHbaConfBakPath);

      // 4. 创建新的 pg_hba.conf 文件
      if (kDebugMode) {
        print('[PostgreSQL密码重置] 创建新的 pg_hba.conf 文件');
      }

      const newPgHbaConfContent = '''host all all ::1/128 trust
host all all 127.0.0.1/32 trust
''';

      await pgHbaConfFile.writeAsString(newPgHbaConfContent);

      // 5. 启动PostgreSQL服务（使用现有的管理器方法）
      if (kDebugMode) {
        print('[PostgreSQL密码重置] 启动PostgreSQL服务');
      }

      final manager = SoftwareManagerFactory.getManager(pgsqlSoftware);
      if (manager == null) {
        await NotificationService.showError(
          title: '错误',
          message: '无法获取PostgreSQL管理器',
        );
        return;
      }

      final startResult = await manager.start(pgsqlSoftware);

      if (!startResult.$1) {
        await NotificationService.showError(
          title: '启动失败',
          message: startResult.$2 ?? '无法启动PostgreSQL服务',
        );
        return;
      }

      // 等待服务启动
      await Future.delayed(const Duration(seconds: 3));

      // 6. 执行 psql 命令修改密码
      final psqlExe = path.join(pgsqlDir, 'bin', 'psql.exe');
      final psqlFile = File(psqlExe);
      if (!await psqlFile.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '找不到psql.exe文件: $psqlExe',
        );
        return;
      }

      if (kDebugMode) {
        print('[PostgreSQL密码重置] 执行 psql 命令修改密码');
      }

      // 构建SQL命令（转义单引号）
      final escapedPassword = newPassword.replaceAll("'", "''");
      final sqlCommand =
          "alter user postgres with password '$escapedPassword';";

      // 启动 psql 进程
      final psqlProcess = await Process.start(
        psqlExe,
        ['-p', '5432', '-U', 'postgres'],
        workingDirectory: path.join(pgsqlDir, 'bin'),
        mode: ProcessStartMode.normal,
      );

      // 将SQL命令写入psql进程的stdin
      final stdin = psqlProcess.stdin;
      stdin.writeln(sqlCommand);
      await stdin.flush();
      await stdin.close();

      // 等待psql进程完成
      final psqlExitCode = await psqlProcess.exitCode;
      final psqlStdout = await psqlProcess.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final psqlStderr = await psqlProcess.stderr
          .transform(const SystemEncoding().decoder)
          .join();

      if (kDebugMode) {
        print('[PostgreSQL密码重置] psql 退出码: $psqlExitCode');
        if (psqlStdout.isNotEmpty) {
          print('[PostgreSQL密码重置] psql stdout: $psqlStdout');
        }
        if (psqlStderr.isNotEmpty) {
          print('[PostgreSQL密码重置] psql stderr: $psqlStderr');
        }
      }

      // 检查是否有错误
      if (psqlExitCode != 0 ||
          (psqlStderr.isNotEmpty && !psqlStderr.contains('WARNING'))) {
        await NotificationService.showError(
          title: '重置失败',
          message:
              '执行SQL命令时发生错误: ${psqlStderr.isEmpty ? psqlStdout : psqlStderr}',
        );
        return;
      }

      // 7. 停止PostgreSQL服务（使用现有的管理器方法）
      if (kDebugMode) {
        print('[PostgreSQL密码重置] 停止PostgreSQL服务');
      }

      final stopResult = await manager.stopSilently(pgsqlSoftware);

      if (!stopResult.$1) {
        await NotificationService.showError(
          title: '停止失败',
          message: stopResult.$2 ?? '无法停止PostgreSQL服务',
        );
        return;
      }

      // 等待服务完全停止
      await Future.delayed(const Duration(seconds: 2));

      // 8. 恢复 pg_hba.conf 文件
      if (kDebugMode) {
        print('[PostgreSQL密码重置] 恢复 pg_hba.conf 文件');
      }

      // 删除新的 pg_hba.conf 文件
      if (await pgHbaConfFile.exists()) {
        await pgHbaConfFile.delete();
      }

      // 恢复备份文件
      await pgHbaConfBakFile.rename(pgHbaConfPath);

      // 更新 SharedPreferences 中的 PostgreSQL 服务状态为停止
      await _updatePgsqlServiceStatus(pgsqlSoftware.id, false);

      // 9. 完成
      await NotificationService.showSuccess(
        title: '重置成功',
        message: 'PostgreSQL postgres密码已成功重置',
      );
    } catch (e) {
      // 确保恢复 pg_hba.conf 文件
      try {
        if (await pgHbaConfFile.exists() && await pgHbaConfBakFile.exists()) {
          await pgHbaConfFile.delete();
          await pgHbaConfBakFile.rename(pgHbaConfPath);
        }
      } catch (restoreError) {
        if (kDebugMode) {
          print('[PostgreSQL密码重置] 恢复 pg_hba.conf 文件失败: $restoreError');
        }
      }

      await NotificationService.showError(
        title: '重置失败',
        message: '重置PostgreSQL密码时发生错误: $e',
      );
    }
  }

  /// 更新 PostgreSQL 服务在 SharedPreferences 中的状态
  static Future<void> _updatePgsqlServiceStatus(
    String pgsqlId,
    bool isRunning,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('server_running_status_$pgsqlId', isRunning);
      if (kDebugMode) {
        print('[PostgreSQL密码重置] 已更新 PostgreSQL 服务状态: $pgsqlId = $isRunning');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[PostgreSQL密码重置] 更新 PostgreSQL 服务状态失败: $e');
      }
    }
  }
}
