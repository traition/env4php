import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/install_service.dart';
import '../services/notification_service.dart';
import '../services/icon_service.dart';
import '../utils/software_menu_helper.dart';
import '../widgets/storage_path_dialog.dart';
import '../utils/software_helper.dart';
import '../services/storage_monitor_service.dart';
import '../utils/nginx_project_helper.dart';
import '../services/software_managers/software_manager.dart';
import '../services/software_managers/software_manager_factory.dart';

/// 软件管理页面
class SoftwareManagementPage extends StatefulWidget {
  const SoftwareManagementPage({super.key});

  @override
  State<SoftwareManagementPage> createState() => _SoftwareManagementPageState();
}

/// 日志查看器对话框
class LogViewerDialog extends StatefulWidget {
  final File logFile;

  const LogViewerDialog({super.key, required this.logFile});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  String _content = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogFile();
  }

  Future<void> _loadLogFile() async {
    try {
      final content = await widget.logFile.readAsString();
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _content = '无法读取文件: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'error.log',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _content,
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftwareManagementPageState extends State<SoftwareManagementPage> {
  SoftwareSource? _softwareSource;
  bool _isLoading = true;
  int _selectedTabIndex = 0; // 0: 已安装, 1: 服务器, 2: 数据库, 3: PHP, 4: 工具
  List<Software> _installedSoftware = [];
  // 独立的 Navigator Key，用于限制对话框只显示在当前页面
  final GlobalKey<NavigatorState> _pageNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
    
    // 注册存储目录变更监听器
    StorageMonitorService().addChangeListener(_onStorageChanged);
  }

  @override
  void dispose() {
    // 移除存储目录变更监听器
    StorageMonitorService().removeChangeListener(_onStorageChanged);
    super.dispose();
  }

  /// 存储目录变更回调
  void _onStorageChanged() {
    if (mounted) {
      // 重新刷新已安装软件列表
      _refreshInstalledSoftware();
    }
  }

  Future<void> _initialize() async {
    // 检查存储目录是否设置
    final isStorageSet = await ConfigService.isStoragePathSet();
    if (!isStorageSet) {
      // 显示设置对话框
      if (mounted) {
        final path = await showDialog<String>(
          context: context,
          useRootNavigator: false, // 不在根 Navigator 中显示，只在 Container 区域显示
          builder: (context) => const StoragePathDialog(),
        );

        if (path != null && path.isNotEmpty) {
          await ConfigService.setStoragePath(path);
          await ConfigService.initializeStorageDirectories(path);
          // 重新启动存储目录监控
          await StorageMonitorService().startMonitoring();
        } else {
          // 用户取消了设置，可以显示提示
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('请先设置存储目录才能使用软件管理功能')));
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }
      }
    } else {
      // 确保目录结构存在
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath != null) {
        await ConfigService.initializeStorageDirectories(storagePath);
      }
    }

    // 直接加载软件源（不再下载，下载已在应用启动时完成）
    final source = await SoftwareSourceService.getSource();

    if (mounted) {
      setState(() {
        _softwareSource = source;
        _isLoading = false;
      });
      if (source != null) {
        _refreshInstalledSoftware();
      }
    }
  }

  /// 刷新软件源
  Future<void> _refreshSoftwareSource() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // 显示刷新提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('正在刷新软件源...'),
              ],
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }

      // 尝试下载最新版本（10秒超时）
      final downloadSuccess = await SoftwareSourceService.downloadSource(
        timeout: const Duration(seconds: 10),
      );

      if (mounted) {
        if (downloadSuccess) {
          // 下载成功，重新加载软件源
          await _initialize();
          await NotificationService.showSuccess(
            title: '刷新成功',
            message: '软件源已更新到最新版本',
          );
        } else {
          // 下载失败，显示错误通知
          await NotificationService.showError(
            title: '刷新失败',
            message: '无法从服务器下载软件源。请检查网络连接，或修改软件源地址。',
          );
          // 重新加载（使用缓存）
          await _initialize();
        }
      }
    } catch (e) {
      if (mounted) {
        await NotificationService.showError(
          title: '刷新失败',
          message: '刷新软件源时发生错误: $e',
        );
        // 重新加载（使用缓存）
        await _initialize();
      }
    }
  }

  /// 修改软件源地址
  Future<void> _changeSourceURL() async {
    final currentURL = SoftwareSourceService.getSourceURL();
    final controller = TextEditingController(text: currentURL);

    final pageContext = _pageNavigatorKey.currentContext;
    if (pageContext == null) return;

    final newURL = await showDialog<String>(
      context: pageContext,
      useRootNavigator: false, // 只在当前页面的 Navigator 中显示
      builder: (context) => AlertDialog(
        title: const Text('修改软件源地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '软件源 URL',
            hintText: 'https://example.com/soft.json',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                Navigator.of(context).pop(url);
              }
            },
            child: const Text('确定'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop('https://conf.e4p.uxyz.fyi/soft.json');
            },
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );

    if (newURL != null && newURL.isNotEmpty) {
      SoftwareSourceService.setSourceURL(newURL);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('软件源地址已更新，请重新加载软件源'),
            backgroundColor: Colors.green,
          ),
        );
        // 重新加载软件源
        setState(() {
          _isLoading = true;
        });
        await _initialize();
      }
    }
  }

  /// 刷新已安装软件列表
  Future<void> _refreshInstalledSoftware() async {
    if (_softwareSource == null) return;

    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return;

    final List<Software> installed = [];

    // 检查所有类别的软件
    final categories = [
      ('servers', _softwareSource!.servers),
      ('databases', _softwareSource!.databases),
      ('php', _softwareSource!.php),
      ('tools', _softwareSource!.tools),
    ];

    for (final (category, softwareList) in categories) {
      for (final software in softwareList) {
        final dir = Directory('$storagePath/$category/${software.id}');
        if (await dir.exists()) {
          installed.add(software);
        }
      }
    }

    if (mounted) {
      setState(() {
        _installedSoftware = installed;
      });
    }
  }

  /// 获取当前显示的软件列表
  Future<List<Software>> _getCurrentSoftwareList() async {
    if (_softwareSource == null) return [];

    List<Software> list;
    switch (_selectedTabIndex) {
      case 0: // 已安装
        list = _installedSoftware;
        // 如果pgsql已安装，添加虚拟的pgAdmin4应用
        final isPgsqlInstalled = await SoftwareHelper.isPgsqlInstalled(
          softwareSource: _softwareSource,
          installedSoftware: _installedSoftware,
        );
        if (isPgsqlInstalled) {
          list = [...list, SoftwareHelper.createPgAdmin4Software()];
        }
        break;
      case 1: // 服务器
        list = _softwareSource!.servers;
        break;
      case 2: // 数据库
        list = _softwareSource!.databases;
        break;
      case 3: // PHP
        list = _softwareSource!.php;
        break;
      case 4: // 工具
        list = _softwareSource!.tools;
        // 如果pgsql已安装，添加虚拟的pgAdmin4应用
        final isPgsqlInstalled = await SoftwareHelper.isPgsqlInstalled(
          softwareSource: _softwareSource,
          installedSoftware: _installedSoftware,
        );
        if (isPgsqlInstalled) {
          list = [...list, SoftwareHelper.createPgAdmin4Software()];
        }
        break;
      default:
        return [];
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _pageNavigatorKey,
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => DefaultTabController(
            length: 5,
            initialIndex: _selectedTabIndex,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 软件源地址和设置（居右显示）
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        '软件源',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        SoftwareSourceService.getSourceURL(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshSoftwareSource,
                        tooltip: '刷新软件源',
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: _changeSourceURL,
                        tooltip: '软件源设置',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Tab 栏
                  TabBar(
                    isScrollable: true,
                    onTap: (index) {
                      setState(() {
                        _selectedTabIndex = index;
                      });
                    },
                    tabs: const [
                      Tab(text: '已安装'),
                      Tab(text: '服务器'),
                      Tab(text: '数据库'),
                      Tab(text: 'PHP'),
                      Tab(text: '工具'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 软件列表
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _softwareSource == null
                        ? Center(
                            child: Text(
                              '无法加载软件源',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                          )
                        : _buildSoftwareList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSoftwareList() {
    return FutureBuilder<List<Software>>(
      future: _getCurrentSoftwareList(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final softwareList = snapshot.data!;

        if (softwareList.isEmpty) {
          return Center(
            child: Text(
              _selectedTabIndex == 0 ? '暂无已安装的软件' : '该分类下暂无软件',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: softwareList.length,
          itemBuilder: (context, index) {
            final software = softwareList[index];
            return _buildSoftwareCard(software);
          },
        );
      },
    );
  }

  // 已移除：_getSoftwareCategory - 已由 IconService 统一处理

  /// 获取图标文件路径
  /// 获取图标路径，使用 IconService 统一处理
  Future<String?> _getIconPath(Software software) async {
    return await IconService.getIconPath(
      software,
      softwareSource: _softwareSource,
    );
  }

  Widget _buildSoftwareCard(Software software) {
    // 检查是否为pgAdmin4
    final isPgAdmin4 = software.id == 'pgadmin4';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: FutureBuilder<String?>(
        future: _getIconPath(software),
        builder: (context, snapshot) {
          Widget? leading;
          if (snapshot.hasData && snapshot.data != null) {
            // 图标文件存在，显示图标，添加边距
            leading = Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.file(
                File(snapshot.data!),
                width: 48,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // 图标加载失败，不显示
                  return const SizedBox.shrink();
                },
              ),
            );
          }

          // 判断是否已安装
          // 对于pgAdmin4，直接判断pgsql是否安装
          // 对于其他软件，根据tab页和已安装列表判断
          return FutureBuilder<bool>(
            future: isPgAdmin4
                ? SoftwareHelper.isPgsqlInstalled(
                    softwareSource: _softwareSource,
                    installedSoftware: _installedSoftware,
                  )
                : Future.value(
                    _selectedTabIndex == 0 ||
                        _installedSoftware.any((s) => s.id == software.id),
                  ),
            builder: (context, isInstalledSnapshot) {
              final isInstalled = isInstalledSnapshot.data ?? false;

              return ListTile(
                leading: leading,
                title: Text(software.name),
                subtitle: _selectedTabIndex == 0
                    ? null // 已安装tab页不显示介绍
                    : (software.description != null
                          ? Text(software.description!)
                          : null),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 已安装tab页不显示大小
                    if (software.byte > 0 && _selectedTabIndex != 0)
                      Text(
                        _formatBytes(software.byte),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (software.byte > 0 && _selectedTabIndex != 0)
                      const SizedBox(width: 16),
                    isInstalled
                        ? (isPgAdmin4
                              ? const Text('已安装')
                              : ElevatedButton(
                                  onPressed: () {
                                    // 管理按钮
                                    _showManageDialog(software);
                                  },
                                  child: const Text('管理'),
                                ))
                        : ElevatedButton(
                            onPressed: () {
                              // 安装按钮
                              _showInstallDialog(software);
                            },
                            child: const Text('安装'),
                          ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showInstallDialog(Software software) {
    final pageContext = _pageNavigatorKey.currentContext;
    if (pageContext == null) return;

    showDialog(
      context: pageContext,
      useRootNavigator: false, // 只在当前页面的 Navigator 中显示
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

  /// 打开软件目录
  /// 获取软件目录路径
  Future<String?> _getSoftwareDirectory(Software software) async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return null;

    // 确定软件类别
    String category;
    if (_softwareSource == null) return null;

    if (_softwareSource!.servers.any((s) => s.id == software.id)) {
      category = 'servers';
    } else if (_softwareSource!.databases.any((s) => s.id == software.id)) {
      category = 'databases';
    } else if (_softwareSource!.php.any((s) => s.id == software.id)) {
      category = 'php';
    } else {
      category = 'tools';
    }

    final softwareDir = Directory('$storagePath/$category/${software.id}');
    if (!await softwareDir.exists()) return null;

    return softwareDir.path;
  }

  /// 编辑 mysql.ini
  Future<void> _editMysqlIni(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    final configFile = File(path.join(softwareDir, 'mysql.ini'));
    if (!await configFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mysql.ini 文件不存在: ${configFile.path}')),
      );
      return;
    }

    // 使用 PowerShell 执行 explorer 命令打开文件
    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      // PowerShell 命令：explorer "文件路径"
      final command = 'explorer "$filePath"';

      // 使用 PowerShell 执行 explorer 命令
      final result = await Process.run('powershell', [
        '-Command',
        command,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $e\n文件路径: ${configFile.path}')),
      );
    }
  }

  /// 编辑 mongod.cfg
  Future<void> _editMongodbConfig(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    final configFile = File(path.join(softwareDir, 'mongod.cfg'));
    if (!await configFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mongod.cfg 文件不存在: ${configFile.path}')),
      );
      return;
    }

    // 使用 PowerShell 执行 explorer 命令打开文件
    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      // PowerShell 命令：explorer "文件路径"
      final command = 'explorer "$filePath"';

      // 使用 PowerShell 执行 explorer 命令
      final result = await Process.run('powershell', [
        '-Command',
        command,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $e\n文件路径: ${configFile.path}')),
      );
    }
  }

  /// 编辑 rudis-server.properties
  Future<void> _editRudisConfig(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    final configFile = File(path.join(softwareDir, 'rudis-server.properties'));
    if (!await configFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('rudis-server.properties 文件不存在: ${configFile.path}'),
        ),
      );
      return;
    }

    // 使用 PowerShell 执行 explorer 命令打开文件
    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      // PowerShell 命令：explorer "文件路径"
      final command = 'explorer "$filePath"';

      // 使用 PowerShell 执行 explorer 命令
      final result = await Process.run('powershell', [
        '-Command',
        command,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $e\n文件路径: ${configFile.path}')),
      );
    }
  }

  /// 编辑 redis.windows.conf
  Future<void> _editRedisConfig(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    final configFile = File(path.join(softwareDir, 'redis.windows.conf'));
    if (!await configFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('redis.windows.conf 文件不存在: ${configFile.path}')),
      );
      return;
    }

    // 使用 PowerShell 执行 explorer 命令打开文件
    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      // PowerShell 命令：explorer "文件路径"
      final command = 'explorer "$filePath"';

      // 使用 PowerShell 执行 explorer 命令
      final result = await Process.run('powershell', [
        '-Command',
        command,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $e\n文件路径: ${configFile.path}')),
      );
    }
  }

  /// 设为php-cli版本（占位函数，后续实现）
  void _setPhpCliVersion(Software software) {
    // TODO: 实现设为php-cli版本的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('设为php-cli版本（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 安装扩展（占位函数，后续实现）
  void _installPhpExtension(Software software) {
    // TODO: 实现安装扩展的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('安装扩展（功能待实现）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 编辑 php.ini
  Future<void> _editPhpIni(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    final configFile = File(path.join(softwareDir, 'php.ini'));
    if (!await configFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('php.ini 文件不存在: ${configFile.path}')),
      );
      return;
    }

    // 使用 PowerShell 执行 explorer 命令打开文件
    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      // PowerShell 命令：explorer "文件路径"
      final command = 'explorer "$filePath"';

      // 使用 PowerShell 执行 explorer 命令
      final result = await Process.run('powershell', [
        '-Command',
        command,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $e\n文件路径: ${configFile.path}')),
      );
    }
  }

  /// 编辑 nginx.conf
  Future<void> _editNginxConfig(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    final configFile = File(path.join(softwareDir, 'conf', 'nginx.conf'));
    if (!await configFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('nginx.conf 文件不存在: ${configFile.path}')),
      );
      return;
    }

    // 使用 PowerShell 执行 explorer 命令打开文件
    try {
      final filePath = configFile.path.replaceAll('/', '\\');
      // PowerShell 命令：explorer "文件路径"
      final command = 'explorer "$filePath"';
      // 使用 PowerShell 执行 explorer 命令
      final result = await Process.run('powershell', [
        '-Command',
        command,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('打开文件失败: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $e\n文件路径: ${configFile.path}')),
      );
    }
  }

  /// 查看 error.log
  Future<void> _viewErrorLog(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    final logFile = File(path.join(softwareDir, 'logs', 'error.log'));
    if (!await logFile.exists()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('error.log 文件不存在')));
      return;
    }

    // 显示文本查看器对话框
    final pageContext = _pageNavigatorKey.currentContext;
    if (pageContext == null) return;

    showDialog(
      context: pageContext,
      useRootNavigator: false, // 只在当前页面的 Navigator 中显示
      builder: (context) => LogViewerDialog(logFile: logFile),
    );
  }

  Future<void> _openSoftwareDirectory(Software software) async {
    final softwareDir = await _getSoftwareDirectory(software);
    if (softwareDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取软件目录')));
      return;
    }

    // 在 Windows 上使用 explorer 打开目录
    try {
      // 验证目录是否存在
      final dir = Directory(softwareDir);
      if (!await dir.exists()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('目录不存在: $softwareDir')));
        return;
      }
      // 使用 explorer 打开目录，将路径中的 / 替换为 \
      final dirPath = softwareDir.replaceAll('/', '\\');

      final result = await Process.run('explorer', [dirPath], runInShell: true);
      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('打开目录失败: $e');
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开目录: $e\n目录路径: $softwareDir')));
    }
  }

  /// 开始安装软件
  Future<void> _startInstall(Software software) async {
    // 确定软件类别
    String category;
    if (_softwareSource == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('软件源未加载')));
      return;
    }

    if (_softwareSource!.servers.any((s) => s.id == software.id)) {
      category = 'servers';
    } else if (_softwareSource!.databases.any((s) => s.id == software.id)) {
      category = 'databases';
    } else if (_softwareSource!.php.any((s) => s.id == software.id)) {
      category = 'php';
    } else {
      category = 'tools';
    }

    // 显示安装进度对话框
    final pageContext = _pageNavigatorKey.currentContext;
    if (pageContext == null) return;

    showDialog(
      context: pageContext,
      useRootNavigator: false, // 只在当前页面的 Navigator 中显示
      barrierDismissible: false,
      builder: (context) => _InstallProgressDialog(
        software: software,
        category: category,
        pageNavigatorKey: _pageNavigatorKey,
        onComplete: (success, error) {
          // 不自动关闭对话框，让用户手动关闭
          if (success) {
            NotificationService.showSuccess(
              title: '安装成功',
              message: '${software.name} 安装成功',
            );
            // 刷新已安装软件列表
            _refreshInstalledSoftware();
          } else {
            NotificationService.showError(
              title: '安装失败',
              message: error ?? '${software.name} 安装失败',
            );
          }
        },
      ),
    );
  }

  void _showManageDialog(Software software) async {
    final pageContext = _pageNavigatorKey.currentContext;
    if (pageContext == null) return;

    // 使用共享的菜单项构建逻辑
    final menuItems = await SoftwareMenuHelper.buildManageDialogItems(
      software,
      softwareSource: _softwareSource,
      onAction: (action) => _handleMenuAction(action, software),
      context: pageContext,
    );

    showDialog(
      context: pageContext,
      useRootNavigator: false, // 只在当前页面的 Navigator 中显示
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

  /// 处理菜单操作
  void _handleMenuAction(SoftwareMenuAction action, Software software) {
    switch (action) {
      case SoftwareMenuAction.editNginxConfig:
        _editNginxConfig(software);
        break;
      case SoftwareMenuAction.viewLog:
        _viewErrorLog(software);
        break;
      case SoftwareMenuAction.editRedisConfig:
        _editRedisConfig(software);
        break;
      case SoftwareMenuAction.editRudisConfig:
        _editRudisConfig(software);
        break;
      case SoftwareMenuAction.editMysqlIni:
        _editMysqlIni(software);
        break;
      case SoftwareMenuAction.editMongodbConfig:
        _editMongodbConfig(software);
        break;
      case SoftwareMenuAction.setPhpCliVersion:
        _setPhpCliVersion(software);
        break;
      case SoftwareMenuAction.editPhpIni:
        _editPhpIni(software);
        break;
      case SoftwareMenuAction.installPhpExtension:
        _installPhpExtension(software);
        break;
      case SoftwareMenuAction.openDirectory:
        _openSoftwareDirectory(software);
        break;
      case SoftwareMenuAction.uninstall:
        _showUninstallDialog(software);
        break;
      default:
        break;
    }
  }

  void _showUninstallDialog(Software software) {
    final pageContext = _pageNavigatorKey.currentContext;
    if (pageContext == null) return;

    showDialog(
      context: pageContext,
      useRootNavigator: false, // 只在当前页面的 Navigator 中显示
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
              _uninstallSoftware(software);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }

  /// 卸载软件
  Future<void> _uninstallSoftware(Software software) async {
    try {
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) {
        await NotificationService.showError(
          title: '错误',
          message: '存储目录未设置',
        );
        return;
      }

      final cate4 = software.cate4?.toLowerCase() ?? '';
      final category = _getSoftwareCategory(software);

      // 根据软件类型执行不同的卸载逻辑
      if (cate4 == 'nginx') {
        await _uninstallNginx(software, storagePath);
      } else if (category == 'php') {
        await _uninstallPhp(software, storagePath);
      } else if (category == 'databases') {
        await _uninstallDatabase(software, storagePath);
      } else if (cate4 == 'mysql' || cate4 == 'pgsql' || cate4 == 'mongodb') {
        await _uninstallServiceDatabase(software, storagePath, cate4);
      } else if (cate4 == 'redis' || cate4 == 'rudis') {
        await _uninstallRedisRudis(software, storagePath);
      } else if (cate4 == 'composer') {
        await _uninstallComposer(software, storagePath);
      } else if (cate4 == 'phpmyadmin') {
        await _uninstallPhpmyadmin(software, storagePath);
      } else if (cate4 == 'dbeaver') {
        await _uninstallDbeaver(software, storagePath);
      } else if (cate4 == 'tiny_rdm') {
        await _uninstallTinyRdm(software, storagePath);
      } else if (cate4 == 'mongodb_compass') {
        await _uninstallMongodbCompass(software, storagePath);
      } else if (cate4 == 'heidisql') {
        await _uninstallHeidisql(software, storagePath);
      } else {
        // 默认卸载逻辑：直接删除目录
        await _uninstallDefault(software, storagePath, category);
      }

      // 刷新已安装软件列表
      await _refreshInstalledSoftware();
    } catch (e) {
      await NotificationService.showError(
        title: '卸载失败',
        message: '卸载 ${software.name} 时发生错误: $e',
      );
    }
  }

  /// 获取软件类别
  String _getSoftwareCategory(Software software) {
    if (_softwareSource == null) return '';
    if (_softwareSource!.servers.contains(software)) return 'servers';
    if (_softwareSource!.databases.contains(software)) return 'databases';
    if (_softwareSource!.php.contains(software)) return 'php';
    if (_softwareSource!.tools.contains(software)) return 'tools';
    return '';
  }

  /// 获取用户主目录的 AppData\Roaming 路径
  String _getUserRoamingPath() {
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    if (userProfile.isEmpty) {
      return '';
    }
    return path.join(userProfile, 'AppData', 'Roaming');
  }

  /// 静默停止服务（用于卸载时）
  Future<void> _stopServerSilently(Software server) async {
    try {
      SoftwareManager? manager;

      // PHP 特殊处理：检查是否为 PHP
      final isPhp = _softwareSource?.php.any((s) => s.id == server.id) ?? false;
      if (isPhp) {
        manager = SoftwareManagerFactory.getManager(
          Software(
            id: server.id,
            name: server.name,
            byte: server.byte,
            downloadURL: server.downloadURL,
            commands: server.commands,
            attachments: server.attachments,
            cate4: 'php', // 临时设置 cate4 为 php
          ),
        );
      } else {
        // 其他服务器使用 cate4 获取管理器
        manager = SoftwareManagerFactory.getManager(server);
      }

      if (manager == null) {
        return;
      }

      // 调用管理器的静默停止方法
      await manager.stopSilently(server);
    } catch (e) {
      if (kDebugMode) {
        print('[卸载] 停止 ${server.name} 时发生错误: $e');
      }
    }
  }

  /// 卸载 nginx
  Future<void> _uninstallNginx(Software software, String storagePath) async {
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
    await _stopServerSilently(software);

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
  Future<void> _uninstallPhp(Software software, String storagePath) async {
    // 检查是否有项目在使用此 PHP 版本
    final projectsUsingPhp = await _findProjectsUsingPhp(software.id, storagePath);

    if (projectsUsingPhp.isNotEmpty) {
      // 检查是否还有其他 PHP 版本
      final otherPhpVersions = await _getOtherPhpVersions(software.id, storagePath);

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
        final selectedPhp = await _showPhpVersionSelectionDialog(otherPhpVersions);
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
    await _stopServerSilently(software);

    // 删除 PHP 目录
    final phpDir = Directory('$storagePath/php/${software.id}');
    if (await phpDir.exists()) {
      await phpDir.delete(recursive: true);
    }

    // 如果不是最后一个 PHP 版本，更新 php.bat
    final remainingPhpVersions = await _getOtherPhpVersions(software.id, storagePath);
    if (remainingPhpVersions.isNotEmpty) {
      // 获取默认 PHP 版本（优先使用第一个）
      final defaultPhp = remainingPhpVersions.first;
      final defaultPhpDir = Directory('$storagePath/php/${defaultPhp.id}');
      if (await defaultPhpDir.exists()) {
        await InstallService.updatePhpBat(
          defaultPhpDir.path,
          storagePath,
        );
      }
    }

    await NotificationService.showSuccess(
      title: '卸载成功',
      message: '已卸载 ${software.name}',
    );
  }

  /// 查找使用指定 PHP 版本的项目
  Future<List<String>> _findProjectsUsingPhp(
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
            await NginxProjectHelper.readPhpVersionFromConfig(project.confFilePath);
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
          final phpMatch = RegExp(r"phpVersion:\s*(\w+)").firstMatch(projectDataStr);
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
  Future<List<Software>> _getOtherPhpVersions(
    String excludePhpId,
    String storagePath,
  ) async {
    final List<Software> otherPhp = [];
    if (_softwareSource == null) return otherPhp;

    final phpDir = Directory('$storagePath/php');
    if (await phpDir.exists()) {
      await for (final entity in phpDir.list()) {
        if (entity is Directory) {
          final phpId = path.basename(entity.path);
          if (phpId != excludePhpId) {
            final php = _softwareSource!.php.firstWhere(
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
  Future<Software?> _showPhpVersionSelectionDialog(List<Software> phpVersions) async {
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
              children: phpVersions.map(
                (php) => RadioListTile<Software>(
                  title: Text(php.name),
                  value: php,
                  groupValue: selectedPhp,
                  onChanged: (value) => setState(() => selectedPhp = value),
                ),
              ).toList(),
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
  Future<void> _updateProjectsSwitchPhp(
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
  Future<void> _updateProjectsRemovePhp(
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
  Future<void> _uninstallDatabase(Software software, String storagePath) async {
    // 查找使用此数据库的项目
    final projectsUsingDb = await _findProjectsUsingDatabase(software.id, storagePath);

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
  Future<List<String>> _findProjectsUsingDatabase(
    String databaseId,
    String storagePath,
  ) async {
    final List<String> projects = [];

    // 检查 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final nginxProjects = await NginxProjectHelper.parseNginxConfigs(nginxDir);
      for (final project in nginxProjects) {
        final projectDbIds =
            await NginxProjectHelper.readDatabaseIdsFromConfig(project.confFilePath);
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
          final dbMatches = RegExp(r"databases:\s*\[(.*?)\]").firstMatch(projectDataStr);
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
  Future<void> _removeDatabaseFromProjects(
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
              } else if (line.trim().isNotEmpty && !line.trim().startsWith('#')) {
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
        final dbMatches = RegExp(r"databases:\s*\[(.*?)\]").firstMatch(projectDataStr);
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
  Future<void> _uninstallServiceDatabase(
    Software software,
    String storagePath,
    String cate4,
  ) async {
    // 停止服务
    await _stopServerSilently(software);

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
      await Process.run(
        'sc',
        ['delete', serviceName],
        runInShell: true,
      );
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
  Future<void> _uninstallRedisRudis(Software software, String storagePath) async {
    // 停止服务
    await _stopServerSilently(software);

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
  Future<void> _uninstallComposer(Software software, String storagePath) async {
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
  Future<void> _uninstallPhpmyadmin(Software software, String storagePath) async {
    // 删除 nginx 项目
    final nginxDir = await NginxProjectHelper.getNginxDirectory();
    if (nginxDir != null) {
      final servsDir = Directory(path.join(nginxDir, 'servs'));
      if (await servsDir.exists()) {
        final projectConfFile = File(path.join(servsDir.path, 'phpmyadmin.conf'));
        if (await projectConfFile.exists()) {
          await projectConfFile.delete();
        }
        final projectSubconfFile = File(path.join(servsDir.path, 'phpmyadmin.subconf'));
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
  Future<void> _uninstallDbeaver(Software software, String storagePath) async {
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
  Future<void> _uninstallTinyRdm(Software software, String storagePath) async {
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
  Future<void> _uninstallMongodbCompass(Software software, String storagePath) async {
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
        final mongodbCompassDir =
            Directory(path.join(roamingPath, 'MongoDB Compass'));
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
  Future<void> _uninstallHeidisql(Software software, String storagePath) async {
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
  Future<void> _uninstallDefault(
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

/// 安装进度对话框
class _InstallProgressDialog extends StatefulWidget {
  final Software software;
  final String category;
  final Function(bool success, String? error) onComplete;
  final GlobalKey<NavigatorState>? pageNavigatorKey;

  const _InstallProgressDialog({
    required this.software,
    required this.category,
    required this.onComplete,
    this.pageNavigatorKey,
  });

  @override
  State<_InstallProgressDialog> createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<_InstallProgressDialog> {
  String _stage = '准备安装...';
  int _progress = 0;
  bool _isInstalling = true;
  final List<String> _logMessages = [];
  bool _isDownloading = false;
  bool _isCancelled = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startInstall();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 自动滚动到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startInstall({bool userConfirmedHashMismatch = false}) async {
    _isCancelled = false; // 重置取消标志
    final result = await InstallService.installSoftware(
      widget.software,
      widget.category,
      userConfirmedHashMismatch: userConfirmedHashMismatch,
      cancellationToken: () => _isCancelled, // 传递取消令牌
      onProgress: (stage, progress, logMessage) {
        if (mounted) {
          setState(() {
            _stage = stage;
            _progress = (progress * 100).toInt();
            // 检测是否在下载阶段
            _isDownloading = stage.contains('下载');
            if (logMessage != null) {
              // 检查是否是进度更新消息（需要替换而不是追加）
              if (logMessage.startsWith('PROGRESS_UPDATE:')) {
                // 移除标记并更新最后一条消息
                final actualMessage = logMessage.substring(
                  'PROGRESS_UPDATE:'.length,
                );
                if (_logMessages.isNotEmpty &&
                    _logMessages.last.startsWith('已下载:')) {
                  _logMessages[_logMessages.length - 1] = actualMessage;
                } else {
                  _logMessages.add(actualMessage);
                }
              } else {
                _logMessages.add(logMessage);
              }
              // 自动滚动到底部
              _scrollToBottom();
            }
          });
        }
      },
    );

    final success = result.$1;
    final error = result.$2;
    // final calculatedHash = result.$3; // 暂不使用

    if (mounted) {
      setState(() {
        // _calculatedHash = calculatedHash; // 已注释，暂不使用
      });
    }

    if (mounted) {
      // 检查是否是哈希不匹配的情况
      if (!success && error == InstallService.statusHashMismatch) {
        // 显示哈希不匹配确认对话框
        final pageContext = widget.pageNavigatorKey?.currentContext ?? context;

        final shouldContinue = await showDialog<bool>(
          context: pageContext,
          useRootNavigator: false, // 只在当前页面的 Navigator 中显示
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('文件完整性验证失败'),
            content: const Text('下载的文件哈希值与预期值不匹配，文件可能已损坏或被篡改。\n\n是否仍要继续安装？'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('取消安装'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: const Text('继续安装'),
              ),
            ],
          ),
        );

        if (shouldContinue == true) {
          // 用户选择继续安装，重新调用安装方法
          await _startInstall(userConfirmedHashMismatch: true);
          return;
        } else {
          // 用户选择取消，清除下载痕迹
          await _cleanupDownloadFiles();
          setState(() {
            _isInstalling = false;
            _stage = '安装已取消';
          });
          widget.onComplete(false, '用户取消了安装');
          return;
        }
      }

      setState(() {
        _isInstalling = false;
        _isDownloading = false;
        if (!success && error != null) {
          _stage = error;
        }
      });

      widget.onComplete(success, error);

      // 不再自动关闭，只显示关闭按钮
    }
  }

  /// 清除下载文件痕迹
  Future<void> _cleanupDownloadFiles() async {
    try {
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null || storagePath.isEmpty) {
        return;
      }

      final fileName = path.basename(
        Uri.parse(widget.software.downloadURL).path,
      );
      final downloadPath = '$storagePath/${widget.category}/$fileName';
      final downloadFile = File(downloadPath);

      if (await downloadFile.exists()) {
        await downloadFile.delete();
      }
    } catch (e) {
      // 忽略清理错误
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFF0C0C0C);
    final textColor = isDark
        ? const Color(0xFF00FF00)
        : const Color(0xFF00FF00);
    final errorColor = const Color(0xFFFF0000);
    final warningColor = const Color(0xFFFFFF00);

    return AlertDialog(
      title: Text('安装 ${widget.software.name}'),
      content: SizedBox(
        width: double.maxFinite,
        height: 340, // 固定高度：命令行区域300 + 间距12 + 进度条4 + 其他间距14
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 命令行样式的输出区域
            Container(
              width: double.maxFinite,
              height: 270, // 固定高度
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      ..._logMessages.asMap().entries.map((entry) {
                        final msg = entry.value;
                        Color msgColor = textColor;
                        if (msg.contains('错误') || msg.contains('失败')) {
                          msgColor = errorColor;
                        } else if (msg.contains('警告')) {
                          msgColor = warningColor;
                        } else if (msg.contains('XXH64') ||
                            msg.contains('哈希')) {
                          msgColor = const Color(0xFF00FFFF); // 青色显示哈希值
                        }
                        return TextSpan(
                          text: '$msg\n',
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 12,
                            color: msgColor,
                            height: 1.4,
                          ),
                        );
                      }),
                      if (_isInstalling)
                        TextSpan(
                          text: '$_stage ($_progress%)\n',
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 12,
                            color: textColor,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 进度条
            if (_isInstalling) ...[
              LinearProgressIndicator(
                value: _progress / 100.0,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _progress == 100 ? Colors.green : Colors.blue,
                ),
              ),
            ],
            // // 显示 XXH64 哈希值
            // if (_calculatedHash != null && !_isInstalling) ...[
            //   const SizedBox(height: 8),
            //   Container(
            //     padding: const EdgeInsets.all(8),
            //     decoration: BoxDecoration(
            //       color: Colors.grey.shade100,
            //       borderRadius: BorderRadius.circular(4),
            //       border: Border.all(color: Colors.grey.shade300),
            //     ),
            //     child: Column(
            //       crossAxisAlignment: CrossAxisAlignment.start,
            //       children: [
            //         Text(
            //           'XXH64:',
            //           style: TextStyle(
            //             fontSize: 11,
            //             fontWeight: FontWeight.bold,
            //             color: Colors.grey.shade700,
            //           ),
            //         ),
            //         const SizedBox(height: 4),
            //         SelectableText(
            //           _calculatedHash!,
            //           style: TextStyle(
            //             fontFamily: 'Courier New',
            //             fontSize: 11,
            //             color: Colors.grey.shade900,
            //           ),
            //         ),
            //       ],
            //     ),
            //   ),
            // ],
          ],
        ),
      ),
      actions: [
        if (_isInstalling && _isDownloading)
          TextButton(
            onPressed: () {
              if (mounted) {
                setState(() {
                  _isCancelled = true;
                  _logMessages.add('用户取消了下载');
                });
              }
            },
            child: const Text('取消下载'),
          ),
        if (!_isInstalling)
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('关闭'),
          ),
      ],
    );
  }
}
