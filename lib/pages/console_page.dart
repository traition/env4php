import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/notification_service.dart';
import '../services/install_service.dart';
import '../services/software_action_service.dart';
import '../models/software_model.dart';
import '../utils/software_menu_helper.dart';
import '../utils/nginx_project_helper.dart';
import 'nginx_config_page.dart';

/// 控制台页面
class ConsolePage extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const ConsolePage({super.key, this.navigatorKey});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

/// 项目信息模型
class _ProjectInfo {
  final String name; // server_name:port格式
  final String confFilePath; // 配置文件路径
  final String serverName; // server_name值
  final String ports; // 端口（多个用|分隔）
  final DateTime? createdAt; // 创建时间
  final DateTime? lastStartedAt; // 最后启动时间
  final bool isFromSharedPreferences; // 是否来自shared_preferences

  _ProjectInfo({
    required this.name,
    required this.confFilePath,
    required this.serverName,
    required this.ports,
    this.createdAt,
    this.lastStartedAt,
    this.isFromSharedPreferences = false,
  });
}

class _ConsolePageState extends State<ConsolePage> {
  List<_ProjectInfo> _projects = []; // 项目列表
  List<Software> _installedServers = []; // 已安装的服务器列表
  bool _isLoadingServers = true; // 是否正在加载服务器列表
  bool _isLoadingProjects = true; // 是否正在加载项目列表
  bool _isNginxInstalled = false; // nginx是否已安装
  // 跟踪每个应用的运行状态：true表示运行中，false表示已停止
  final Map<String, bool> _serverRunningStatus = {};
  // 跟踪每个项目的运行状态：true表示运行中，false表示已停止
  final Map<String, bool> _projectRunningStatus = {};

