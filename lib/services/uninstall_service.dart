import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/notification_service.dart';
import '../services/install_service.dart';
import '../utils/nginx_project_helper.dart';

/// 卸载服务
class UninstallService {
  /// 卸载软件
  /// [software] 要卸载的软件
  /// [context] 用于显示对话框的上下文
  /// [onStopServer] 停止服务的回调函数
  /// [onRefresh] 刷新UI的回调函数
  static Future<void> uninstallSoftware(
    Software software, {
    required BuildContext context,
    required Future<void> Function(Software) onStopServer,
    required Future<void> Function() onRefresh,
  }) async {
    try {
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) {
        await NotificationService.showError(
          title: '错误',
          message: '存储目录未设置',
        );
        return;
      }

      final softwareSource = await SoftwareSourceService.getSource();
      if (softwareSource == null) {
        await NotificationService.showError(
          title: '错误',
          message: '软件源未加载',
        );
        return;
      }

      final cate4 = software.cate4?.toLowerCase() ?? '';
      final category = _getSoftwareCategory(software, softwareSource);

      // 根据软件类型执行不同的卸载逻辑
      if (cate4 == 'nginx') {
        await _uninstallNginx(software, storagePath, context, onStopServer);
      } else if (category == 'php') {
        await _uninstallPhp(
          software,
          storagePath,
          softwareSource,
          context,
          onStopServer,
        );
      } else if (category == 'databases') {
        await _uninstallDatabase(
          software,
          storagePath,
          softwareSource,
          context,
        );
      } else if (cate4 == 'mysql' || cate4 == 'pgsql' || cate4 == 'mongodb') {
        await _uninstallServiceDatabase(
          software,
          storagePath,
          cate4,
          onStopServer,
        );
      } else if (cate4 == 'redis' || cate4 == 'rudis') {
        await _uninstallRedisRudis(software, storagePath, onStopServer);
      } else if (cate4 == 'composer') {
        await _uninstallComposer(software, storagePath);
      } else if (cate4 == 'phpmyadmin') {
        await _uninstallPhpmyadmin(software, storagePath);
      } else if (cate4 == 'dbeaver') {
        await _uninstallDbeaver(software, storagePath, context);
      } else if (cate4 == 'tiny_rdm') {
        await _uninstallTinyRdm(software, storagePath, context);
      } else if (cate4 == 'mongodb_compass') {
        await _uninstallMongodbCompass(software, storagePath, context);
      } else if (cate4 == 'heidisql') {
        await _uninstallHeidisql(software, storagePath, context);
      } else {
        // 默认卸载逻辑：直接删除目录
        await _uninstallDefault(software, storagePath, category);
      }

      // 刷新UI
      await onRefresh();
    } catch (e) {
      await NotificationService.showError(
        title: '卸载失败',
        message: '卸载 ${software.name} 时发生错误: $e',
      );
    }
  }

  /// 获取软件类别
  static String _getSoftwareCategory(
    Software software,
    SoftwareSource softwareSource,
  ) {
    if (softwareSource.servers.any((s) => s.id == software.id)) return 'servers';
    if (softwareSource.databases.any((s) => s.id == software.id)) return 'databases';
    if (softwareSource.php.any((s) => s.id == software.id)) return 'php';
    if (softwareSource.tools.any((s) => s.id == software.id)) return 'tools';
    return '';
  }

  /// 获取用户主目录的 AppData\Roaming 路径
  static String _getUserRoamingPath() {
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    if (userProfile.isEmpty) {
      return '';
    }
    return path.join(userProfile, 'AppData', 'Roaming');
  }

  /// 卸载 nginx
  static Future<void> _uninstallNginx(
    Software software,
    String storagePath,
    BuildContext context,
    Future<void> Function(Software) onStopServer,
  ) async {
    // 显示提示对话框
    final shouldContinue = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('卸载 nginx'),
        content: const Text(
          '重新安装 nginx 后需要重新安装 PHP 才能正常使用项目管理功能。\n\n是否继续卸载？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认卸载'),
          ),
        ],
      ),
    );

    if (shouldContinue != true) {
      return;
    }

    // 停止 nginx 服务
    await onStopServer(software);

    // 删除 nginx 目录
    final nginxDir = Directory('$storagePath/servers/${software.id}');
    if (await nginxDir.exists()) {
      await nginxDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 卸载 PHP
  static Future<void> _uninstallPhp(
    Software software,
    String storagePath,
    SoftwareSource softwareSource,
    BuildContext context,
    Future<void> Function(Software) onStopServer,
  ) async {
    // 检查是否有项目在使用此 PHP 版本
    final projectsUsingPhp = await _findProjectsUsingPhp(
      software.id,
      storagePath,
    );

    if (projectsUsingPhp.isNotEmpty) {
      // 检查是否还有其他 PHP 版本
      final otherPhpVersions = await _getOtherPhpVersions(
        software.id,
        storagePath,
        softwareSource,
      );

      if (otherPhpVersions.isEmpty) {
        // 这是最后一个 PHP 版本
        final shouldContinue = await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: const Text('卸载 PHP'),
            content: Text(
              '此 PHP 版本是现存的最后一个 PHP 版本。\n\n'
              '以下项目正在使用此 PHP 版本：\n'
              '${projectsUsingPhp.map((p) => '  • $p').join('\n')}\n\n'
              '卸载后这些项目将无法正常运行。\n\n'
              '是否继续卸载？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('确认卸载'),
              ),
            ],
          ),
        );

        if (shouldContinue != true) {
          return;
        }

        // 更新所有使用此 PHP 版本的项目配置（注释掉 PHP include）
        await _updateProjectsRemovePhp(projectsUsingPhp, storagePath);

        // 删除 php.bat
        final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
        final phpBatFile = File(phpBatPath);
        if (await phpBatFile.exists()) {
          await phpBatFile.delete();
        }
      } else if (otherPhpVersions.length == 1) {
        // 只有一个其他 PHP 版本，自动切换
        final newPhpVersion = otherPhpVersions.first;
        await _updateProjectsSwitchPhp(
          projectsUsingPhp,
          software.id,
          newPhpVersion.id,
          storagePath,
        );
      } else {
        // 有多个其他 PHP 版本，让用户选择
        final selectedPhp = await _showPhpVersionSelectionDialog(
          otherPhpVersions,
          context,
        );
        if (selectedPhp == null) {
          return; // 用户取消
        }

        await _updateProjectsSwitchPhp(
          projectsUsingPhp,
          software.id,
          selectedPhp.id,
          storagePath,
        );
      }
    }

    // 停止 PHP 服务
    await onStopServer(software);

    // 删除 PHP 目录
    final phpDir = Directory('$storagePath/php/${software.id}');
    if (await phpDir.exists()) {
      await phpDir.delete(recursive: true);
    }

    // 如果不是最后一个 PHP 版本，更新 php.bat
    final remainingPhpVersions = await _getOtherPhpVersions(
      software.id,
      storagePath,
      softwareSource,
    );
    if (remainingPhpVersions.isNotEmpty) {
      // 获取默认 PHP 版本（优先使用第一个）
      final defaultPhp = remainingPhpVersions.first;
      final defaultPhpDir = Directory('$storagePath/php/${defaultPhp.id}');
      if (await defaultPhpDir.exists()) {
        await InstallService.updatePhpBat(defaultPhpDir.path, storagePath);
      }
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 查找使用指定 PHP 版本的项目
  static Future<List<String>> _findProjectsUsingPhp(
    String phpVersionId,
    String storagePath,
  ) async {
    final List<String> projects = [];

    // 检查 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final nginxProjects = await NginxProjectHelper.parseNginxConfigs(nginxDir);
      for (final project in nginxProjects) {
        final projectPhpVersion =
            await NginxProjectHelper.readPhpVersionFromConfig(
          project.confFilePath,
        );
        if (projectPhpVersion == phpVersionId) {
          projects.add(project.name);
        }
      }
    }

    // 检查非 nginx 项目（从 shared_preferences）
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('project_') &&
          !key.endsWith('_created_at') &&
          !key.endsWith('_last_started')) {
        final projectDataStr = prefs.getString(key);
        if (projectDataStr != null) {
          final phpMatch = RegExp(r"phpVersion:\s*(\w+)").firstMatch(
            projectDataStr,
          );
          if (phpMatch != null && phpMatch.group(1) == phpVersionId) {
            final projectName = key.substring(8); // 去掉'project_'前缀
            projects.add(projectName);
          }
        }
      }
    }

    return projects;
  }

  /// 获取其他 PHP 版本（排除指定的版本）
  static Future<List<Software>> _getOtherPhpVersions(
    String excludePhpId,
    String storagePath,
    SoftwareSource softwareSource,
  ) async {
    final List<Software> otherPhp = [];

    final phpDir = Directory('$storagePath/php');
    if (await phpDir.exists()) {
      await for (final entity in phpDir.list()) {
        if (entity is Directory) {
          final phpId = path.basename(entity.path);
          if (phpId != excludePhpId) {
            final php = softwareSource.php.firstWhere(
              (s) => s.id == phpId,
              orElse: () => Software(
                id: '',
                name: '',
                byte: 0,
                downloadURL: '',
                commands: [],
                attachments: [],
              ),
            );
            if (php.id.isNotEmpty) {
              otherPhp.add(php);
            }
          }
        }
      }
    }

    return otherPhp;
  }

  /// 显示 PHP 版本选择对话框
  static Future<Software?> _showPhpVersionSelectionDialog(
    List<Software> phpVersions,
    BuildContext context,
  ) async {
    Software? selectedPhp;

    return showDialog<Software>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('选择 PHP 版本'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: phpVersions
                  .map(
                    (php) => RadioListTile<Software>(
                      title: Text(php.name),
                      value: php,
                      groupValue: selectedPhp,
                      onChanged: (value) => setState(() => selectedPhp = value),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedPhp != null) {
                  Navigator.of(context).pop(selectedPhp);
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 更新项目配置，切换 PHP 版本
  static Future<void> _updateProjectsSwitchPhp(
    List<String> projectNames,
    String oldPhpId,
    String newPhpId,
    String storagePath,
  ) async {
    // 更新 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final nginxProjects = await NginxProjectHelper.parseNginxConfigs(nginxDir);
      for (final project in nginxProjects) {
        if (projectNames.contains(project.name)) {
          final content = await File(project.confFilePath).readAsString();
          final lines = content.split('\n');
          // 更新 PHP include 行
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.contains('include') &&
                line.contains('conf/php') &&
                line.contains('$oldPhpId.conf')) {
              lines[i] = lines[i].replaceAll(
                '$oldPhpId.conf',
                '$newPhpId.conf',
              );
              break;
            }
          }
          await File(project.confFilePath).writeAsString(lines.join('\n'));
        }
      }
    }

    // 更新非 nginx 项目（从 shared_preferences）
    final prefs = await SharedPreferences.getInstance();
    for (final projectName in projectNames) {
      final projectKey = 'project_$projectName';
      final projectDataStr = prefs.getString(projectKey);
      if (projectDataStr != null) {
        // 替换 phpVersion
        final newProjectDataStr = projectDataStr.replaceAll(
          'phpVersion: $oldPhpId',
          'phpVersion: $newPhpId',
        );
        await prefs.setString(projectKey, newProjectDataStr);
      }
    }
  }

  /// 更新项目配置，移除 PHP（注释掉 PHP include）
  static Future<void> _updateProjectsRemovePhp(
    List<String> projectNames,
    String storagePath,
  ) async {
    // 更新 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final nginxProjects = await NginxProjectHelper.parseNginxConfigs(nginxDir);
      for (final project in nginxProjects) {
        if (projectNames.contains(project.name)) {
          final content = await File(project.confFilePath).readAsString();
          final lines = content.split('\n');
          // 注释掉 PHP include 行
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.contains('include') &&
                line.contains('conf/php') &&
                !line.startsWith('#')) {
              lines[i] = '#${lines[i]}';
              break;
            }
          }
          await File(project.confFilePath).writeAsString(lines.join('\n'));
        }
      }
    }

    // 更新非 nginx 项目（从 shared_preferences）
    final prefs = await SharedPreferences.getInstance();
    for (final projectName in projectNames) {
      final projectKey = 'project_$projectName';
      final projectDataStr = prefs.getString(projectKey);
      if (projectDataStr != null) {
        // 移除或设置为 null
        final newProjectDataStr = projectDataStr.replaceAll(
          RegExp(r'phpVersion:\s*\w+'),
          'phpVersion: null',
        );
        await prefs.setString(projectKey, newProjectDataStr);
      }
    }
  }

  /// 卸载数据库软件
  static Future<void> _uninstallDatabase(
    Software software,
    String storagePath,
    SoftwareSource softwareSource,
    BuildContext context,
  ) async {
    // 查找使用此数据库的项目
    final projectsUsingDb = await _findProjectsUsingDatabase(
      software.id,
      storagePath,
    );

    if (projectsUsingDb.isNotEmpty) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('卸载数据库'),
          content: Text(
            '以下项目设置了此数据库为相关软件：\n'
            '${projectsUsingDb.map((p) => '  • $p').join('\n')}\n\n'
            '卸载后这些项目可能无法正常运行。\n\n'
            '是否继续卸载？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('确认卸载'),
            ),
          ],
        ),
      );

      if (shouldContinue != true) {
        return;
      }

      // 从项目配置中移除此数据库
      await _removeDatabaseFromProjects(projectsUsingDb, software.id, storagePath);
    }

    // 删除数据库目录
    final dbDir = Directory('$storagePath/databases/${software.id}');
    if (await dbDir.exists()) {
      await dbDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 查找使用指定数据库的项目
  static Future<List<String>> _findProjectsUsingDatabase(
    String databaseId,
    String storagePath,
  ) async {
    final List<String> projects = [];

    // 检查 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final nginxProjects = await NginxProjectHelper.parseNginxConfigs(nginxDir);
      for (final project in nginxProjects) {
        final projectDbIds = await NginxProjectHelper.readDatabaseIdsFromConfig(
          project.confFilePath,
        );
        if (projectDbIds.contains(databaseId)) {
          projects.add(project.name);
        }
      }
    }

    // 检查非 nginx 项目（从 shared_preferences）
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('project_') &&
          !key.endsWith('_created_at') &&
          !key.endsWith('_last_started')) {
        final projectDataStr = prefs.getString(key);
        if (projectDataStr != null) {
          final dbMatches = RegExp(r"databases:\s*\[(.*?)\]").firstMatch(
            projectDataStr,
          );
          if (dbMatches != null) {
            final dbStr = dbMatches.group(1) ?? '';
            final dbPattern = RegExp(r'''['"]?(\w+)['"]?''');
            final dbMatches2 = dbPattern.allMatches(dbStr);
            for (final match in dbMatches2) {
              final dbId = match.group(1);
              if (dbId == databaseId) {
                final projectName = key.substring(8); // 去掉'project_'前缀
                projects.add(projectName);
                break;
              }
            }
          }
        }
      }
    }

    return projects;
  }

  /// 从项目配置中移除数据库
  static Future<void> _removeDatabaseFromProjects(
    List<String> projectNames,
    String databaseId,
    String storagePath,
  ) async {
    // 更新 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final nginxProjects = await NginxProjectHelper.parseNginxConfigs(nginxDir);
      for (final project in nginxProjects) {
        if (projectNames.contains(project.name)) {
          final content = await File(project.confFilePath).readAsString();
          final lines = content.split('\n');
          // 移除数据库配置行
          bool inDatabaseSection = false;
          final newLines = <String>[];
          for (final line in lines) {
            if (line.trim() == '# ENV4PHP_CONF_DONT_EDIT') {
              inDatabaseSection = true;
              newLines.add(line);
            } else if (inDatabaseSection) {
              if (line.trim() == '# $databaseId') {
                // 跳过这一行（移除数据库ID）
                continue;
              } else if (line.trim().isNotEmpty &&
                  !line.trim().startsWith('#')) {
                // 遇到非注释行，结束数据库配置区域
                inDatabaseSection = false;
                newLines.add(line);
              } else {
                newLines.add(line);
              }
            } else {
              newLines.add(line);
            }
          }
          await File(project.confFilePath).writeAsString(newLines.join('\n'));
        }
      }
    }

    // 更新非 nginx 项目（从 shared_preferences）
    final prefs = await SharedPreferences.getInstance();
    for (final projectName in projectNames) {
      final projectKey = 'project_$projectName';
      final projectDataStr = prefs.getString(projectKey);
      if (projectDataStr != null) {
        // 从 databases 列表中移除
        final dbMatches = RegExp(r"databases:\s*\[(.*?)\]").firstMatch(
          projectDataStr,
        );
        if (dbMatches != null) {
          final dbStr = dbMatches.group(1) ?? '';
          final dbPattern = RegExp(r'''['"]?(\w+)['"]?''');
          final remainingDbIds = <String>[];
          for (final match in dbPattern.allMatches(dbStr)) {
            final dbId = match.group(1);
            if (dbId != null && dbId != databaseId) {
              remainingDbIds.add(dbId);
            }
          }
          final newDbStr = remainingDbIds.map((id) => "'$id'").join(', ');
          final newProjectDataStr = projectDataStr.replaceAll(
            RegExp(r"databases:\s*\[.*?\]"),
            'databases: [$newDbStr]',
          );
          await prefs.setString(projectKey, newProjectDataStr);
        }
      }
    }
  }

  /// 卸载服务型数据库（mysql, pgsql, mongodb）
  static Future<void> _uninstallServiceDatabase(
    Software software,
    String storagePath,
    String cate4,
    Future<void> Function(Software) onStopServer,
  ) async {
    // 停止服务
    await onStopServer(software);

    // 执行 sc delete 命令
    String serviceName;
    if (cate4 == 'mysql') {
      serviceName = 'MySQL';
    } else if (cate4 == 'pgsql') {
      serviceName = 'postgresql-x64-${software.id}'; // PostgreSQL 服务名格式
    } else if (cate4 == 'mongodb') {
      serviceName = 'MongoDB';
    } else {
      serviceName = software.id;
    }

    try {
      await Process.run('sc', ['delete', serviceName], runInShell: true);
      // 即使服务不存在（exitCode != 0），也继续删除目录
    } catch (e) {
      // 忽略错误，继续删除目录
    }

    // 删除目录
    final dbDir = Directory('$storagePath/databases/${software.id}');
    if (await dbDir.exists()) {
      await dbDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 卸载 redis/rudis
  static Future<void> _uninstallRedisRudis(
    Software software,
    String storagePath,
    Future<void> Function(Software) onStopServer,
  ) async {
    // 停止服务
    await onStopServer(software);

    // 删除目录
    final redisDir = Directory('$storagePath/databases/${software.id}');
    if (await redisDir.exists()) {
      await redisDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 卸载 composer
  static Future<void> _uninstallComposer(Software software, String storagePath) async {
    // 删除 composer.bat
    final composerBatPath = path.join(storagePath, 'bin', 'composer.bat');
    final composerBatFile = File(composerBatPath);
    if (await composerBatFile.exists()) {
      await composerBatFile.delete();
    }

    // 删除目录
    final composerDir = Directory('$storagePath/tools/${software.id}');
    if (await composerDir.exists()) {
      await composerDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 卸载 phpmyadmin
  static Future<void> _uninstallPhpmyadmin(
    Software software,
    String storagePath,
  ) async {
    // 删除 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final servsDir = Directory(path.join(nginxDir, 'servs'));
      if (await servsDir.exists()) {
        final projectConfFile = File(
          path.join(servsDir.path, 'phpmyadmin.conf'),
        );
        if (await projectConfFile.exists()) {
          await projectConfFile.delete();
        }
        final projectSubconfFile = File(
          path.join(servsDir.path, 'phpmyadmin.subconf'),
        );
        if (await projectSubconfFile.exists()) {
          await projectSubconfFile.delete();
        }
      }
    }

    // 删除目录
    final phpmyadminDir = Directory('$storagePath/tools/${software.id}');
    if (await phpmyadminDir.exists()) {
      await phpmyadminDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}。如果创建了 phpMyAdmin 数据库，请手动删除。',
    );
  }

  /// 卸载 dbeaver
  static Future<void> _uninstallDbeaver(
    Software software,
    String storagePath,
    BuildContext context,
  ) async {
    // 询问是否保留配置数据
    final keepConfig = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('卸载 DBeaver'),
        content: const Text('是否保留配置数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不保留'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保留'),
          ),
        ],
      ),
    );

    if (keepConfig != true) {
      // 删除配置数据
      final roamingPath = _getUserRoamingPath();
      if (roamingPath.isNotEmpty) {
        final dbeaverDataDir = Directory(path.join(roamingPath, 'DBeaverData'));
        if (await dbeaverDataDir.exists()) {
          await dbeaverDataDir.delete(recursive: true);
        }
      }
    }

    // 删除目录
    final dbeaverDir = Directory('$storagePath/tools/${software.id}');
    if (await dbeaverDir.exists()) {
      await dbeaverDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 卸载 tiny_rdm
  static Future<void> _uninstallTinyRdm(
    Software software,
    String storagePath,
    BuildContext context,
  ) async {
    // 询问是否保留配置数据
    final keepConfig = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('卸载 Tiny RDM'),
        content: const Text('是否保留配置数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不保留'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保留'),
          ),
        ],
      ),
    );

    if (keepConfig != true) {
      // 删除配置数据
      final roamingPath = _getUserRoamingPath();
      if (roamingPath.isNotEmpty) {
        final tinyRdmExeDir = Directory(path.join(roamingPath, 'Tiny RDM.exe'));
        if (await tinyRdmExeDir.exists()) {
          await tinyRdmExeDir.delete(recursive: true);
        }
        final tinyRdmDir = Directory(path.join(roamingPath, 'TinyRDM'));
        if (await tinyRdmDir.exists()) {
          await tinyRdmDir.delete(recursive: true);
        }
      }
    }

    // 删除目录
    final tinyRdmDir = Directory('$storagePath/tools/${software.id}');
    if (await tinyRdmDir.exists()) {
      await tinyRdmDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 卸载 mongodb_compass
  static Future<void> _uninstallMongodbCompass(
    Software software,
    String storagePath,
    BuildContext context,
  ) async {
    // 询问是否保留配置数据
    final keepConfig = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('卸载 MongoDB Compass'),
        content: const Text('是否保留配置数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不保留'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保留'),
          ),
        ],
      ),
    );

    if (keepConfig != true) {
      // 删除配置数据
      final roamingPath = _getUserRoamingPath();
      if (roamingPath.isNotEmpty) {
        final mongodbCompassDir = Directory(
          path.join(roamingPath, 'MongoDB Compass'),
        );
        if (await mongodbCompassDir.exists()) {
          await mongodbCompassDir.delete(recursive: true);
        }
      }
    }

    // 删除目录
    final mongodbCompassDir = Directory('$storagePath/tools/${software.id}');
    if (await mongodbCompassDir.exists()) {
      await mongodbCompassDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 卸载 heidisql
  static Future<void> _uninstallHeidisql(
    Software software,
    String storagePath,
    BuildContext context,
  ) async {
    // 询问是否保留配置数据
    final keepConfig = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('卸载 HeidiSQL'),
        content: const Text('是否保留配置数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不保留'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保留'),
          ),
        ],
      ),
    );

    if (keepConfig != true) {
      // 删除配置数据
      final roamingPath = _getUserRoamingPath();
      if (roamingPath.isNotEmpty) {
        final heidisqlDir = Directory(path.join(roamingPath, 'HeidiSQL'));
        if (await heidisqlDir.exists()) {
          await heidisqlDir.delete(recursive: true);
        }
      }
    }

    // 删除目录
    final heidisqlDir = Directory('$storagePath/tools/${software.id}');
    if (await heidisqlDir.exists()) {
      await heidisqlDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 默认卸载逻辑
  static Future<void> _uninstallDefault(
    Software software,
    String storagePath,
    String category,
  ) async {
    // 直接删除目录
    final softwareDir = Directory('$storagePath/$category/${software.id}');
    if (await softwareDir.exists()) {
      await softwareDir.delete(recursive: true);
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }
}

