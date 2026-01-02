import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hosts_service.dart';
import '../services/notification_service.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../models/software_model.dart';

/// Nginx项目配置数据类
class NginxProjectConfig {
  final String projectName;
  final Map<String, dynamic> nginxConfig;
  final List<String> databases;
  final String? phpVersionId;
  final String? framework;
  final String? rewriteRule;

  NginxProjectConfig({
    required this.projectName,
    required this.nginxConfig,
    required this.databases,
    this.phpVersionId,
    this.framework,
    this.rewriteRule,
  });
}

/// Nginx项目信息数据类
class NginxProjectInfo {
  final String name; // server_name:port格式
  final String confFilePath; // 配置文件路径
  final String serverName; // server_name值
  final String ports; // 端口（多个用|分隔）
  final DateTime? createdAt; // 创建时间
  final DateTime? lastStartedAt; // 最后启动时间
  final bool isFromSharedPreferences; // 是否来自shared_preferences

  NginxProjectInfo({
    required this.name,
    required this.confFilePath,
    required this.serverName,
    required this.ports,
    this.createdAt,
    this.lastStartedAt,
    this.isFromSharedPreferences = false,
  });
}

/// Nginx项目创建辅助类
class NginxProjectHelper {
  /// 准备nginx项目的基础环境
  /// 返回 (nginxDir, servsDir, projectConfFile, lines) 或 null
  static Future<
    ({
      String nginxDir,
      Directory servsDir,
      File projectConfFile,
      List<String> lines,
    })?
  >
  prepareNginxProjectEnvironment(String projectName, String nginxDir) async {
    try {
      final servsDir = Directory(path.join(nginxDir, 'servs'));
      if (!await servsDir.exists()) {
        await servsDir.create(recursive: true);
      }

      // 读取example文件
      final exampleFile = File(path.join(nginxDir, 'dont_delete.conf.example'));
      if (!await exampleFile.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '找不到dont_delete.conf.example文件',
        );
        return null;
      }

      final projectConfFile = File(
        path.join(servsDir.path, '$projectName.conf'),
      );
      final content = await exampleFile.readAsString();
      final lines = content.split('\n');

      return (
        nginxDir: nginxDir,
        servsDir: servsDir,
        projectConfFile: projectConfFile,
        lines: lines,
      );
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '准备nginx项目环境失败: $e',
      );
      return null;
    }
  }

  /// 修改nginx配置文件的端口
  static void updatePort(List<String> lines, String port) {
    if (lines.length >= 2) {
      lines[1] = lines[1].replaceAll(RegExp(r'listen\s+\d+'), 'listen $port');
    }
  }

  /// 处理SSL配置
  /// 返回是否成功，如果返回false表示用户取消或失败
  static Future<bool> handleSslConfig(
    List<String> lines,
    Map<String, dynamic> nginxConfig,
    String projectName,
    Directory servsDir,
    Future<bool> Function(String certPath, String keyPath) generateCert,
  ) async {
    if (nginxConfig['enableSsl'] != true) {
      return true; // 未启用SSL，直接返回成功
    }

    final sslPort = nginxConfig['sslPort'] ?? '443';

    // 修改SSL端口并取消注释
    if (lines.length >= 3) {
      lines[2] = lines[2]
          .replaceAll('#listen', 'listen')
          .replaceAll('#--#', sslPort);
    }
    if (lines.length >= 4) {
      lines[3] = lines[3].replaceAll('#http2', 'http2');
    }

    final certPath = path.join(servsDir.path, '$projectName.pem');
    final keyPath = path.join(servsDir.path, '$projectName.key');

    // 处理证书
    if (nginxConfig['useSelfSignedCert'] == true) {
      // 生成自签证书
      final certGenerated = await generateCert(certPath, keyPath);
      if (!certGenerated) {
        return false; // 用户取消或生成失败
      }
    } else {
      // 写入用户提供的证书和密钥内容
      final userCertContent = nginxConfig['certPath'] as String?;
      final userKeyContent = nginxConfig['keyPath'] as String?;
      if (userCertContent != null && userCertContent.isNotEmpty) {
        await File(certPath).writeAsString(userCertContent);
      }
      if (userKeyContent != null && userKeyContent.isNotEmpty) {
        await File(keyPath).writeAsString(userKeyContent);
      }
    }

    // 修改SSL配置行
    if (lines.length >= 15) {
      lines[14] = lines[14]
          .replaceAll('#ssl_certificate', 'ssl_certificate')
          .replaceAll('#--#', '$projectName.pem');
    }
    if (lines.length >= 16) {
      lines[15] = lines[15]
          .replaceAll('#ssl_certificate_key', 'ssl_certificate_key')
          .replaceAll('#--#', '$projectName.key');
    }
    // 取消其他SSL相关行的注释
    if (lines.length >= 17) lines[16] = lines[16].replaceAll('#', '');
    if (lines.length >= 18) lines[17] = lines[17].replaceAll('#', '');
    if (lines.length >= 21) lines[20] = lines[20].replaceAll('#', '');
    if (lines.length >= 22) lines[21] = lines[21].replaceAll('#', '');
    if (lines.length >= 23) lines[22] = lines[22].replaceAll('#', '');

    return true;
  }

  /// 修改server_name
  static void updateServerName(List<String> lines, String serverName) {
    if (lines.length >= 5) {
      lines[4] = lines[4].replaceAll('#--#', serverName);
    }
  }

  /// 修改root路径
  static void updateRootPath(List<String> lines, String rootPath) {
    if (lines.length >= 8) {
      final normalizedPath = rootPath.replaceAll('\\', '/');
      lines[7] = lines[7].replaceAll('#--#', normalizedPath);
    }
  }

  /// 修改项目名称行（第49、50行）
  static void updateProjectNameLines(List<String> lines, String projectName) {
    if (lines.length >= 49) {
      lines[48] = lines[48].replaceAll('#--#', projectName);
    }
    if (lines.length >= 50) {
      lines[49] = lines[49].replaceAll('#--#', projectName);
    }
  }

  /// 修改PHP include行
  static void updatePhpInclude(List<String> lines, String phpVersionId) {
    if (lines.length >= 12) {
      lines[11] = lines[11].replaceAll('#--#', '$phpVersionId.conf');
    }
  }

  /// 注释PHP include行（用于静态项目）
  static void commentPhpInclude(List<String> lines) {
    if (lines.length >= 12) {
      if (!lines[11].trim().startsWith('#')) {
        lines[11] = '#${lines[11]}';
      }
    }
  }

  /// 创建守护进程项目的subconf文件
  static Future<void> createDaemonSubconf(
    String projectName,
    String framework,
    Map<String, dynamic> nginxConfig,
    String nginxDir,
    Directory servsDir,
  ) async {
    final subconfFile = File(path.join(servsDir.path, '$projectName.subconf'));

    if (framework == 'other' &&
        (nginxConfig['customRules'] as String?)?.isEmpty != false) {
      // 没有框架配置也没有自定义规则，创建空文件
      await subconfFile.writeAsString('');
      return;
    }

    final preconfFile = File(
      path.join(nginxDir, 'conf', 'preconf', '$framework.conf'),
    );
    if (!await preconfFile.exists()) {
      await subconfFile.writeAsString('');
      return;
    }

    var subconfContent = await preconfFile.readAsString();
    final subconfLines = subconfContent.split('\n');

    // 取消注释开头的连续#行
    int commentEndIndex = 0;
    for (int i = 0; i < subconfLines.length; i++) {
      if (subconfLines[i].trim().startsWith('#')) {
        subconfLines[i] = subconfLines[i].replaceFirst('#', '');
        commentEndIndex = i + 1;
      } else {
        break;
      }
    }

    // 插入upstream配置
    final upstreamPorts = (nginxConfig['upstreamPorts'] as String).split(',');
    final upstreamLines = upstreamPorts
        .map((port) => '  server 127.0.0.1:${port.trim()};')
        .toList();
    subconfLines.insert(commentEndIndex, upstreamLines.join('\n'));

    // 添加自定义规则
    final customRules = nginxConfig['customRules'] as String?;
    if (customRules != null && customRules.isNotEmpty) {
      subconfLines.add(customRules);
    }

    await subconfFile.writeAsString(subconfLines.join('\n'));
  }

  /// 创建普通PHP项目的subconf文件（伪静态规则）
  static Future<void> createNormalPhpSubconf(
    String projectName,
    String? rewriteRule,
    String nginxDir,
    Directory servsDir,
  ) async {
    final subconfFile = File(path.join(servsDir.path, '$projectName.subconf'));

    if (rewriteRule != null && rewriteRule.isNotEmpty) {
      final rewriteConfFile = File(
        path.join(nginxDir, 'conf', 'preconf', '$rewriteRule.conf'),
      );
      if (await rewriteConfFile.exists()) {
        final rewriteContent = await rewriteConfFile.readAsString();
        await subconfFile.writeAsString(rewriteContent);
      } else {
        await subconfFile.writeAsString('');
      }
    } else {
      await subconfFile.writeAsString('');
    }
  }

  /// 创建静态项目的subconf文件（自定义规则）
  static Future<void> createStaticSubconf(
    String projectName,
    String? customRules,
    Directory servsDir,
  ) async {
    final subconfFile = File(path.join(servsDir.path, '$projectName.subconf'));
    await subconfFile.writeAsString(customRules ?? '');
  }

  /// 修改include conf/preconf行
  static void updatePreconfInclude(List<String> lines, String projectName) {
    if (lines.length >= 26) {
      lines[25] = lines[25].replaceAll('#--#', 'servs/$projectName.subconf');
    }
  }

  /// 添加数据库配置
  static void addDatabaseConfig(List<String> lines, List<String> databases) {
    final dbConfigLines = <String>['# ENV4PHP_CONF_DONT_EDIT'];
    for (final dbId in databases) {
      dbConfigLines.add('# $dbId');
    }
    lines.addAll(dbConfigLines);
  }

  /// 从nginx配置文件中读取PHP版本ID
  /// [confFilePath] nginx配置文件路径
  /// 返回PHP版本ID，如果未找到或已注释则返回null
  static Future<String?> readPhpVersionFromConfig(String confFilePath) async {
    try {
      final confFile = File(confFilePath);
      if (!await confFile.exists()) {
        return null;
      }

      final content = await confFile.readAsString();
      final lines = content.split('\n');

      // 查找 include ../conf/php/ 行（通常在第11-12行）
      for (final line in lines) {
        final trimmedLine = line.trim();
        // 跳过注释行（包括整行注释和行内注释）
        if (trimmedLine.startsWith('#')) {
          continue;
        }
        // 匹配 include ../conf/php/phpVersionId.conf; 格式
        // 也支持 include conf/php/phpVersionId.conf; 格式（向后兼容）
        // 例如：include ../conf/php/php8.5.1.conf; 或 include conf/php/php81.conf;
        final match = RegExp(r'include\s+\.\.?/conf/php/([^/]+)\.conf;').firstMatch(trimmedLine);
        if (match != null) {
          final phpVersionId = match.group(1);
          if (phpVersionId != null && phpVersionId.isNotEmpty) {
            return phpVersionId;
          }
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[Nginx项目助手] 读取PHP版本失败: $e');
      }
      return null;
    }
  }

  /// 从nginx配置文件中读取数据库ID列表
  /// [confFilePath] nginx配置文件路径
  /// 返回数据库ID列表
  static Future<List<String>> readDatabaseIdsFromConfig(
    String confFilePath,
  ) async {
    try {
      final confFile = File(confFilePath);
      if (!await confFile.exists()) {
        return [];
      }

      final content = await confFile.readAsString();
      final lines = content.split('\n');

      final List<String> databaseIds = [];
      bool inDatabaseSection = false;

      for (final line in lines) {
        final trimmedLine = line.trim();

        // 检测数据库配置区域开始
        if (trimmedLine == '# ENV4PHP_CONF_DONT_EDIT') {
          inDatabaseSection = true;
          continue;
        }

        // 如果在数据库配置区域
        if (inDatabaseSection) {
          // 匹配 # databaseId 格式
          if (trimmedLine.startsWith('# ')) {
            final dbId = trimmedLine.substring(2).trim();
            if (dbId.isNotEmpty && dbId != 'ENV4PHP_CONF_DONT_EDIT') {
              databaseIds.add(dbId);
            }
          } else if (trimmedLine.isNotEmpty && !trimmedLine.startsWith('#')) {
            // 遇到非注释行，结束数据库配置区域
            break;
          }
        }
      }

      return databaseIds;
    } catch (e) {
      if (kDebugMode) {
        print('[Nginx项目助手] 读取数据库ID列表失败: $e');
      }
      return [];
    }
  }

  /// 完成项目创建后的通用操作
  /// 返回是否成功
  static Future<bool> finalizeProjectCreation(
    String nginxDir,
    File projectConfFile,
    List<String> lines,
    String projectName,
    String serverName,
    Future<({bool success, String output})> Function(String nginxDir)
    checkNginxConfig,
    Future<void> Function(String output) showNginxConfigErrorDialog,
    Future<bool> Function() isNginxRunning,
    Future<void> Function() reloadNginx,
  ) async {
    try {
      // 写入配置文件
      await projectConfFile.writeAsString(lines.join('\n'));

      // 检查nginx配置
      final configResult = await checkNginxConfig(nginxDir);
      if (!configResult.success) {
        await showNginxConfigErrorDialog(configResult.output);
        return false;
      }

      // 检查并更新hosts文件
      if (serverName.isNotEmpty) {
        await _checkAndUpdateHosts(serverName);
      }

      await NotificationService.showSuccess(
        title: '创建成功',
        message: '项目 $projectName 创建成功',
      );

      // 如果nginx正在运行，重新加载配置
      if (await isNginxRunning()) {
        await reloadNginx();
      }

      return true;
    } catch (e) {
      await NotificationService.showError(title: '创建失败', message: '创建项目失败: $e');
      return false;
    }
  }

  /// 检查并更新hosts文件
  static Future<void> _checkAndUpdateHosts(String serverName) async {
    try {
      // 检查是否以.localhost结尾
      if (serverName.endsWith('.localhost')) {
        return; // 以.localhost结尾，无需处理
      }

      // 检查是否为IPv4或IPv6地址
      if (HostsService.isIPv4(serverName) || HostsService.isIPv6(serverName)) {
        return; // 是IP地址，无需处理
      }

      // 不是.localhost结尾，也不是IP地址，需要更新hosts文件
      final success = await HostsService.ensureDomainPointsToLocalhost(
        serverName,
      );
      if (!success) {
        if (kDebugMode) {
          print('更新hosts文件失败: $serverName');
        }
        // 不显示错误，静默处理，避免影响项目创建流程
      }
    } catch (e) {
      if (kDebugMode) {
        print('检查并更新hosts文件时发生错误: $e');
      }
      // 不显示错误，静默处理
    }
  }

  /// 检查 nginx 配置是否正确
  /// 返回 (是否成功, 输出内容)
  static Future<({bool success, String output})> checkNginxConfig(
    String nginxDir,
  ) async {
    try {
      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) {
        final errorMsg = '找不到nginx.exe文件: $nginxExe';
        return (success: false, output: errorMsg);
      }

      // 执行 nginx -t 命令
      final result = await Process.run(
        nginxExe,
        ['-t'],
        runInShell: true,
        workingDirectory: nginxDir,
      );

      // 获取输出（合并stdout和stderr）
      final output = '${result.stdout}${result.stderr}';

      // 检查输出是否以 "test is successful" 结尾（不区分大小写）
      final normalizedOutput = output.trim().toLowerCase();
      if (normalizedOutput.endsWith('test is successful')) {
        return (success: true, output: output);
      } else {
        // 配置检查失败
        return (success: false, output: output);
      }
    } catch (e) {
      final errorMsg = '执行nginx配置检查时发生错误: $e';
      return (success: false, output: errorMsg);
    }
  }

  /// 获取nginx安装目录
  /// 返回nginx目录路径，如果未安装返回null
  static Future<String?> getNginxDirectory() async {
    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return null;

    // 查找nginx软件
    Software? nginx;
    try {
      nginx = softwareSource.servers.firstWhere(
        (s) => s.cate4?.toLowerCase() == 'nginx',
      );
    } catch (e) {
      try {
        nginx = softwareSource.servers.firstWhere(
          (s) => s.id.toLowerCase() == 'nginx',
        );
      } catch (e) {
        // 未找到nginx
      }
    }

    if (nginx == null) return null;

    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    // 检查 servers 目录
    final serversDir = Directory('$storagePath/servers/${nginx.id}');
    if (await serversDir.exists()) {
      return serversDir.path;
    }

    // 检查 databases 目录（某些情况下nginx可能在databases分类）
    final databasesDir = Directory('$storagePath/databases/${nginx.id}');
    if (await databasesDir.exists()) {
      return databasesDir.path;
    }

    return null;
  }

  /// 检查nginx是否正在运行
  /// [serverRunningStatus] 服务器运行状态映射
  /// 返回是否正在运行
  static Future<bool> isNginxRunning(
    Map<String, bool> serverRunningStatus,
  ) async {
    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return false;

    // 查找nginx软件
    Software? nginx;
    try {
      nginx = softwareSource.servers.firstWhere(
        (s) => s.cate4?.toLowerCase() == 'nginx',
      );
    } catch (e) {
      try {
        nginx = softwareSource.servers.firstWhere(
          (s) => s.id.toLowerCase() == 'nginx',
        );
      } catch (e) {
        // 未找到nginx
      }
    }

    if (nginx == null) return false;

    // 检查运行状态
    return serverRunningStatus[nginx.id] ?? false;
  }

  /// 重新加载nginx配置
  /// [nginxDir] nginx安装目录
  /// 返回是否成功
  static Future<bool> reloadNginx(String nginxDir) async {
    try {
      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) {
        if (kDebugMode) {
          print('nginx.exe不存在: $nginxExe');
        }
        return false;
      }

      // 执行reload命令: nginx目录\nginx -s reload
      final result = await Process.run(
        nginxExe,
        ['-s', 'reload'],
        runInShell: true,
        workingDirectory: nginxDir,
      );

      if (result.exitCode != 0) {
        if (kDebugMode) {
          print('nginx配置重新加载失败: ${result.stderr}');
        }
        return false;
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('重新加载nginx配置时发生错误: $e');
      }
      return false;
    }
  }

  /// 解析nginx配置文件，提取server_name和listen
  /// [nginxDir] nginx安装目录
  /// 返回项目信息列表
  static Future<List<NginxProjectInfo>> parseNginxConfigs(
    String nginxDir,
  ) async {
    final List<NginxProjectInfo> projects = [];
    final servsDir = Directory(path.join(nginxDir, 'servs'));

    if (!await servsDir.exists()) {
      return projects;
    }

    // 遍历servs目录下的所有conf文件
    await for (final entity in servsDir.list()) {
      if (entity is File && entity.path.endsWith('.conf')) {
        try {
          final content = await entity.readAsString();
          final projectInfos = await parseNginxConfig(content, entity.path);
          projects.addAll(projectInfos);
        } catch (e) {
          if (kDebugMode) {
            print('解析nginx配置文件失败: ${entity.path}, 错误: $e');
          }
          // 忽略解析失败的文件
          continue;
        }
      }
    }

    return projects;
  }

  /// 解析单个nginx配置文件内容
  /// [content] 配置文件内容
  /// [filePath] 配置文件路径
  /// 返回项目信息列表
  static Future<List<NginxProjectInfo>> parseNginxConfig(
    String content,
    String filePath,
  ) async {
    final List<NginxProjectInfo> projects = [];

    // 使用正则表达式匹配server块
    final serverBlockPattern = RegExp(
      r'server\s*\{[^}]*\}',
      multiLine: true,
      dotAll: true,
    );

    final matches = serverBlockPattern.allMatches(content);

    for (final match in matches) {
      final serverBlock = match.group(0) ?? '';

      // 提取server_name
      final serverNamePattern = RegExp(r'server_name\s+([^;]+);');
      final serverNameMatch = serverNamePattern.firstMatch(serverBlock);
      if (serverNameMatch == null) continue;

      String serverName = serverNameMatch.group(1)?.trim() ?? '';
      // 去掉引号
      serverName = serverName.replaceAll(RegExp(r'''["']'''), '');
      // 去掉结尾的'.localhost'
      if (serverName.endsWith('.localhost')) {
        serverName = serverName.substring(0, serverName.length - 10);
      }

      // 提取listen（忽略注释）
      final listenPattern = RegExp(r'^\s*listen\s+([^;#]+);', multiLine: true);
      final listenMatches = listenPattern.allMatches(serverBlock);

      final List<String> ports = [];
      for (final listenMatch in listenMatches) {
        String listenValue = listenMatch.group(1)?.trim() ?? '';
        // 提取端口号（可能是 "80" 或 "127.0.0.1:80" 格式）
        final portMatch = RegExp(r':?(\d+)$').firstMatch(listenValue);
        if (portMatch != null) {
          ports.add(portMatch.group(1)!);
        } else if (RegExp(r'^\d+$').hasMatch(listenValue)) {
          // 如果直接是端口号
          ports.add(listenValue);
        }
      }

      if (ports.isEmpty) continue;

      // 组合端口（多个用|分隔）
      final portsStr = ports.join('|');

      // 组合名称：server_name:port
      final projectName = '$serverName:$portsStr';

      // 获取文件创建时间
      final file = File(filePath);
      DateTime? createdAt;
      DateTime? lastStartedAt;
      if (await file.exists()) {
        final stat = await file.stat();
        createdAt = stat.modified;
        // 尝试从shared_preferences读取最后启动时间
        final prefs = await SharedPreferences.getInstance();
        final lastStartedKey = 'project_${projectName}_last_started';
        final lastStartedStr = prefs.getString(lastStartedKey);
        if (lastStartedStr != null) {
          try {
            lastStartedAt = DateTime.parse(lastStartedStr);
          } catch (e) {
            // 解析失败，忽略
          }
        }
      }

      projects.add(
        NginxProjectInfo(
          name: projectName,
          confFilePath: filePath,
          serverName: serverName,
          ports: portsStr,
          createdAt: createdAt,
          lastStartedAt: lastStartedAt,
        ),
      );
    }

    return projects;
  }
}