  @override
  void initState() {
    super.initState();
    _loadInstalledServers();
    _loadProjects();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 控制台内容区域：左右分栏
        Expanded(
          child: Row(
            children: [
              // 左侧：Servers 列表（占50%）
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                  child: _buildServersList(),
                ),
              ),
              // 右侧：项目列表（占50%）
              Expanded(flex: 1, child: _buildProjectsList()),
            ],
          ),
        ),
      ],
    );
  }

  /// 加载已安装的服务器列表
  Future<void> _loadInstalledServers() async {
    if (mounted) {
      setState(() {
        _isLoadingServers = true;
      });
    }

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) {
      if (mounted) {
        setState(() {
          _isLoadingServers = false;
          _installedServers = [];
        });
      }
      return;
    }

    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) {
      if (mounted) {
        setState(() {
          _isLoadingServers = false;
          _installedServers = [];
        });
      }
      return;
    }

    final List<Software> installed = [];

    // 允许的 cate4 值
    const allowedCate4 = [
      'nginx',
      'mysql',
      'pgsql',
      'redis',
      'rudis',
      'mongodb',
    ];

    // 检查 servers 分类
    for (final software in softwareSource.servers) {
      final cate4 = software.cate4?.toLowerCase();
      if (cate4 != null && allowedCate4.contains(cate4)) {
        final dir = Directory('$storagePath/servers/${software.id}');
        if (await dir.exists()) {
          installed.add(software);
          // 初始化运行状态为 false（未启动）
          if (!_serverRunningStatus.containsKey(software.id)) {
            _serverRunningStatus[software.id] = false;
          }
        }
      }
    }

    // 检查 databases 分类
    for (final software in softwareSource.databases) {
      final cate4 = software.cate4?.toLowerCase();
      if (cate4 != null && allowedCate4.contains(cate4)) {
        final dir = Directory('$storagePath/databases/${software.id}');
        if (await dir.exists()) {
          installed.add(software);
          // 初始化运行状态为 false（未启动）
          if (!_serverRunningStatus.containsKey(software.id)) {
            _serverRunningStatus[software.id] = false;
          }
        }
      }
    }

    // 检查 php 分类（所有 php 应用）
    for (final software in softwareSource.php) {
      final dir = Directory('$storagePath/php/${software.id}');
      if (await dir.exists()) {
        installed.add(software);
        // 初始化运行状态为 false（未启动）
        if (!_serverRunningStatus.containsKey(software.id)) {
          _serverRunningStatus[software.id] = false;
        }
      }
    }

    if (mounted) {
      setState(() {
        _installedServers = installed;
        _isLoadingServers = false;
      });
    }
  }

  /// 全部启动服务器（占位函数）
  void _startAllServers() {
    // TODO: 实现全部启动逻辑
    NotificationService.showInfo(title: '提示', message: '全部启动（功能待实现）');
  }

  /// 全部停止服务器（占位函数）
  void _stopAllServers() {
    // TODO: 实现全部停止逻辑
    NotificationService.showInfo(title: '提示', message: '全部停止（功能待实现）');
  }

  /// 启动单个服务器
  Future<void> _startServer(Software server) async {
    try {
      // 检查是否是nginx
      if (server.cate4?.toLowerCase() == 'nginx') {
        final nginxDir = await _getNginxDirectory();
        if (nginxDir == null) {
          await NotificationService.showError(
            title: '启动失败',
            message: 'nginx未安装',
          );
          return;
        }

        final nginxExe = path.join(nginxDir, 'nginx.exe');
        final nginxFile = File(nginxExe);
        if (!await nginxFile.exists()) {
          await NotificationService.showError(
            title: '启动失败',
            message: '找不到nginx.exe文件: $nginxExe',
          );
          return;
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
          // 配置检查失败，显示错误对话框
          await _showNginxConfigErrorDialog(configResult.output);
          return;
        }

        // 新建nginx进程
        await Process.start(
          nginxExe,
          [],
          workingDirectory: nginxDir,
          mode: ProcessStartMode.detached,
        );

        setState(() {
          _serverRunningStatus[server.id] = true;
        });

        await NotificationService.showSuccess(
          title: '启动成功',
          message: '${server.name} 已启动',
        );
      } else {
        // 其他服务器类型暂未实现
        setState(() {
          _serverRunningStatus[server.id] = true;
        });
        await NotificationService.showInfo(
          title: '提示',
          message: '启动 ${server.name}（功能待实现）',
        );
      }
    } catch (e) {
      await NotificationService.showError(
        title: '启动失败',
        message: '启动 ${server.name} 时发生错误: $e',
      );
    }
  }

  /// 停止单个服务器
  Future<void> _stopServer(Software server) async {
    try {
      // 检查是否是nginx
      if (server.cate4?.toLowerCase() == 'nginx') {
        final nginxDir = await _getNginxDirectory();
        if (nginxDir == null) {
          await NotificationService.showError(
            title: '停止失败',
            message: 'nginx未安装',
          );
          return;
        }

        final nginxExe = path.join(nginxDir, 'nginx.exe');
        final nginxFile = File(nginxExe);
        if (!await nginxFile.exists()) {
          await NotificationService.showError(
            title: '停止失败',
            message: '找不到nginx.exe文件: $nginxExe',
          );
          return;
        }

        // 执行停止命令: nginx目录\nginx -s stop
        final result = await Process.run(
          nginxExe,
          ['-s', 'stop'],
          runInShell: true,
          workingDirectory: nginxDir,
        );

        if (result.exitCode == 0) {
          setState(() {
            _serverRunningStatus[server.id] = false;
          });
          await NotificationService.showSuccess(
            title: '停止成功',
            message: '${server.name} 已停止',
          );
        } else {
          await NotificationService.showError(
            title: '停止失败',
            message: '停止 ${server.name} 失败: ${result.stderr}',
          );
        }
      } else {
        // 其他服务器类型暂未实现
        setState(() {
          _serverRunningStatus[server.id] = false;
        });
        await NotificationService.showInfo(
          title: '提示',
          message: '停止 ${server.name}（功能待实现）',
        );
      }
    } catch (e) {
      await NotificationService.showError(
        title: '停止失败',
        message: '停止 ${server.name} 时发生错误: $e',
      );
    }
  }

  /// 重启单个服务器
  Future<void> _restartServer(Software server) async {
    try {
      // 检查是否是nginx
      if (server.cate4?.toLowerCase() == 'nginx') {
        final nginxDir = await _getNginxDirectory();
        if (nginxDir == null) {
          await NotificationService.showError(
            title: '重启失败',
            message: 'nginx未安装',
          );
          return;
        }

        final nginxExe = path.join(nginxDir, 'nginx.exe');
        final nginxFile = File(nginxExe);
        if (!await nginxFile.exists()) {
          await NotificationService.showError(
            title: '重启失败',
            message: '找不到nginx.exe文件: $nginxExe',
          );
          return;
        }

        // 重启前检查nginx配置
        final configResult = await _checkNginxConfig(nginxDir);
        if (!configResult.success) {
          // 配置检查失败，显示错误对话框
          await _showNginxConfigErrorDialog(configResult.output);
          return;
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
        } else {
          await NotificationService.showError(
            title: '重启失败',
            message: '重启 ${server.name} 失败: ${result.stderr}',
          );
        }
      } else {
        // 其他服务器类型暂未实现
        await NotificationService.showInfo(
          title: '提示',
          message: '重启 ${server.name}（功能待实现）',
        );
      }
    } catch (e) {
      await NotificationService.showError(
        title: '重启失败',
        message: '重启 ${server.name} 时发生错误: $e',
      );
    }
  }

  /// 获取服务器显示名称（去除[*]后的部分）
  String _getServerDisplayName(String name) {
    // 查找第一个'['的位置
    final bracketIndex = name.indexOf('[');
    if (bracketIndex != -1) {
      // 如果找到'['，只显示'['前的部分
      return name.substring(0, bracketIndex);
    }
    // 如果没有找到'['，返回原名称
    return name;
  }

  /// 构建服务器列表项
  Widget _buildServerItem(Software server, bool isRunning) {
    // 获取显示名称（去除[*]后的部分）
    final displayName = _getServerDisplayName(server.name);

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showServerContextMenu(details.globalPosition, server);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 服务器名称（只显示前15个字符）
                Expanded(
                  child: Text(
                    displayName.length > 15
                        ? '${displayName.substring(0, 15)}...'
                        : displayName,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 按钮组
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 启动按钮（只在未启动时显示）
                    if (!isRunning)
                      TextButton.icon(
                        onPressed: () => _startServer(server),
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        label: const Text('启动'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    // 停止按钮（只在启动后显示）
                    if (isRunning)
                      TextButton.icon(
                        onPressed: () => _stopServer(server),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('停止'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    // 重启按钮（只在启动后显示）
                    if (isRunning)
                      TextButton.icon(
                        onPressed: () => _restartServer(server),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重启'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // 分隔线（独立于列表项边距）
          if (server != _installedServers.last)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.95,
                  child: Container(
                    height: 0.5,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 显示服务器右键菜单
  Future<void> _showServerContextMenu(Offset position, Software server) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect positionRelativeRect = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
    );

    // 检查是否已安装
    final isInstalled = _installedServers.any((s) => s.id == server.id);
    final softwareSource = await SoftwareSourceService.getSource();

    // 使用共享的菜单项构建逻辑
    final menuItems = await SoftwareMenuHelper.buildContextMenuItems(
      server,
      isInstalled: isInstalled,
      softwareSource: softwareSource,
    );

    // 转换为 PopupMenuItem
    final popupItems = <PopupMenuEntry<String>>[];
    for (final item in menuItems) {
      if (item.isDivider) {
        popupItems.add(const PopupMenuDivider());
      } else {
        popupItems.add(
          PopupMenuItem<String>(
            value: item.action.name,
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: item.iconColor),
                const SizedBox(width: 8),
                Text(item.label, style: TextStyle(color: item.textColor)),
              ],
            ),
          ),
        );
      }
    }

    final value = await showMenu<String>(
      context: context,
      position: positionRelativeRect,
      items: popupItems,
    );

    if (value == null) return;

    // 根据菜单项执行相应操作
    try {
      final action = SoftwareMenuAction.values.firstWhere(
        (a) => a.name == value,
        orElse: () {
          if (kDebugMode) {
            print('未找到对应的菜单操作: $value');
          }
          return SoftwareMenuAction.manage;
        },
      );

      if (kDebugMode) {
        print('执行菜单操作: ${action.name} for ${server.name}');
      }

      await _handleMenuAction(action, server);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('处理菜单选择时发生错误: $e');
        print('堆栈跟踪: $stackTrace');
      }
      NotificationService.showError(title: '操作失败', message: '执行菜单操作时发生错误: $e');
    }
  }

  /// 处理菜单操作
  Future<void> _handleMenuAction(
    SoftwareMenuAction action,
    Software software,
  ) async {
    try {
      // 获取软件源
      final softwareSource = await SoftwareSourceService.getSource();

      switch (action) {
        case SoftwareMenuAction.install:
          _showInstallDialog(software);
          break;
        case SoftwareMenuAction.uninstall:
          _showUninstallDialog(software);
          break;
        case SoftwareMenuAction.manage:
          // 保留此选项以兼容性，但右键菜单不再显示
          await _showManageDialog(software);
          break;
        default:
          // 其他操作都使用共享的服务类
          await SoftwareActionService.handleMenuAction(
            action,
            software,
            context: context,
            navigatorKey: widget.navigatorKey,
            softwareSource: softwareSource,
          );
          break;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('处理菜单操作时发生错误: $e');
        print('堆栈跟踪: $stackTrace');
      }
      await NotificationService.showError(
        title: '操作失败',
        message: '执行操作时发生错误: $e',
      );
    }
  }

  /// 构建 Servers 列表
  Widget _buildServersList() {
    // 如果正在加载，显示加载提示
    if (_isLoadingServers) {
      return const Center(child: CircularProgressIndicator());
    }

    // 如果列表为空，显示提示文字
    if (_installedServers.isEmpty) {
      return Center(
        child: Text(
          '先去安装应用吧',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
      );
    }

    // 不为空时显示列表和操作按钮
    return Column(
      children: [
        // 顶部工具栏：全部操作按钮组
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          height: 48, // 固定高度，与项目列表按钮栏对齐
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // 按钮组：全部
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "全部"文字
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 40, // 确保有足够宽度显示文字
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '全部',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 24,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    // 启动按钮
                    TextButton.icon(
                      onPressed: _startAllServers,
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('启动'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 24,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    // 停止按钮
                    TextButton.icon(
                      onPressed: _stopAllServers,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('停止'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 服务器列表
        Expanded(
          child: ListView.builder(
            itemCount: _installedServers.length,
            itemBuilder: (context, index) {
              final server = _installedServers[index];
              final isRunning = _serverRunningStatus[server.id] ?? false;
              return _buildServerItem(server, isRunning);
            },
          ),
        ),
      ],
    );
  }

  /// 检查nginx是否已安装
  Future<String?> _getNginxDirectory() async {
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

  /// 检查nginx是否正在运行
  Future<bool> _isNginxRunning() async {
    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return false;

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

    if (nginx.id.isEmpty) return false;

    // 检查运行状态
    return _serverRunningStatus[nginx.id] ?? false;
  }

  /// 重新加载nginx配置
  Future<void> _reloadNginx() async {
    try {
      final nginxDir = await _getNginxDirectory();
      if (nginxDir == null) {
        return; // nginx未安装，无需reload
      }

      final nginxExe = path.join(nginxDir, 'nginx.exe');
      final nginxFile = File(nginxExe);
      if (!await nginxFile.exists()) {
        return; // nginx.exe不存在，无需reload
      }

      // 执行reload命令: nginx目录\nginx -s reload
      final result = await Process.run(
        nginxExe,
        ['-s', 'reload'],
        runInShell: true,
        workingDirectory: nginxDir,
      );

      if (result.exitCode != 0) {
        await NotificationService.showError(
          title: '重新加载配置失败',
          message: 'nginx配置重新加载失败: ${result.stderr}',
        );
      }
    } catch (e) {
      // 静默处理错误，不影响项目创建流程
      if (kDebugMode) {
        print('重新加载nginx配置时发生错误: $e');
      }
    }
  }

  /// 检查nginx配置是否正确
  /// 返回 (是否成功, 输出内容)
  Future<({bool success, String output})> _checkNginxConfig(
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

  /// 显示nginx配置检查失败的对话框
  Future<void> _showNginxConfigErrorDialog(String output) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFF0C0C0C);
    final textColor = isDark
        ? const Color(0xFF00FF00)
        : const Color(0xFF00FF00);

    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('nginx配置检查失败'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('nginx配置有误，请检查配置文件。', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              // 命令行样式的输出区域
              Expanded(
                child: Container(
                  width: double.maxFinite,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade700),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      output.isEmpty ? '(无输出)' : output,
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 12,
                        color: textColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 解析nginx配置文件，提取server_name和listen
  Future<List<_ProjectInfo>> _parseNginxConfigs(String nginxDir) async {
    final List<_ProjectInfo> projects = [];
    final servsDir = Directory(path.join(nginxDir, 'servs'));

    if (!await servsDir.exists()) {
      return projects;
    }

    // 遍历servs目录下的所有conf文件
    await for (final entity in servsDir.list()) {
      if (entity is File && entity.path.endsWith('.conf')) {
        try {
          final content = await entity.readAsString();
          final projectInfos = await _parseNginxConfig(content, entity.path);
          projects.addAll(projectInfos);
        } catch (e) {
          // 忽略解析失败的文件
          continue;
        }
      }
    }

    return projects;
  }

  /// 解析单个nginx配置文件内容
  Future<List<_ProjectInfo>> _parseNginxConfig(
    String content,
    String filePath,
  ) async {
    final List<_ProjectInfo> projects = [];

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
        _ProjectInfo(
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

  /// 加载项目列表
  Future<void> _loadProjects() async {
    if (mounted) {
      setState(() {
        _isLoadingProjects = true;
      });
    }

    final List<_ProjectInfo> projects = [];

    // 1. 从nginx配置文件中加载项目
    final nginxDir = await _getNginxDirectory();
    if (nginxDir != null) {
      _isNginxInstalled = true;
      final nginxProjects = await _parseNginxConfigs(nginxDir);
      projects.addAll(nginxProjects);
    } else {
      _isNginxInstalled = false;
    }

    // 2. 从shared_preferences中加载项目
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('project_') &&
          !key.endsWith('_created_at') &&
          !key.endsWith('_last_started')) {
        final projectName = key.substring(8); // 去掉'project_'前缀
        final projectDataStr = prefs.getString(key);
        if (projectDataStr != null) {
          // 检查是否已存在于nginx项目中
          final exists = projects.any((p) => p.name == projectName);
          if (!exists) {
            // 从shared_preferences创建项目信息
            DateTime? createdAt;
            DateTime? lastStartedAt;
            final createdAtKey = 'project_${projectName}_created_at';
            final lastStartedKey = 'project_${projectName}_last_started';
            final createdAtStr = prefs.getString(createdAtKey);
            final lastStartedStr = prefs.getString(lastStartedKey);
            if (createdAtStr != null) {
              try {
                createdAt = DateTime.parse(createdAtStr);
              } catch (e) {
                // 解析失败，忽略
              }
            }
            if (lastStartedStr != null) {
              try {
                lastStartedAt = DateTime.parse(lastStartedStr);
              } catch (e) {
                // 解析失败，忽略
              }
            }
            final projectInfo = _ProjectInfo(
              name: projectName,
              confFilePath: '', // shared_preferences项目没有配置文件
              serverName: projectName,
              ports: '',
              createdAt: createdAt,
              lastStartedAt: lastStartedAt,
              isFromSharedPreferences: true,
            );
            projects.add(projectInfo);
          }
        }
      }
    }

    // 3. 排序：按最近启动时间，然后按最近创建时间
    projects.sort((a, b) {
      // 先按最后启动时间排序（最近启动的在前）
      if (a.lastStartedAt != null && b.lastStartedAt != null) {
        final startCompare = b.lastStartedAt!.compareTo(a.lastStartedAt!);
        if (startCompare != 0) return startCompare;
      } else if (a.lastStartedAt != null) {
        return -1; // a有启动时间，b没有，a在前
      } else if (b.lastStartedAt != null) {
        return 1; // b有启动时间，a没有，b在前
      }
      // 如果启动时间相同或都没有，按创建时间排序（最近创建的在前）
      if (a.createdAt != null && b.createdAt != null) {
        return b.createdAt!.compareTo(a.createdAt!);
      } else if (a.createdAt != null) {
        return -1;
      } else if (b.createdAt != null) {
        return 1;
      }
      return 0;
    });

    // 初始化项目运行状态
    for (final project in projects) {
      if (!_projectRunningStatus.containsKey(project.name)) {
        _projectRunningStatus[project.name] = false;
      }
    }

    if (mounted) {
      setState(() {
        _projects = projects;
        _isLoadingProjects = false;
      });
    }
  }

  /// 启动项目（占位函数）
  void _startProject(_ProjectInfo project) {
    setState(() {
      _projectRunningStatus[project.name] = true;
    });
    NotificationService.showInfo(
      title: '提示',
      message: '启动 ${project.name}（功能待实现）',
    );
  }

  /// 停止项目（占位函数）
  void _stopProject(_ProjectInfo project) {
    setState(() {
      _projectRunningStatus[project.name] = false;
    });
    NotificationService.showInfo(
      title: '提示',
      message: '停止 ${project.name}（功能待实现）',
    );
  }

  /// 重启项目（占位函数）
  void _restartProject(_ProjectInfo project) {
    NotificationService.showInfo(
      title: '提示',
      message: '重启 ${project.name}（功能待实现）',
    );
  }

  /// 打开项目（占位函数）
  void _openProject(_ProjectInfo project) {
    // TODO: 实现打开项目逻辑（可能在浏览器中打开）
    NotificationService.showInfo(
      title: '提示',
      message: '打开 ${project.name}（功能待实现）',
    );
  }

  /// 构建项目列表项
  Widget _buildProjectItem(_ProjectInfo project, bool isRunning) {
    // 项目名称只显示前15个字符
    final displayName = project.name.length > 15
        ? '${project.name.substring(0, 15)}...'
        : project.name;

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showProjectContextMenu(details.globalPosition, project);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 项目名称
                Expanded(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 按钮组
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 启动按钮（只在未启动时显示）
                    if (!isRunning)
                      TextButton.icon(
                        onPressed: () => _startProject(project),
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        label: const Text('启动'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    // 停止按钮（只在启动后显示）
                    if (isRunning)
                      TextButton.icon(
                        onPressed: () => _stopProject(project),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('停止'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    // 重启按钮（只在启动后显示）
                    if (isRunning)
                      TextButton.icon(
                        onPressed: () => _restartProject(project),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重启'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    // 打开按钮（始终显示）
                    TextButton.icon(
                      onPressed: () => _openProject(project),
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text('打开'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 分隔线（独立于列表项边距）
          if (project != _projects.last)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.95,
                  child: Container(
                    height: 0.5,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 显示项目右键菜单
  void _showProjectContextMenu(Offset position, _ProjectInfo project) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect positionRelativeRect = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
    );

    final isNginxProject = project.confFilePath.isNotEmpty;

    showMenu<String>(
      context: context,
      position: positionRelativeRect,
      items: [
        if (isNginxProject) ...[
          PopupMenuItem<String>(
            value: 'open_access_log',
            child: const Text('打开访问日志'),
          ),
          PopupMenuItem<String>(
            value: 'open_error_log',
            child: const Text('打开错误日志'),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(value: 'open_conf', child: const Text('打开配置')),
          PopupMenuItem<String>(
            value: 'open_subconf',
            child: const Text('打开子配置'),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              Text('删除项目', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'open_access_log':
          _openProjectAccessLog(project);
          break;
        case 'open_error_log':
          _openProjectErrorLog(project);
          break;
        case 'open_conf':
          _openProjectConf(project);
          break;
        case 'open_subconf':
          _openProjectSubconf(project);
          break;
        case 'delete':
          _deleteProject(project);
          break;
      }
    });
  }

  /// 使用PowerShell打开文件
  Future<void> _openFileWithExplorer(
    String filePath,
    String errorMessage,
  ) async {
    try {
      final normalizedPath = filePath.replaceAll('/', '\\');
      final command = 'explorer "$normalizedPath"';
      final result = await Process.run('powershell', [
        '-Command',
        command,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '$errorMessage: $e',
      );
    }
  }

  /// 打开项目访问日志
  Future<void> _openProjectAccessLog(_ProjectInfo project) async {
    if (project.confFilePath.isEmpty) {
      await NotificationService.showError(title: '错误', message: '项目配置文件不存在');
      return;
    }

    final nginxDir = await _getNginxDirectory();
    if (nginxDir == null) {
      await NotificationService.showError(title: '错误', message: 'nginx未安装');
      return;
    }

    final confFile = File(project.confFilePath);
    final projectName = path.basenameWithoutExtension(confFile.path);
    final logPath = path.join(nginxDir, 'logs', '$projectName.access.log');

    final logFile = File(logPath);
    if (!await logFile.exists()) {
      await NotificationService.showError(title: '错误', message: '访问日志文件不存在');
      return;
    }

    await _openFileWithExplorer(logPath, '无法打开访问日志');
  }

  /// 打开项目错误日志
  Future<void> _openProjectErrorLog(_ProjectInfo project) async {
    if (project.confFilePath.isEmpty) {
      await NotificationService.showError(title: '错误', message: '项目配置文件不存在');
      return;
    }

    final nginxDir = await _getNginxDirectory();
    if (nginxDir == null) {
      await NotificationService.showError(title: '错误', message: 'nginx未安装');
      return;
    }

    final confFile = File(project.confFilePath);
    final projectName = path.basenameWithoutExtension(confFile.path);
    final logPath = path.join(nginxDir, 'logs', '$projectName.error.log');

    final logFile = File(logPath);
    if (!await logFile.exists()) {
      await NotificationService.showError(title: '错误', message: '错误日志文件不存在');
      return;
    }

    await _openFileWithExplorer(logPath, '无法打开错误日志');
  }

  /// 打开项目配置文件
  Future<void> _openProjectConf(_ProjectInfo project) async {
    if (project.confFilePath.isEmpty) {
      await NotificationService.showError(title: '错误', message: '项目配置文件不存在');
      return;
    }

    await _openFileWithExplorer(project.confFilePath, '无法打开配置文件');
  }

  /// 打开项目子配置文件
  Future<void> _openProjectSubconf(_ProjectInfo project) async {
    if (project.confFilePath.isEmpty) {
      await NotificationService.showError(title: '错误', message: '项目配置文件不存在');
      return;
    }

    final confFile = File(project.confFilePath);
    final projectName = path.basenameWithoutExtension(confFile.path);
    final servsDir = confFile.parent;
    final subconfPath = path.join(servsDir.path, '$projectName.subconf');

    final subconfFile = File(subconfPath);
    if (!await subconfFile.exists()) {
      await NotificationService.showError(title: '错误', message: '子配置文件不存在');
      return;
    }

    await _openFileWithExplorer(subconfPath, '无法打开子配置文件');
  }

  /// 删除项目
  Future<void> _deleteProject(_ProjectInfo project) async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除项目 "${project.name}" 吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // 如果是nginx项目，删除配置文件
      if (project.confFilePath.isNotEmpty) {
        final confFile = File(project.confFilePath);
        if (await confFile.exists()) {
          await confFile.delete();
        }

        // 删除子配置文件
        final projectName = path.basenameWithoutExtension(confFile.path);
        final servsDir = confFile.parent;
        final subconfPath = path.join(servsDir.path, '$projectName.subconf');
        final subconfFile = File(subconfPath);
        if (await subconfFile.exists()) {
          await subconfFile.delete();
        }

        // 删除SSL证书文件（如果存在）
        final certPath = path.join(servsDir.path, '$projectName.pem');
        final keyPath = path.join(servsDir.path, '$projectName.key');
        final certFile = File(certPath);
        final keyFile = File(keyPath);
        if (await certFile.exists()) {
          await certFile.delete();
        }
        if (await keyFile.exists()) {
          await keyFile.delete();
        }
      }

      // 删除shared_preferences中的项目数据
      final prefs = await SharedPreferences.getInstance();
      final projectKey = 'project_${project.name}';
      final createdAtKey = 'project_${project.name}_created_at';
      final lastStartedKey = 'project_${project.name}_last_started';
      await prefs.remove(projectKey);
      await prefs.remove(createdAtKey);
      await prefs.remove(lastStartedKey);

      // 从列表中移除项目
      setState(() {
        _projects.removeWhere((p) => p.name == project.name);
        _projectRunningStatus.remove(project.name);
      });

      await NotificationService.showSuccess(
        title: '删除成功',
        message: '项目 "${project.name}" 已删除',
      );
    } catch (e) {
      await NotificationService.showError(title: '删除失败', message: '删除项目失败: $e');
    }
  }

  /// 构建项目列表
  Widget _buildProjectsList() {
    // 如果正在加载，显示加载提示
    if (_isLoadingProjects) {
      return const Center(child: CircularProgressIndicator());
    }

    // 如果nginx未安装，只显示提示信息
    if (!_isNginxInstalled) {
      return Center(
        child: Text(
          '请先安装nginx',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
      );
    }

    // 如果项目列表为空，显示居中的新建项目按钮
    if (_projects.isEmpty) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _createNewProject,
          icon: const Icon(Icons.add),
          label: const Text('新建项目'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      );
    }

    // 有项目时，显示项目列表和右上角的新建按钮
    return Column(
      children: [
        // 顶部工具栏：新建按钮
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 48, // 固定高度，与servers列表按钮栏对齐
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: _createNewProject,
                icon: const Icon(Icons.add),
                label: const Text('新建项目'),
              ),
            ],
          ),
        ),
        // 项目列表
        Expanded(
          child: ListView.builder(
            itemCount: _projects.length,
            itemBuilder: (context, index) {
              final project = _projects[index];
              final isRunning = _projectRunningStatus[project.name] ?? false;
              return _buildProjectItem(project, isRunning);
            },
          ),
        ),
      ],
    );
  }

  /// 创建新项目
  Future<void> _createNewProject() async {
    // 1. 选择项目类型
    final projectType = await _showProjectTypeDialog();
    if (projectType == null) return;

    // 2. 输入项目名称
    final projectName = await _showProjectNameDialog();
    if (projectName == null || projectName.isEmpty) return;

    // 验证项目名称格式
    if (!_isValidProjectName(projectName)) {
      await NotificationService.showError(
        title: '验证失败',
        message: '项目名称只能包含英文、数字、-、_、()、[]',
      );
      return;
    }

    // 验证项目名称是否重复
    final nginxDir = await _getNginxDirectory();
    if (nginxDir != null) {
      final servsDir = Directory(path.join(nginxDir, 'servs'));
      if (await servsDir.exists()) {
        final projectConfFile = File(
          path.join(servsDir.path, '$projectName.conf'),
        );
        if (await projectConfFile.exists()) {
          await NotificationService.showError(
            title: '验证失败',
            message: '项目名称 "$projectName" 已存在',
          );
          return;
        }
      }
    }

    // 根据项目类型处理
    if (projectType == 'daemon_php') {
      await _createDaemonPhpProject(projectName);
    } else if (projectType == 'normal_php') {
      await _createNormalPhpProject(projectName);
    } else if (projectType == 'static') {
      await _createStaticProject(projectName);
    }

    // 重新加载项目列表
    await _loadProjects();
  }

  /// 显示项目类型选择对话框
  Future<String?> _showProjectTypeDialog() async {
    return showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('选择项目类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('守护进程PHP项目'),
              subtitle: const Text('EasySwoole, Webman, Hyperf等'),
              onTap: () => Navigator.of(context).pop('daemon_php'),
            ),
            ListTile(
              title: const Text('普通PHP项目'),
              subtitle: const Text('传统PHP项目'),
              onTap: () => Navigator.of(context).pop('normal_php'),
            ),
            ListTile(
              title: const Text('静态项目'),
              subtitle: const Text('HTML/CSS/JS静态网站'),
              onTap: () => Navigator.of(context).pop('static'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示项目名称输入对话框
  Future<String?> _showProjectNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('输入项目名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '项目名称',
            hintText: '只能包含英文、数字、-、_、()、[]',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop(name);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 验证项目名称格式
  bool _isValidProjectName(String name) {
    final regex = RegExp(r'^[a-zA-Z0-9\-_()\[\]]+$');
    return regex.hasMatch(name);
  }

  /// 生成默认的server_name（基于项目名称，去除_, (), []）
  String _generateDefaultServerName(String projectName) {
    // 去除_, (), []
    String serverName = projectName
        .replaceAll('_', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('[', '')
        .replaceAll(']', '');
    return '$serverName.localhost';
  }

  /// 检查server_name:port是否已存在
  bool _isServerNamePortExists(String serverName, String port) {
    // 如果server_name是'.localhost'，视为空
    if (serverName.trim() == '.localhost' || serverName.trim().isEmpty) {
      return false; // 空值会在后续验证中被拒绝
    }

    // 规范化server_name（去掉.localhost后缀，统一比较）
    String normalizeServerName(String name) {
      String normalized = name.trim();
      if (normalized.endsWith('.localhost')) {
        normalized = normalized.substring(0, normalized.length - 10);
      }
      return normalized;
    }

    final normalizedCheckServerName = normalizeServerName(serverName);

    // 检查现有项目中是否有相同的server_name:port组合
    for (final project in _projects) {
      final projectPorts = project.ports.split('|');
      if (projectPorts.contains(port)) {
        // 检查server_name是否相同（规范化后比较）
        final normalizedProjectServerName = normalizeServerName(
          project.serverName,
        );

        if (normalizedProjectServerName == normalizedCheckServerName) {
          return true;
        }
      }
    }
    return false;
  }

  /// 验证server_name和port配置
  String? _validateServerNameAndPort(
    String serverName,
    String port,
    bool enableSsl,
    String sslPort,
  ) {
    // 检查server_name是否为空或'.localhost'
    final trimmedServerName = serverName.trim();
    if (trimmedServerName.isEmpty || trimmedServerName == '.localhost') {
      return 'server_name不能为空';
    }

    // 检查port是否为空
    if (port.trim().isEmpty) {
      return '端口不能为空';
    }

    // 检查默认端口是否重复
    if (_isServerNamePortExists(trimmedServerName, port.trim())) {
      return '$trimmedServerName:$port 已存在';
    }

    // 如果启用了SSL，检查SSL端口是否重复
    if (enableSsl) {
      if (sslPort.trim().isEmpty) {
        return 'SSL端口不能为空';
      }
      if (_isServerNamePortExists(trimmedServerName, sslPort.trim())) {
        return '$trimmedServerName:$sslPort 已存在';
      }
    }

    return null; // 验证通过
  }

  /// 创建守护进程PHP项目
  Future<void> _createDaemonPhpProject(String projectName) async {
    // 2.1 选择框架和设置启动命令
    final frameworkResult = await _showDaemonFrameworkDialog();
    if (frameworkResult == null) return;

    final framework = frameworkResult['framework'] as String;
    final startCommand = frameworkResult['command'] as String;

    // 2.2 询问是否需要nginx
    final needNginx = await _showNginxNeededDialog();
    if (needNginx == null) return;

    String? phpVersionId;
    List<String> selectedDatabases = [];

    if (needNginx) {
      // 2.2.1 需要nginx的配置
      final nginxConfig = await Navigator.of(context)
          .push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (context) => NginxConfigPage(
                projectName: projectName,
                configType: 'daemon',
                framework: framework,
                validateServerNameAndPort: _validateServerNameAndPort,
              ),
            ),
          );
      if (nginxConfig == null) return;

      // 选择PHP版本
      phpVersionId = await _showPhpVersionDialog();
      if (phpVersionId == null) return;

      // 选择数据库
      final databases1 = await _showDatabaseSelectionDialog();
      if (databases1 == null) return;
      selectedDatabases = databases1;

      // 执行文件操作
      await _createDaemonPhpProjectWithNginx(
        projectName,
        framework,
        startCommand,
        nginxConfig,
        phpVersionId,
        selectedDatabases,
      );
    } else {
      // 2.2.2 不需要nginx
      // 选择PHP版本
      phpVersionId = await _showPhpVersionDialog();
      if (phpVersionId == null) return;

      // 选择数据库
      final databases2 = await _showDatabaseSelectionDialog();
      if (databases2 == null) return;
      selectedDatabases = databases2;

      // 执行逻辑
      await _createDaemonPhpProjectWithoutNginx(
        projectName,
        startCommand,
        phpVersionId,
        selectedDatabases,
      );
    }
  }

  /// 创建普通PHP项目
  Future<void> _createNormalPhpProject(String projectName) async {
    // 3.1 配置nginx
    final nginxConfig = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => NginxConfigPage(
          projectName: projectName,
          configType: 'normal',
          validateServerNameAndPort: _validateServerNameAndPort,
        ),
      ),
    );
    if (nginxConfig == null) return;

    // 3.2 选择PHP版本
    final phpVersionId = await _showPhpVersionDialog();
    if (phpVersionId == null) return;

    // 选择数据库
    final selectedDatabases = await _showDatabaseSelectionDialog();
    if (selectedDatabases == null) return;

    // 执行文件操作
    await _createNormalPhpProjectFiles(
      projectName,
      nginxConfig,
      phpVersionId,
      selectedDatabases,
    );
  }

  /// 创建静态项目
  Future<void> _createStaticProject(String projectName) async {
    // 4.1 配置nginx
    final nginxConfig = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => NginxConfigPage(
          projectName: projectName,
          configType: 'static',
          validateServerNameAndPort: _validateServerNameAndPort,
        ),
      ),
    );
    if (nginxConfig == null) return;

    // 选择数据库
    final databases4 = await _showDatabaseSelectionDialog();
    if (databases4 == null) return;

    // 执行文件操作
    await _createStaticProjectFiles(projectName, nginxConfig, databases4);
  }

  /// 显示守护进程框架选择对话框
  Future<Map<String, dynamic>?> _showDaemonFrameworkDialog() async {
    String? selectedFramework;
    final commandController = TextEditingController();

    // 预设命令
    final presetCommands = {
      'easyswoole': 'php easyswoole.php server start -d',
      'webman': 'php windows.php',
      'hyperf': 'php bin/hyperf.php start',
    };

    return showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('选择框架和启动命令'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 框架选择
                RadioListTile<String>(
                  title: const Text('EasySwoole'),
                  value: 'easyswoole',
                  groupValue: selectedFramework,
                  onChanged: (value) {
                    setState(() {
                      selectedFramework = value;
                      commandController.text = presetCommands['easyswoole']!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Webman'),
                  value: 'webman',
                  groupValue: selectedFramework,
                  onChanged: (value) {
                    setState(() {
                      selectedFramework = value;
                      commandController.text = presetCommands['webman']!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Hyperf'),
                  value: 'hyperf',
                  groupValue: selectedFramework,
                  onChanged: (value) {
                    setState(() {
                      selectedFramework = value;
                      commandController.text = presetCommands['hyperf']!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('其他'),
                  value: 'other',
                  groupValue: selectedFramework,
                  onChanged: (value) {
                    setState(() {
                      selectedFramework = value;
                      commandController.clear();
                    });
                  },
                ),
                const SizedBox(height: 16),
                // 启动命令输入
                TextField(
                  controller: commandController,
                  decoration: const InputDecoration(
                    labelText: '启动命令',
                    hintText: '例如: php easyswoole.php server start -d',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedFramework != null &&
                    commandController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop({
                    'framework': selectedFramework,
                    'command': commandController.text.trim(),
                  });
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示是否需要nginx对话框
  Future<bool?> _showNginxNeededDialog() async {
    return showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('是否需要nginx'),
        content: const Text('是否需要nginx作为反向代理？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不需要'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('需要'),
          ),
        ],
      ),
    );
  }

  /// 显示守护进程nginx配置对话框
  Future<Map<String, dynamic>?> _showDaemonNginxConfigDialog(
    String framework,
    String projectName,
  ) async {
    final defaultServerName = _generateDefaultServerName(projectName);
    final serverNameController = TextEditingController(text: defaultServerName);
    final portController = TextEditingController(text: '80');
    bool enableSsl = false;
    final sslPortController = TextEditingController(text: '443');
    bool useSelfSignedCert = false;
    String? certPath;
    String? keyPath;
    final upstreamPortsController = TextEditingController(
      text: framework == 'easyswoole'
          ? '9501'
          : framework == 'webman'
          ? '8787'
          : framework == 'hyperf'
          ? '9501,9502'
          : '',
    );
    final rootController = TextEditingController();
    final customRulesController = TextEditingController();

    return showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('配置nginx'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // server_name
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: TextField(
                      controller: serverNameController,
                      decoration: const InputDecoration(
                        labelText: 'server_name',
                        hintText: '例如: example.localhost',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 端口
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '默认: 80',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // SSL开关
                  SwitchListTile(
                    title: const Text('启用SSL'),
                    value: enableSsl,
                    onChanged: (value) => setState(() => enableSsl = value),
                  ),
                  if (enableSsl) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: sslPortController,
                      decoration: const InputDecoration(
                        labelText: 'SSL端口',
                        hintText: '默认: 443',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('使用自签证书'),
                      value: useSelfSignedCert,
                      onChanged: (value) =>
                          setState(() => useSelfSignedCert = value),
                    ),
                    if (!useSelfSignedCert) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // TODO: 选择证书文件
                        },
                        icon: const Icon(Icons.file_upload),
                        label: const Text('选择证书文件'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // TODO: 选择私钥文件
                        },
                        icon: const Icon(Icons.file_upload),
                        label: const Text('选择私钥文件'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  // upstream端口
                  TextField(
                    controller: upstreamPortsController,
                    decoration: const InputDecoration(
                      labelText: 'upstream端口',
                      hintText: '用半角逗号分隔，例如: 9501,9502',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // root路径
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rootController,
                          decoration: const InputDecoration(
                            labelText: 'root路径',
                            hintText: '项目根目录路径',
                            border: OutlineInputBorder(),
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform
                              .getDirectoryPath();
                          if (result != null) {
                            setState(() {
                              rootController.text = result;
                            });
                          }
                        },
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 自定义规则
                  TextField(
                    controller: customRulesController,
                    decoration: const InputDecoration(
                      labelText: '自定义server{}块规则',
                      hintText: '可选，留空则不添加',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final upstreamPorts = upstreamPortsController.text.trim();
                if (upstreamPorts.isEmpty) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: 'upstream端口不能为空',
                  );
                  return;
                }

                final serverName = serverNameController.text.trim();
                final port = portController.text.trim();
                final sslPort = sslPortController.text.trim();
                final root = rootController.text.trim();

                // 验证root路径
                if (root.isEmpty) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: 'root路径不能为空',
                  );
                  return;
                }

                // 验证server_name和port
                final validationError = _validateServerNameAndPort(
                  serverName,
                  port,
                  enableSsl,
                  sslPort,
                );
                if (validationError != null) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: validationError,
                  );
                  return;
                }

                Navigator.of(context).pop({
                  'serverName': serverName,
                  'port': port,
                  'enableSsl': enableSsl,
                  'sslPort': sslPort,
                  'useSelfSignedCert': useSelfSignedCert,
                  'certPath': certPath,
                  'keyPath': keyPath,
                  'upstreamPorts': upstreamPorts,
                  'root': root,
                  'customRules': customRulesController.text.trim(),
                });
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取已安装的PHP版本列表
  Future<List<Software>> _getInstalledPhpVersions() async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return [];

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return [];

    final List<Software> installedPhp = [];
    final phpDir = Directory('$storagePath/php');

    if (await phpDir.exists()) {
      await for (final entity in phpDir.list()) {
        if (entity is Directory) {
          final phpId = path.basename(entity.path);
          // 在软件源中查找对应的PHP软件
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
            installedPhp.add(php);
          }
        }
      }
    }

    return installedPhp;
  }

  /// 获取默认PHP版本
  Future<String?> _getDefaultPhpVersion() async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
    final phpBatFile = File(phpBatPath);

    if (!await phpBatFile.exists()) return null;

    try {
      final content = await phpBatFile.readAsString();
      // 匹配第二行的第一个""包裹的值
      final lines = content.split('\n');
      if (lines.length < 2) return null;

      final secondLine = lines[1];
      final match = RegExp(r'"([^"]+)"').firstMatch(secondLine);
      if (match != null) {
        final phpExePath = match.group(1);
        if (phpExePath == null) return null;
        // 从路径中提取PHP版本ID
        // 例如: E:\storage\php\php81\php.exe -> php81
        final phpExeDir = path.dirname(phpExePath);
        return path.basename(phpExeDir);
      }
    } catch (e) {
      // 忽略错误
    }

    return null;
  }

  /// 显示PHP版本选择对话框
  Future<String?> _showPhpVersionDialog() async {
    final installedPhp = await _getInstalledPhpVersions();
    if (installedPhp.isEmpty) {
      await NotificationService.showError(title: '错误', message: '没有已安装的PHP版本');
      return null;
    }

    final defaultPhpId = await _getDefaultPhpVersion();
    String? selectedPhpId = defaultPhpId;

    return showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('选择PHP版本'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (defaultPhpId != null)
                  RadioListTile<String>(
                    title: const Text('默认版本'),
                    value: defaultPhpId,
                    groupValue: selectedPhpId,
                    onChanged: (value) => setState(() => selectedPhpId = value),
                  ),
                ...installedPhp.map(
                  (php) => RadioListTile<String>(
                    title: Text(php.name),
                    value: php.id,
                    groupValue: selectedPhpId,
                    onChanged: (value) => setState(() => selectedPhpId = value),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedPhpId != null) {
                  Navigator.of(context).pop(selectedPhpId);
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取已安装的数据库软件列表
  Future<List<Software>> _getInstalledDatabases() async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return [];

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return [];

    final List<Software> installedDatabases = [];
    final databasesDir = Directory('$storagePath/databases');

    if (await databasesDir.exists()) {
      await for (final entity in databasesDir.list()) {
        if (entity is Directory) {
          final dbId = path.basename(entity.path);
          // 在软件源的databases分类中查找
          final db = softwareSource.databases.firstWhere(
            (s) => s.id == dbId,
            orElse: () => Software(
              id: '',
              name: '',
              byte: 0,
              downloadURL: '',
              commands: [],
              attachments: [],
            ),
          );
          if (db.id.isNotEmpty) {
            installedDatabases.add(db);
          }
        }
      }
    }

    return installedDatabases;
  }

  /// 显示数据库选择对话框
  Future<List<String>?> _showDatabaseSelectionDialog() async {
    final installedDatabases = await _getInstalledDatabases();
    final selectedDatabases = <String>{};

    return showDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('选择相关软件'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: installedDatabases.isEmpty
                  ? [const Text('没有已安装的数据库软件')]
                  : [
                      ...installedDatabases.map(
                        (db) => CheckboxListTile(
                          title: Text(db.name),
                          value: selectedDatabases.contains(db.id),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                selectedDatabases.add(db.id);
                              } else {
                                selectedDatabases.remove(db.id);
                              }
                            });
                          },
                        ),
                      ),
                    ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(selectedDatabases.toList());
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示普通PHP项目nginx配置对话框
  Future<Map<String, dynamic>?> _showNormalPhpNginxConfigDialog(
    String projectName,
  ) async {
    final defaultServerName = _generateDefaultServerName(projectName);
    final serverNameController = TextEditingController(text: defaultServerName);
    final portController = TextEditingController(text: '80');
    bool enableSsl = false;
    final sslPortController = TextEditingController(text: '443');
    bool useSelfSignedCert = false;
    String? certPath;
    String? keyPath;
    final rootController = TextEditingController();
    String? selectedRewriteRule;

    // 伪静态规则选项
    const rewriteRules = [
      'codeigniter',
      'laravel',
      'symfony',
      'thinkphp',
      'yii',
    ];

    return showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('配置nginx'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // server_name
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: TextField(
                      controller: serverNameController,
                      decoration: const InputDecoration(
                        labelText: 'server_name',
                        hintText: '例如: example.localhost',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 端口
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '默认: 80',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // SSL开关
                  SwitchListTile(
                    title: const Text('启用SSL'),
                    value: enableSsl,
                    onChanged: (value) => setState(() => enableSsl = value),
                  ),
                  if (enableSsl) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: sslPortController,
                      decoration: const InputDecoration(
                        labelText: 'SSL端口',
                        hintText: '默认: 443',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('使用自签证书'),
                      value: useSelfSignedCert,
                      onChanged: (value) =>
                          setState(() => useSelfSignedCert = value),
                    ),
                    if (!useSelfSignedCert) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // TODO: 选择证书文件
                        },
                        icon: const Icon(Icons.file_upload),
                        label: const Text('选择证书文件'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // TODO: 选择私钥文件
                        },
                        icon: const Icon(Icons.file_upload),
                        label: const Text('选择私钥文件'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  // root路径
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rootController,
                          decoration: const InputDecoration(
                            labelText: 'root路径',
                            hintText: '项目根目录路径',
                            border: OutlineInputBorder(),
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform
                              .getDirectoryPath();
                          if (result != null) {
                            setState(() {
                              rootController.text = result;
                            });
                          }
                        },
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 伪静态规则
                  DropdownButtonFormField<String>(
                    value: selectedRewriteRule,
                    decoration: const InputDecoration(
                      labelText: '伪静态规则',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('无')),
                      ...rewriteRules.map(
                        (rule) =>
                            DropdownMenuItem(value: rule, child: Text(rule)),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => selectedRewriteRule = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final serverName = serverNameController.text.trim();
                final port = portController.text.trim();
                final sslPort = sslPortController.text.trim();
                final root = rootController.text.trim();

                // 验证root路径
                if (root.isEmpty) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: 'root路径不能为空',
                  );
                  return;
                }

                // 验证server_name和port
                final validationError = _validateServerNameAndPort(
                  serverName,
                  port,
                  enableSsl,
                  sslPort,
                );
                if (validationError != null) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: validationError,
                  );
                  return;
                }

                Navigator.of(context).pop({
                  'serverName': serverName,
                  'port': port,
                  'enableSsl': enableSsl,
                  'sslPort': sslPort,
                  'useSelfSignedCert': useSelfSignedCert,
                  'certPath': certPath,
                  'keyPath': keyPath,
                  'root': root,
                  'rewriteRule': selectedRewriteRule,
                });
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示静态项目nginx配置对话框
  Future<Map<String, dynamic>?> _showStaticNginxConfigDialog(
    String projectName,
  ) async {
    final defaultServerName = _generateDefaultServerName(projectName);
    final serverNameController = TextEditingController(text: defaultServerName);
    final portController = TextEditingController(text: '80');
    bool enableSsl = false;
    final sslPortController = TextEditingController(text: '443');
    bool useSelfSignedCert = false;
    String? certPath;
    String? keyPath;
    final rootController = TextEditingController();
    final customRulesController = TextEditingController();

    return showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('配置nginx'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // server_name
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: TextField(
                      controller: serverNameController,
                      decoration: const InputDecoration(
                        labelText: 'server_name',
                        hintText: '例如: example.localhost',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 端口
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '默认: 80',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // SSL开关
                  SwitchListTile(
                    title: const Text('启用SSL'),
                    value: enableSsl,
                    onChanged: (value) => setState(() => enableSsl = value),
                  ),
                  if (enableSsl) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: sslPortController,
                      decoration: const InputDecoration(
                        labelText: 'SSL端口',
                        hintText: '默认: 443',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('使用自签证书'),
                      value: useSelfSignedCert,
                      onChanged: (value) =>
                          setState(() => useSelfSignedCert = value),
                    ),
                    if (!useSelfSignedCert) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // TODO: 选择证书文件
                        },
                        icon: const Icon(Icons.file_upload),
                        label: const Text('选择证书文件'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // TODO: 选择私钥文件
                        },
                        icon: const Icon(Icons.file_upload),
                        label: const Text('选择私钥文件'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  // root路径
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rootController,
                          decoration: const InputDecoration(
                            labelText: 'root路径',
                            hintText: '项目根目录路径',
                            border: OutlineInputBorder(),
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform
                              .getDirectoryPath();
                          if (result != null) {
                            setState(() {
                              rootController.text = result;
                            });
                          }
                        },
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 自定义规则
                  TextField(
                    controller: customRulesController,
                    decoration: const InputDecoration(
                      labelText: '自定义server{}块规则',
                      hintText: '可选，留空则不添加',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final serverName = serverNameController.text.trim();
                final port = portController.text.trim();
                final sslPort = sslPortController.text.trim();
                final root = rootController.text.trim();

                // 验证root路径
                if (root.isEmpty) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: 'root路径不能为空',
                  );
                  return;
                }

                // 验证server_name和port
                final validationError = _validateServerNameAndPort(
                  serverName,
                  port,
                  enableSsl,
                  sslPort,
                );
                if (validationError != null) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: validationError,
                  );
                  return;
                }

                Navigator.of(context).pop({
                  'serverName': serverName,
                  'port': port,
                  'enableSsl': enableSsl,
                  'sslPort': sslPort,
                  'useSelfSignedCert': useSelfSignedCert,
                  'certPath': certPath,
                  'keyPath': keyPath,
                  'root': root,
                  'customRules': customRulesController.text.trim(),
                });
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 检查端口是否被占用
  Future<bool> _isPortInUse(int port) async {
    try {
      final result = await Process.run('netstat', ['-an'], runInShell: true);
      final output = result.stdout.toString();
      // 检查端口是否在监听状态
      return output.contains(':$port ') && output.contains('LISTENING');
    } catch (e) {
      return false;
    }
  }

  /// 获取可用的PHP端口
  Future<int> _getAvailablePhpPort(String phpVersionId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'php_port_$phpVersionId';
    int port = prefs.getInt(key) ?? 9000;
    port += 1;

    // 检查端口是否被占用，如果被占用则自增
    while (await _isPortInUse(port)) {
      port++;
    }

    // 保存端口
    await prefs.setInt(key, port);
    return port;
  }

  /// 确保PHP配置文件存在
  Future<void> _ensurePhpConfigExists(
    String nginxDir,
    String phpVersionId,
  ) async {
    final phpConfPath = path.join(
      nginxDir,
      'conf',
      'php',
      '$phpVersionId.conf',
    );
    final phpConfFile = File(phpConfPath);

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
        // 获取可用端口
        final port = await _getAvailablePhpPort(phpVersionId);
        // 替换第三行的#--#为端口
        final lines = content.split('\n');
        if (lines.length >= 3) {
          lines[2] = lines[2].replaceAll('#--#', port.toString());
        }
        await phpConfFile.writeAsString(lines.join('\n'));
      }
    } else {
      // 如果文件已存在，检查端口配置
      final content = await phpConfFile.readAsString();
      final portMatch = RegExp(r'listen\s+(\d+)').firstMatch(content);
      if (portMatch == null) {
        // 没有端口配置，需要添加
        final port = await _getAvailablePhpPort(phpVersionId);
        final lines = content.split('\n');
        if (lines.length >= 3) {
          lines[2] = lines[2].replaceAll('#--#', port.toString());
        }
        await phpConfFile.writeAsString(lines.join('\n'));
      }
    }
  }

  /// 生成SSL自签证书
  /// 显示证书生成配置对话框
  Future<Map<String, dynamic>?> _showCertConfigDialog() async {
    String selectedKeyType = 'RSA2048';
    final countryController = TextEditingController(text: 'CN');
    final stateController = TextEditingController(text: 'Beijing');
    final cityController = TextEditingController(text: 'Beijing');
    final organizationController = TextEditingController(text: 'env4php');
    final daysController = TextEditingController(text: '365');

    return showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('配置自签证书'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 密钥类型
                  DropdownButtonFormField<String>(
                    value: selectedKeyType,
                    decoration: const InputDecoration(
                      labelText: '密钥类型',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'EC256', child: Text('EC256')),
                      DropdownMenuItem(value: 'EC384', child: Text('EC384')),
                      DropdownMenuItem(
                        value: 'RSA2048',
                        child: Text('RSA2048'),
                      ),
                      DropdownMenuItem(
                        value: 'RSA4096',
                        child: Text('RSA4096'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedKeyType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // 地区
                  TextField(
                    controller: countryController,
                    decoration: const InputDecoration(
                      labelText: '地区（C）',
                      hintText: '例如: CN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 州/省
                  TextField(
                    controller: stateController,
                    decoration: const InputDecoration(
                      labelText: '州/省（ST）',
                      hintText: '例如: Beijing',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 地市
                  TextField(
                    controller: cityController,
                    decoration: const InputDecoration(
                      labelText: '地市（L）',
                      hintText: '例如: Beijing',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 组织名称
                  TextField(
                    controller: organizationController,
                    decoration: const InputDecoration(
                      labelText: '组织名称（O）',
                      hintText: '例如: env4php',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 有效期
                  TextField(
                    controller: daysController,
                    decoration: const InputDecoration(
                      labelText: '有效期（天）',
                      hintText: '例如: 365',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final days = int.tryParse(daysController.text.trim());
                if (days == null || days <= 0) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: '有效期必须是大于0的数字',
                  );
                  return;
                }

                // 验证必填字段
                final country = countryController.text.trim();
                final state = stateController.text.trim();
                final city = cityController.text.trim();
                final organization = organizationController.text.trim();

                if (country.isEmpty ||
                    state.isEmpty ||
                    city.isEmpty ||
                    organization.isEmpty) {
                  await NotificationService.showError(
                    title: '验证失败',
                    message: '所有字段都不能为空',
                  );
                  return;
                }

                if (mounted) {
                  Navigator.of(context).pop({
                    'keyType': selectedKeyType,
                    'country': country,
                    'state': state,
                    'city': city,
                    'organization': organization,
                    'days': days,
                  });
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取openssl可执行文件路径
  String _getOpensslPath() {
    final executablePath = Platform.resolvedExecutable;
    final executableDir = path.dirname(executablePath);
    return path.join(executableDir, 'assets', 'openssl', 'openssl-3.0.18.exe');
  }

  /// 生成自签证书
  Future<bool> _generateSelfSignedCert(
    String certPath,
    String keyPath, {
    String? keyType,
    String? country,
    String? state,
    String? city,
    String? organization,
    int? days,
  }) async {
    try {
      // 如果参数为空，显示配置对话框
      if (keyType == null ||
          country == null ||
          state == null ||
          city == null ||
          organization == null ||
          days == null) {
        final config = await _showCertConfigDialog();
        if (config == null) {
          return false; // 用户取消
        }
        keyType = config['keyType'] as String;
        country = config['country'] as String;
        state = config['state'] as String;
        city = config['city'] as String;
        organization = config['organization'] as String;
        days = config['days'] as int;
      }

      // 获取openssl路径
      final opensslPath = _getOpensslPath();
      final opensslFile = File(opensslPath);
      if (!await opensslFile.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '找不到openssl可执行文件: $opensslPath',
        );
        return false;
      }

      // 构建主题名称
      final subject =
          '/C=$country/ST=$state/L=$city/O=$organization/CN=localhost';

      // 根据密钥类型生成证书
      if (keyType == 'EC256' || keyType == 'EC384') {
        // EC密钥需要分两步：先生成私钥，再生成证书
        final curveName = keyType == 'EC256' ? 'prime256v1' : 'secp384r1';

        // 第一步：生成EC私钥
        final genKeyResult = await Process.run(opensslPath, [
          'ecparam',
          '-name',
          curveName,
          '-genkey',
          '-out',
          keyPath,
        ], runInShell: true);
        if (genKeyResult.exitCode != 0) {
          await NotificationService.showError(
            title: '错误',
            message: '生成EC私钥失败: ${genKeyResult.stderr}',
          );
          return false;
        }

        // 第二步：生成自签证书
        final certResult = await Process.run(opensslPath, [
          'req',
          '-x509',
          '-new',
          '-key',
          keyPath,
          '-out',
          certPath,
          '-days',
          days.toString(),
          '-subj',
          subject,
        ], runInShell: true);

        if (certResult.exitCode != 0) {
          await NotificationService.showError(
            title: '错误',
            message: '生成证书失败: ${certResult.stderr}',
          );
          return false;
        }
      } else {
        // RSA密钥直接生成
        final keySize = keyType == 'RSA2048' ? '2048' : '4096';
        final result = await Process.run(opensslPath, [
          'req',
          '-x509',
          '-newkey',
          'rsa:$keySize',
          '-keyout',
          keyPath,
          '-out',
          certPath,
          '-days',
          days.toString(),
          '-nodes',
          '-subj',
          subject,
        ], runInShell: true);
        if (result.exitCode != 0) {
          await NotificationService.showError(
            title: '错误',
            message: '生成证书失败: ${result.stderr}',
          );
          return false;
        }
      }

      return true;
    } catch (e) {
      await NotificationService.showError(
        title: '错误',
        message: '生成证书时发生异常: $e',
      );
      return false;
    }
  }

  /// 创建守护进程PHP项目（需要nginx）
  Future<void> _createDaemonPhpProjectWithNginx(
    String projectName,
    String framework,
    String startCommand,
    Map<String, dynamic> nginxConfig,
    String phpVersionId,
    List<String> databases,
  ) async {
    try {
      final nginxDir = await _getNginxDirectory();
      if (nginxDir == null) {
        await NotificationService.showError(title: '错误', message: 'nginx未安装');
        return;
      }

      // 准备nginx项目环境
      final env = await NginxProjectHelper.prepareNginxProjectEnvironment(
        projectName,
        nginxDir,
      );
      if (env == null) return;

      final lines = env.lines;

      // 修改端口
      NginxProjectHelper.updatePort(lines, nginxConfig['port'] as String);

      // 处理SSL
      final sslSuccess = await NginxProjectHelper.handleSslConfig(
        lines,
        nginxConfig,
        projectName,
        env.servsDir,
        (certPath, keyPath) => _generateSelfSignedCert(certPath, keyPath),
      );
      if (!sslSuccess) return;

      // 修改server_name
      NginxProjectHelper.updateServerName(
        lines,
        nginxConfig['serverName'] as String? ?? '',
      );

      // 修改root路径
      NginxProjectHelper.updateRootPath(
        lines,
        nginxConfig['root'] as String? ?? '',
      );

      // 修改项目名称行
      NginxProjectHelper.updateProjectNameLines(lines, projectName);

      // 确保PHP配置文件存在
      await _ensurePhpConfigExists(nginxDir, phpVersionId);

      // 修改PHP include行
      NginxProjectHelper.updatePhpInclude(lines, phpVersionId);

      // 创建subconf文件
      await NginxProjectHelper.createDaemonSubconf(
        projectName,
        framework,
        nginxConfig,
        nginxDir,
        env.servsDir,
      );

      // 修改include conf/preconf行
      NginxProjectHelper.updatePreconfInclude(lines, projectName);

      // 添加数据库配置
      NginxProjectHelper.addDatabaseConfig(lines, databases);

      // 完成项目创建
      final serverName = nginxConfig['serverName'] as String? ?? '';
      await NginxProjectHelper.finalizeProjectCreation(
        nginxDir,
        env.projectConfFile,
        lines,
        projectName,
        serverName,
        _checkNginxConfig,
        _showNginxConfigErrorDialog,
        _isNginxRunning,
        _reloadNginx,
      );
    } catch (e) {
      await NotificationService.showError(title: '创建失败', message: '创建项目失败: $e');
    }
  }

  /// 创建守护进程PHP项目（不需要nginx）
  Future<void> _createDaemonPhpProjectWithoutNginx(
    String projectName,
    String startCommand,
    String phpVersionId,
    List<String> databases,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) {
        await NotificationService.showError(title: '错误', message: '存储目录未设置');
        return;
      }

      // 1. 在shared_preferences中新建项目块
      final projectKey = 'project_$projectName';
      final createdAtKey = 'project_${projectName}_created_at';
      final projectData = <String, dynamic>{
        'name': projectName,
        'command': startCommand,
        'phpVersion': phpVersionId,
        'databases': databases,
      };
      await prefs.setString(projectKey, projectData.toString());
      // 保存创建时间
      await prefs.setString(createdAtKey, DateTime.now().toIso8601String());

      // 2. 替换启动命令中的php
      String finalCommand = startCommand;
      if (phpVersionId == 'default' || phpVersionId.isEmpty) {
        // 使用默认版本
        final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
        final phpBatFile = File(phpBatPath);
        if (await phpBatFile.exists()) {
          final batContent = await phpBatFile.readAsString();
          final lines = batContent.split('\n');
          if (lines.length >= 2) {
            final match = RegExp(r'"([^"]+)"').firstMatch(lines[1]);
            if (match != null) {
              final phpExePath = match.group(1);
              finalCommand = startCommand.replaceFirst(
                RegExp(r'^php\s+'),
                '$phpExePath ',
              );
            }
          }
        }
      } else {
        // 使用指定版本
        final phpDir = Directory(path.join(storagePath, 'php', phpVersionId));
        if (await phpDir.exists()) {
          final phpExePath = path.join(phpDir.path, 'php.exe');
          finalCommand = startCommand.replaceFirst(
            RegExp(r'^php\s+'),
            '$phpExePath ',
          );
        }
      }

      // 更新命令
      projectData['command'] = finalCommand;
      await prefs.setString(projectKey, projectData.toString());

      await NotificationService.showSuccess(
        title: '创建成功',
        message: '项目 $projectName 创建成功',
      );
    } catch (e) {
      await NotificationService.showError(title: '创建失败', message: '创建项目失败: $e');
    }
  }

  /// 创建普通PHP项目
  Future<void> _createNormalPhpProjectFiles(
    String projectName,
    Map<String, dynamic> nginxConfig,
    String phpVersionId,
    List<String> databases,
  ) async {
    try {
      final nginxDir = await _getNginxDirectory();
      if (nginxDir == null) {
        await NotificationService.showError(title: '错误', message: 'nginx未安装');
        return;
      }

      // 准备nginx项目环境
      final env = await NginxProjectHelper.prepareNginxProjectEnvironment(
        projectName,
        nginxDir,
      );
      if (env == null) return;

      final lines = env.lines;

      // 修改端口
      NginxProjectHelper.updatePort(lines, nginxConfig['port'] as String);

      // 处理SSL
      final sslSuccess = await NginxProjectHelper.handleSslConfig(
        lines,
        nginxConfig,
        projectName,
        env.servsDir,
        (certPath, keyPath) => _generateSelfSignedCert(certPath, keyPath),
      );
      if (!sslSuccess) return;

      // 修改server_name
      NginxProjectHelper.updateServerName(
        lines,
        nginxConfig['serverName'] as String? ?? '',
      );

      // 修改root路径
      NginxProjectHelper.updateRootPath(
        lines,
        nginxConfig['root'] as String? ?? '',
      );

      // 修改项目名称行
      NginxProjectHelper.updateProjectNameLines(lines, projectName);

      // 确保PHP配置文件存在
      await _ensurePhpConfigExists(nginxDir, phpVersionId);

      // 修改PHP include行
      NginxProjectHelper.updatePhpInclude(lines, phpVersionId);

      // 创建subconf文件（伪静态规则）
      await NginxProjectHelper.createNormalPhpSubconf(
        projectName,
        nginxConfig['rewriteRule'] as String?,
        nginxDir,
        env.servsDir,
      );

      // 修改include conf/preconf行
      NginxProjectHelper.updatePreconfInclude(lines, projectName);

      // 添加数据库配置
      NginxProjectHelper.addDatabaseConfig(lines, databases);

      // 完成项目创建
      final serverName = nginxConfig['serverName'] as String? ?? '';
      await NginxProjectHelper.finalizeProjectCreation(
        nginxDir,
        env.projectConfFile,
        lines,
        projectName,
        serverName,
        _checkNginxConfig,
        _showNginxConfigErrorDialog,
        _isNginxRunning,
        _reloadNginx,
      );
    } catch (e) {
      await NotificationService.showError(title: '创建失败', message: '创建项目失败: $e');
    }
  }

  /// 创建静态项目
  Future<void> _createStaticProjectFiles(
    String projectName,
    Map<String, dynamic> nginxConfig,
    List<String> databases,
  ) async {
    try {
      final nginxDir = await _getNginxDirectory();
      if (nginxDir == null) {
        await NotificationService.showError(title: '错误', message: 'nginx未安装');
        return;
      }

      // 准备nginx项目环境
      final env = await NginxProjectHelper.prepareNginxProjectEnvironment(
        projectName,
        nginxDir,
      );
      if (env == null) return;

      final lines = env.lines;

      // 修改端口
      NginxProjectHelper.updatePort(lines, nginxConfig['port'] as String);

      // 处理SSL
      final sslSuccess = await NginxProjectHelper.handleSslConfig(
        lines,
        nginxConfig,
        projectName,
        env.servsDir,
        (certPath, keyPath) => _generateSelfSignedCert(certPath, keyPath),
      );
      if (!sslSuccess) return;

      // 修改server_name
      NginxProjectHelper.updateServerName(
        lines,
        nginxConfig['serverName'] as String? ?? '',
      );

      // 修改root路径
      NginxProjectHelper.updateRootPath(
        lines,
        nginxConfig['root'] as String? ?? '',
      );

      // 修改项目名称行
      NginxProjectHelper.updateProjectNameLines(lines, projectName);

      // 注释PHP include行（静态项目不需要PHP）
      NginxProjectHelper.commentPhpInclude(lines);

      // 创建subconf文件（自定义规则）
      await NginxProjectHelper.createStaticSubconf(
        projectName,
        nginxConfig['customRules'] as String?,
        env.servsDir,
      );

      // 修改include conf/preconf行
      NginxProjectHelper.updatePreconfInclude(lines, projectName);

      // 添加数据库配置
      NginxProjectHelper.addDatabaseConfig(lines, databases);

      // 完成项目创建
      final serverName = nginxConfig['serverName'] as String? ?? '';
      await NginxProjectHelper.finalizeProjectCreation(
        nginxDir,
        env.projectConfFile,
        lines,
        projectName,
        serverName,
        _checkNginxConfig,
        _showNginxConfigErrorDialog,
        _isNginxRunning,
        _reloadNginx,
      );
    } catch (e) {
      await NotificationService.showError(title: '创建失败', message: '创建项目失败: $e');
    }
  }

  /// 显示管理对话框
  Future<void> _showManageDialog(Software software) async {
    final softwareSource = await SoftwareSourceService.getSource();

    // 使用共享的菜单项构建逻辑
    final menuItems = await SoftwareMenuHelper.buildManageDialogItems(
      software,
      softwareSource: softwareSource,
      onAction: (action) => _handleMenuAction(action, software),
      context: context,
    );

    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text('管理 ${software.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: menuItems),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示安装对话框
  void _showInstallDialog(Software software) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text('安装 ${software.name}'),
        content: Text('确定要安装 ${software.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startInstall(software);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示卸载对话框
  void _showUninstallDialog(Software software) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text('卸载 ${software.name}'),
        content: const Text('确定要卸载此软件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: 实现卸载逻辑
              _loadInstalledServers();
              NotificationService.showSuccess(
                title: '卸载成功',
                message: '已卸载 ${software.name}',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }

  /// 开始安装软件
  Future<void> _startInstall(Software software) async {
    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) {
      await NotificationService.showError(title: '错误', message: '软件源未加载');
      return;
    }

    // 确定软件类别
    String category;
    if (softwareSource.servers.any((s) => s.id == software.id)) {
      category = 'servers';
    } else if (softwareSource.databases.any((s) => s.id == software.id)) {
      category = 'databases';
    } else if (softwareSource.php.any((s) => s.id == software.id)) {
      category = 'php';
    } else {
      category = 'tools';
    }

    // 导入安装服务
    try {
      final result = await InstallService.installSoftware(
        software,
        category,
        onProgress: (stage, progress, logMessage) {
          // 可以在这里显示进度，但控制台页面暂时不显示安装进度对话框
          if (kDebugMode) {
            print('安装进度: $stage - ${(progress * 100).toInt()}%');
            if (logMessage != null) {
              print('日志: $logMessage');
            }
          }
        },
      );

      final success = result.$1;
      final error = result.$2;

      if (success) {
        await NotificationService.showSuccess(
          title: '安装成功',
          message: '${software.name} 安装成功',
        );
        // 刷新已安装服务器列表
        await _loadInstalledServers();
      } else {
        await NotificationService.showError(
          title: '安装失败',
          message: error ?? '${software.name} 安装失败',
        );
      }
    } catch (e) {
      await NotificationService.showError(
        title: '安装失败',
        message: '安装 ${software.name} 时发生错误: $e',
      );
    }
  }
}
