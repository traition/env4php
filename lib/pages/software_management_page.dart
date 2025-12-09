import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/install_service.dart';
import '../widgets/storage_path_dialog.dart';

/// 软件管理页面
class SoftwareManagementPage extends StatefulWidget {
  const SoftwareManagementPage({super.key});

  @override
  State<SoftwareManagementPage> createState() => _SoftwareManagementPageState();
}

/// 日志查看器对话框
class _LogViewerDialog extends StatefulWidget {
  final File logFile;

  const _LogViewerDialog({required this.logFile});

  @override
  State<_LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<_LogViewerDialog> {
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

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    // 检查存储目录是否设置
    final isStorageSet = await ConfigService.isStoragePathSet();
    if (!isStorageSet) {
      // 显示设置对话框
      if (mounted) {
        final path = await showDialog<String>(
          context: context,
          builder: (context) => const StoragePathDialog(),
        );

        if (path != null && path.isNotEmpty) {
          await ConfigService.setStoragePath(path);
          await ConfigService.initializeStorageDirectories(path);
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

  /// 检查pgsql是否已安装
  Future<bool> _isPgsqlInstalled() async {
    if (_softwareSource == null) return false;

    // 查找pgsql软件
    final pgsql = _softwareSource!.databases.firstWhere(
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

    if (pgsql.id.isEmpty) return false;

    // 检查pgsql是否已安装
    return _installedSoftware.any((s) => s.id == pgsql.id);
  }

  /// 创建虚拟的pgAdmin4应用
  Software _createPgAdmin4Software() {
    return Software(
      id: 'pgadmin4',
      name: 'pgAdmin4',
      description: 'PostgreSQL自带管理工具',
      byte: 0,
      downloadURL: '',
      commands: [],
      attachments: [],
      cate4: 'pgadmin4',
    );
  }

  /// 获取当前显示的软件列表
  Future<List<Software>> _getCurrentSoftwareList() async {
    if (_softwareSource == null) return [];

    List<Software> list;
    switch (_selectedTabIndex) {
      case 0: // 已安装
        list = _installedSoftware;
        // 如果pgsql已安装，添加虚拟的pgAdmin4应用
        final isPgsqlInstalled = await _isPgsqlInstalled();
        if (isPgsqlInstalled) {
          list = [...list, _createPgAdmin4Software()];
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
        final isPgsqlInstalled = await _isPgsqlInstalled();
        if (isPgsqlInstalled) {
          list = [...list, _createPgAdmin4Software()];
        }
        break;
      default:
        return [];
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      initialIndex: _selectedTabIndex,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('软件管理', style: Theme.of(context).textTheme.headlineMedium),
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : _buildSoftwareList(),
            ),
          ],
        ),
      ),
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

  /// 获取软件的分类名称
  String? _getSoftwareCategory(Software software) {
    if (_selectedTabIndex == 0) {
      // 已安装页面，需要从软件源中查找分类
      if (_softwareSource == null) return null;

      if (_softwareSource!.servers.any((s) => s.id == software.id)) {
        return 'servers';
      } else if (_softwareSource!.databases.any((s) => s.id == software.id)) {
        return 'databases';
      } else if (_softwareSource!.php.any((s) => s.id == software.id)) {
        return 'php';
      } else if (_softwareSource!.tools.any((s) => s.id == software.id)) {
        return 'tools';
      }
      return null;
    } else {
      // 其他页面，根据选中的 tab 确定分类
      switch (_selectedTabIndex) {
        case 1:
          return 'servers';
        case 2:
          return 'databases';
        case 3:
          return 'php';
        case 4:
          return 'tools';
        default:
          return null;
      }
    }
  }

  /// 获取图标文件路径
  Future<String?> _getIconPath(Software software) async {
    try {
      // 获取应用可执行文件目录
      final executablePath = Platform.resolvedExecutable;
      final executableDir = path.dirname(executablePath);
      final iconsDir = path.join(executableDir, 'assets', 'icons');

      // 确定图标文件名
      String? iconFileName;
      final category = _getSoftwareCategory(software);

      if (category == 'php') {
        // PHP 分类直接使用 php.png
        iconFileName = 'php.png';
      } else if (software.cate4 != null && software.cate4!.isNotEmpty) {
        // 其他分类使用 cate4 值作为文件名
        iconFileName = '${software.cate4}.png';
      } else {
        // 没有 cate4 值，不显示图标
        return null;
      }

      // 构建完整路径
      final iconPath = path.join(iconsDir, iconFileName);
      final iconFile = File(iconPath);

      // 检查文件是否存在
      if (await iconFile.exists()) {
        return iconPath;
      }

      return null;
    } catch (e) {
      // 出错时返回 null，不显示图标
      return null;
    }
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
                ? _isPgsqlInstalled()
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
                    if (software.byte > 0)
                      Text(
                        _formatBytes(software.byte),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (software.byte > 0) const SizedBox(width: 16),
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
    showDialog(
      context: context,
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
    showDialog(
      context: context,
      builder: (context) => _LogViewerDialog(logFile: logFile),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _InstallProgressDialog(
        software: software,
        category: category,
        onComplete: (success, error) {
          // 不自动关闭对话框，让用户手动关闭
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${software.name} 安装成功'),
                backgroundColor: Colors.green,
              ),
            );
            // 刷新已安装软件列表
            _refreshInstalledSoftware();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error ?? '${software.name} 安装失败'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
      ),
    );
  }

  void _showManageDialog(Software software) async {
    // 根据 cate4 值或分类显示不同的管理选项
    final isNginx = software.cate4?.toLowerCase() == 'nginx';
    final isRedis = software.cate4?.toLowerCase() == 'redis';
    final isRudis = software.cate4?.toLowerCase() == 'rudis';
    final isMysql = software.cate4?.toLowerCase() == 'mysql';
    final isMongodb = software.cate4?.toLowerCase() == 'mongodb';
    // 判断是否为 PHP 分类
    final isPhp =
        _softwareSource != null &&
        _softwareSource!.php.any((s) => s.id == software.id);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('管理 ${software.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isNginx) ...[
                // nginx 专用选项
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('编辑 nginx.conf'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editNginxConfig(software);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('查看 error.log'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _viewErrorLog(software);
                  },
                ),
                const Divider(),
              ],
              if (isRedis) ...[
                // redis 专用选项
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('编辑conf'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editRedisConfig(software);
                  },
                ),
                const Divider(),
              ],
              if (isRudis) ...[
                // rudis 专用选项
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('编辑配置'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editRudisConfig(software);
                  },
                ),
                const Divider(),
              ],
              if (isMysql) ...[
                // mysql 专用选项
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('编辑ini'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editMysqlIni(software);
                  },
                ),
                const Divider(),
              ],
              if (isMongodb) ...[
                // mongodb 专用选项
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('编辑配置'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editMongodbConfig(software);
                  },
                ),
                const Divider(),
              ],
              if (isPhp) ...[
                // PHP 专用选项
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('设为php-cli版本'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _setPhpCliVersion(software);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('编辑 php.ini'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editPhpIni(software);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension),
                  title: const Text('安装扩展'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _installPhpExtension(software);
                  },
                ),
                const Divider(),
              ],
              // 通用选项
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('打开目录'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openSoftwareDirectory(software);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('卸载'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showUninstallDialog(software);
                },
              ),
            ],
          ),
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

  void _showUninstallDialog(Software software) {
    showDialog(
      context: context,
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
              _refreshInstalledSoftware();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('已卸载 ${software.name}')));
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
}

/// 安装进度对话框
class _InstallProgressDialog extends StatefulWidget {
  final Software software;
  final String category;
  final Function(bool success, String? error) onComplete;

  const _InstallProgressDialog({
    required this.software,
    required this.category,
    required this.onComplete,
  });

  @override
  State<_InstallProgressDialog> createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<_InstallProgressDialog> {
  String _stage = '准备安装...';
  int _progress = 0;
  bool _isInstalling = true;
  final List<String> _logMessages = [];
  String? _calculatedHash;
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
    final calculatedHash = result.$3;

    if (mounted) {
      setState(() {
        _calculatedHash = calculatedHash;
      });
    }

    if (mounted) {
      // 检查是否是哈希不匹配的情况
      if (!success && error == InstallService.statusHashMismatch) {
        // 显示哈希不匹配确认对话框
        final shouldContinue = await showDialog<bool>(
          context: context,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 命令行样式的输出区域
            Container(
              width: double.maxFinite,
              height: 300,
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
