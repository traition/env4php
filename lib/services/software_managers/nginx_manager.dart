import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../../models/software_model.dart';
import '../notification_service.dart';
import 'software_manager.dart';
import 'software_manager_helper.dart';
import '../../utils/nginx_project_helper.dart';

/// Nginx 软件管理器
class NginxManager extends SoftwareManager {
  @override
  String get supportedCate4 => 'nginx';

  /// 检查 nginx 配置
  Future<({bool success, String output})> _checkNginxConfig(
    String nginxDir,
  ) async {
    return await NginxProjectHelper.checkNginxConfig(nginxDir);
  }

  @override
  Future<(bool success, String? error)> start(Software server) async {
    try {
      final nginxDir = await SoftwareManagerHelper.getNginxDirectory();
      if (nginxDir == null) {
        await NotificationService.showError(
          title: '启动失败',
          message: 'nginx未安装',
        );
        return (false, 'nginx未安装');
      }

      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) {
        await NotificationService.showError(
          title: '启动失败',
          message: '找不到nginx.exe文件: $nginxExe',
        );
        return (false, '找不到nginx.exe文件: $nginxExe');
      }

      // 启动前先执行停止命令，确保没有残留进程
      try {
        await Process.run(
          nginxExe,
          ['-s', 'stop'],
          runInShell: true,
          workingDirectory: nginxDir,
        );
        // 等待一小段时间，确保进程完全停止
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // 如果停止失败（可能nginx未运行），继续执行启动
        if (kDebugMode) {
          print('停止nginx时发生错误（可能nginx未运行）: $e');
        }
      }

      // 启动前检查nginx配置
      final configResult = await _checkNginxConfig(nginxDir);
      if (!configResult.success) {
        // 配置检查失败，显示错误（这里只返回错误，不显示对话框，由调用者处理）
        await NotificationService.showError(
          title: 'nginx配置检查失败',
          message: configResult.output,
        );
        return (false, 'nginx配置检查失败: ${configResult.output}');
      }

      // 新建nginx进程
      await Process.start(
        nginxExe,
        [],
        workingDirectory: nginxDir,
        mode: ProcessStartMode.detached,
      );

      await NotificationService.showSuccess(
        title: '启动成功',
        message: '${server.name} 已启动',
      );
      return (true, null);
    } catch (e) {
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
      final nginxDir = await SoftwareManagerHelper.getNginxDirectory();
      if (nginxDir == null) return (true, null);

      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) return (true, null);

      final result = await Process.run(
        nginxExe,
        ['-s', 'stop'],
        runInShell: true,
        workingDirectory: nginxDir,
      );

      if (result.exitCode == 0) {
        return (true, null);
      } else {
        return (true, null); // 即使失败也返回成功，可能nginx未运行
      }
    } catch (e) {
      if (kDebugMode) {
        print('[静默停止Nginx] 发生异常: $e');
      }
      return (true, null); // 即使失败也返回成功
    }
  }

  @override
  Future<(bool success, String? error)> stop(Software server) async {
    try {
      final nginxDir = await SoftwareManagerHelper.getNginxDirectory();
      if (nginxDir == null) {
        await NotificationService.showError(
          title: '停止失败',
          message: 'nginx未安装',
        );
        return (false, 'nginx未安装');
      }

      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) {
        await NotificationService.showError(
          title: '停止失败',
          message: '找不到nginx.exe文件: $nginxExe',
        );
        return (false, '找不到nginx.exe文件: $nginxExe');
      }

      final result = await Process.run(
        nginxExe,
        ['-s', 'stop'],
        runInShell: true,
        workingDirectory: nginxDir,
      );

      if (result.exitCode == 0) {
        await NotificationService.showSuccess(
          title: '停止成功',
          message: '${server.name} 已停止',
        );
        return (true, null);
      } else {
        // 即使退出码非0，也可能已经停止（nginx可能未运行）
        await NotificationService.showInfo(
          title: '提示',
          message: '${server.name} 可能已经停止',
        );
        return (true, null);
      }
    } catch (e) {
      await NotificationService.showError(
        title: '停止失败',
        message: '停止 ${server.name} 时发生错误: $e',
      );
      return (false, '停止失败: $e');
    }
  }

  @override
  Future<(bool success, String? error)> restart(Software server) async {
    try {
      final nginxDir = await SoftwareManagerHelper.getNginxDirectory();
      if (nginxDir == null) {
        await NotificationService.showError(
          title: '重启失败',
          message: 'nginx未安装',
        );
        return (false, 'nginx未安装');
      }

      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) {
        await NotificationService.showError(
          title: '重启失败',
          message: '找不到nginx.exe文件: $nginxExe',
        );
        return (false, '找不到nginx.exe文件: $nginxExe');
      }

      // 检查nginx配置
      final configResult = await _checkNginxConfig(nginxDir);
      if (!configResult.success) {
        await NotificationService.showError(
          title: 'nginx配置检查失败',
          message: configResult.output,
        );
        return (false, 'nginx配置检查失败: ${configResult.output}');
      }

      // 执行重启命令: nginx目录\nginx -s reopen
      final result = await Process.run(
        nginxExe,
        ['-s', 'reload'],
        runInShell: true,
        workingDirectory: nginxDir,
      );

      if (result.exitCode == 0) {
        await NotificationService.showSuccess(
          title: '重启成功',
          message: '${server.name} 已重启',
        );
        return (true, null);
      } else {
        // 如果reload失败，尝试先停止再启动
        if (kDebugMode) {
          print('[Nginx重启] reload失败，尝试先停止再启动');
        }
        final stopResult = await stop(server);
        if (!stopResult.$1) {
          return stopResult;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        return await start(server);
      }
    } catch (e) {
      await NotificationService.showError(
        title: '重启失败',
        message: '重启 ${server.name} 时发生错误: $e',
      );
      return (false, '重启失败: $e');
    }
  }
}

