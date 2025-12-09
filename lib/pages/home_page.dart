import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/window_button.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../widgets/storage_path_dialog.dart';
import 'console_page.dart';
import 'software_management_page.dart';
import 'settings_page.dart';
import 'quick_tools_page.dart';

/// 主页面
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 当前选中的页面
  String _currentPage = '控制台';

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  /// 初始化应用（检查配置、下载软件源）
  Future<void> _initialize() async {
    // 初始化软件源服务
    SoftwareSourceService.initialize();

    // 检查存储目录是否设置
    final isStorageSet = await ConfigService.isStoragePathSet();
    if (!isStorageSet && mounted) {
      // 显示设置对话框
      final path = await showDialog<String>(
        context: context,
        builder: (context) => const StoragePathDialog(),
      );

      if (path != null && path.isNotEmpty) {
        await ConfigService.setStoragePath(path);
        await ConfigService.initializeStorageDirectories(path);
      }
    } else if (isStorageSet) {
      // 确保目录结构存在
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath != null) {
        await ConfigService.initializeStorageDirectories(storagePath);
      }
    }

    // 下载软件源（带交互式提示）
    await _downloadSoftwareSourceWithProgress();
  }

  /// 下载软件源（带交互式提示）
  Future<void> _downloadSoftwareSourceWithProgress() async {
    // 显示下载提示
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
              Text('正在下载软件源...'),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }

    // 尝试下载（3秒超时）
    final downloadSuccess = await SoftwareSourceService.downloadSource(
      timeout: const Duration(seconds: 3),
    );

    if (mounted) {
      if (downloadSuccess) {
        // 下载成功
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('软件源下载成功'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        // 下载失败，检查是否有缓存
        final hasCache = await SoftwareSourceService.hasCachedSource();

        if (hasCache) {
          // 有缓存，使用缓存
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('软件源下载失败，已使用缓存'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          // 没有缓存，提示用户并允许修改 URL
          final shouldModify = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('软件源加载失败'),
              content: const Text(
                '无法从服务器下载软件源，且没有可用的缓存。\n\n'
                '请检查网络连接，或修改软件源地址。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('稍后重试'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('修改软件源地址'),
                ),
              ],
            ),
          );

          if (shouldModify == true) {
            // 跳转到设置页面
            setState(() {
              _currentPage = '设置';
            });
          }
        }
      }
    }
  }

  // 获取当前页面组件
  Widget _getCurrentPage() {
    switch (_currentPage) {
      case '控制台':
        return const ConsolePage();
      case '软件管理':
        return const SoftwareManagementPage();
      case '快捷工具':
        return const QuickToolsPage();
      case '设置':
        return const SettingsPage();
      default:
        return const ConsolePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 自定义标题栏
          _buildTitleBar(context),
          // 主要内容区域
          Expanded(
            child: Row(
              children: [
                // 左侧侧边栏
                Container(
                  width: 160, // 180 * 0.8
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: <Widget>[
                            ListTile(
                              leading: const Icon(Icons.terminal),
                              title: const Text('控制台'),
                              selected: _currentPage == '控制台',
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.3),
                              onTap: () {
                                setState(() {
                                  _currentPage = '控制台';
                                });
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.apps),
                              title: const Text('软件管理'),
                              selected: _currentPage == '软件管理',
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.3),
                              onTap: () {
                                setState(() {
                                  _currentPage = '软件管理';
                                });
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.flash_on),
                              title: const Text('快捷工具'),
                              selected: _currentPage == '快捷工具',
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.3),
                              onTap: () {
                                setState(() {
                                  _currentPage = '快捷工具';
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.settings),
                        title: const Text('设置'),
                        selected: _currentPage == '设置',
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        onTap: () {
                          setState(() {
                            _currentPage = '设置';
                          });
                        },
                      ),
                    ],
                  ),
                ),
                // 右侧内容区域
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: _getCurrentPage(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inversePrimary,
      ),
      child: Row(
        children: [
          // 左侧标题
          Expanded(
            child: GestureDetector(
              onPanStart: (details) => windowManager.startDragging(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          // 右侧窗口控制按钮
          Row(
            children: [
              // 最小化按钮
              WindowButton(
                icon: Icons.remove,
                onPressed: () => windowManager.minimize(),
              ),
              // 最大化/还原按钮
              WindowButton(
                icon: Icons.crop_square,
                onPressed: () async {
                  bool isMaximized = await windowManager.isMaximized();
                  if (isMaximized) {
                    windowManager.restore();
                  } else {
                    windowManager.maximize();
                  }
                },
              ),
              // 关闭按钮
              WindowButton(
                icon: Icons.close,
                onPressed: () => windowManager.close(),
                isCloseButton: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
