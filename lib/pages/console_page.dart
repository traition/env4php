import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../models/software_model.dart';

/// 控制台页面
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

/// 项目信息模型
class _ProjectInfo {
  final String name; // server_name:port格式
  final String confFilePath; // 配置文件路径
  final String serverName; // server_name值
  final String ports; // 端口（多个用|分隔）

  _ProjectInfo({
    required this.name,
    required this.confFilePath,
    required this.serverName,
    required this.ports,
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('全部启动（功能待实现）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 全部停止服务器（占位函数）
  void _stopAllServers() {
    // TODO: 实现全部停止逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('全部停止（功能待实现）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 启动单个服务器（占位函数）
  void _startServer(Software server) {
    // TODO: 实现启动逻辑
    setState(() {
      _serverRunningStatus[server.id] = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('启动 ${server.name}（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 停止单个服务器（占位函数）
  void _stopServer(Software server) {
    // TODO: 实现停止逻辑
    setState(() {
      _serverRunningStatus[server.id] = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('停止 ${server.name}（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 重启单个服务器（占位函数）
  void _restartServer(Software server) {
    // TODO: 实现重启逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('重启 ${server.name}（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 构建服务器列表项
  Widget _buildServerItem(Software server, bool isRunning) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 服务器名称（只显示前15个字符）
              Expanded(
                child: Text(
                  server.name.length > 15
                      ? '${server.name.substring(0, 15)}...'
                      : server.name,
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
    );
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
          final projectInfos = _parseNginxConfig(content, entity.path);
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
  List<_ProjectInfo> _parseNginxConfig(String content, String filePath) {
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

      projects.add(
        _ProjectInfo(
          name: projectName,
          confFilePath: filePath,
          serverName: serverName,
          ports: portsStr,
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

    final nginxDir = await _getNginxDirectory();

    if (nginxDir == null) {
      if (mounted) {
        setState(() {
          _isNginxInstalled = false;
          _projects = [];
          _isLoadingProjects = false;
        });
      }
      return;
    }

    _isNginxInstalled = true;
    final projects = await _parseNginxConfigs(nginxDir);

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('启动 ${project.name}（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 停止项目（占位函数）
  void _stopProject(_ProjectInfo project) {
    setState(() {
      _projectRunningStatus[project.name] = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('停止 ${project.name}（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 重启项目（占位函数）
  void _restartProject(_ProjectInfo project) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('重启 ${project.name}（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 打开项目（占位函数）
  void _openProject(_ProjectInfo project) {
    // TODO: 实现打开项目逻辑（可能在浏览器中打开）
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('打开 ${project.name}（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 构建项目列表项
  Widget _buildProjectItem(_ProjectInfo project, bool isRunning) {
    // 项目名称只显示前15个字符
    final displayName = project.name.length > 15
        ? '${project.name.substring(0, 15)}...'
        : project.name;

    return Column(
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
    );
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
          onPressed: () {
            // TODO: 实现新建项目逻辑
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('新建项目（功能待实现）'),
                duration: Duration(seconds: 2),
              ),
            );
          },
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
                onPressed: () {
                  // TODO: 实现新建项目逻辑
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('新建项目（功能待实现）'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
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
}
