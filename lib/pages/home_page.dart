import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';
import '../widgets/title_bar.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/notification_service.dart';
import '../services/icon_service.dart';
import '../services/tool_launcher_service.dart';
import '../widgets/storage_path_dialog.dart';
import '../models/software_model.dart';
import '../utils/software_helper.dart';
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // 当前选中的页面
  String _currentPage = '控制台';
  // 顶栏的垂直偏移（用于在有AppBar的页面时下移）
  double _titleBarTopOffset = 0;
  // Container 区域的 Navigator Key
  final GlobalKey<NavigatorState> _containerNavigatorKey =
      GlobalKey<NavigatorState>();
  // 右侧页面容器的 Navigator Key
  final GlobalKey<NavigatorState> _rightContainerNavigatorKey =
      GlobalKey<NavigatorState>();
  // 已安装的工具列表
  List<Software> _installedTools = [];
  // 使用 IndexedStack 保持页面状态
  final Map<String, Widget> _pageCache = {};

  // 获取当前页面的索引
  int _getPageIndex() {
    switch (_currentPage) {
      case '控制台':
        return 0;
      case '软件管理':
        return 1;
      case '快捷工具':
        return 2;
      case '设置':
        return 3;
      default:
        return 0;
    }
  }

  // 获取所有页面
  List<Widget> _getAllPages() {
    if (_pageCache.isEmpty) {
      _pageCache['控制台'] = ConsolePage(
        key: ConsolePage.globalKey,
        navigatorKey: _rightContainerNavigatorKey,
      );
      _pageCache['软件管理'] = const SoftwareManagementPage();
      _pageCache['快捷工具'] = const QuickToolsPage();
      _pageCache['设置'] = const SettingsPage();
    }
    return [
      _pageCache['控制台']!,
      _pageCache['软件管理']!,
      _pageCache['快捷工具']!,
      _pageCache['设置']!,
    ];
  }

  @override
  void initState() {
    super.initState();
    // 注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);
    // 延迟初始化，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
      _checkRouteAndUpdateTitleBar();
      _loadInstalledTools();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 应用关闭时停止所有服务
    final consoleState = ConsolePage.globalKey.currentState;
    if (consoleState != null) {
      consoleState.stopAllServersOnClose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // 应用即将关闭，停止所有服务
      final consoleState = ConsolePage.globalKey.currentState;
      if (consoleState != null) {
        consoleState.stopAllServersOnClose();
      }
    }
  }

  /// 加载已安装的tools应用
  Future<void> _loadInstalledTools() async {
    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) return;

    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) return;

    final List<Software> installed = [];

    for (final software in softwareSource.tools) {
      // 过滤掉composer相关的应用（cate4、id、文件夹名任一匹配composer）
      if (software.cate4?.toLowerCase() == 'composer' ||
          software.id.toLowerCase() == 'composer') {
        continue;
      }

      final dir = Directory('$storagePath/tools/${software.id}');
      if (await dir.exists()) {
        // 检查文件夹名称是否为composer
        final folderName = path.basename(dir.path).toLowerCase();
        if (folderName == 'composer') {
          continue;
        }
        installed.add(software);
      }
    }

    // 检查pgsql是否已安装，如果已安装则添加虚拟的pgAdmin4
    final isPgsqlInstalled = await SoftwareHelper.isPgsqlInstalled(
      softwareSource: softwareSource,
      storagePath: storagePath,
    );
    if (isPgsqlInstalled) {
      installed.add(SoftwareHelper.createPgAdmin4Software());
    }

    if (mounted) {
      setState(() {
        _installedTools = installed;
      });
    }
  }


  /// 检查当前路由并更新顶栏位置
  void _checkRouteAndUpdateTitleBar() {
    if (!mounted) return;

    // 检查当前路由栈中是否有AppBar页面（如HostsEditPage）
    final navigator = Navigator.of(context);
    final canPop = navigator.canPop();

    // 如果有可以返回的路由，说明有全屏页面打开，顶栏应该下移
    // AppBar的标准高度是56px（Material 3）
    final newOffset = canPop ? 56.0 : 0.0;

    if (newOffset != _titleBarTopOffset) {
      setState(() {
        _titleBarTopOffset = newOffset;
      });
    }
  }

  /// 初始化应用（检查配置、下载软件源）
  Future<void> _initialize() async {
    // 初始化软件源服务
    SoftwareSourceService.initialize();

    // 检查存储目录是否设置
    final isStorageSet = await ConfigService.isStoragePathSet();
    if (!isStorageSet && mounted) {
      // 显示设置对话框（使用 Container Navigator 的 context）
      final containerContext = _containerNavigatorKey.currentContext;
      if (containerContext != null) {
        final path = await showDialog<String>(
          context: containerContext,
          useRootNavigator: false,
          builder: (context) => const StoragePathDialog(),
        );

        if (path != null && path.isNotEmpty) {
          await ConfigService.setStoragePath(path);
          await ConfigService.initializeStorageDirectories(path);
        }
      }
    } else if (isStorageSet) {
      // 确保目录结构存在
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath != null) {
        await ConfigService.initializeStorageDirectories(storagePath);
      }
    }

    // 检查并下载软件源（只有首次打开或没有缓存时才下载）
    await _checkAndDownloadSoftwareSource();
  }

  /// 检查并下载软件源（每次冷启动都更新）
  Future<void> _checkAndDownloadSoftwareSource() async {
    // 检查是否有缓存
    final hasCache = await SoftwareSourceService.hasCachedSource();

    if (!hasCache) {
      // 没有缓存，需要下载
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

      // 尝试下载（5秒超时）
      final downloadSuccess = await SoftwareSourceService.downloadSource(
        timeout: const Duration(seconds: 5),
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
          // 下载失败，显示系统通知
          await NotificationService.showError(
            title: '软件源加载失败',
            message: '无法从服务器下载软件源，且没有可用的缓存。请检查网络连接，或修改软件源地址。',
          );
        }
      }
    } else {
      // 有缓存，在后台更新软件源（冷启动时总是更新）
      _updateSoftwareSourceInBackground();
    }
  }

  /// 在后台更新软件源（冷启动时调用）
  Future<void> _updateSoftwareSourceInBackground() async {
    try {
      final hasUpdate = await SoftwareSourceService.checkForUpdate();
      if (hasUpdate && mounted) {
        // 有更新，显示右下角通知
        await NotificationService.showInfo(
          title: '软件源已更新',
          message: '软件源已更新到最新版本',
        );
      }
    } catch (e) {
      // 更新失败，静默处理，不影响用户体验
      if (kDebugMode) {
        print('更新软件源失败: $e');
      }
    }
  }

  // 获取当前页面组件
  /// 构建侧边栏项（带圆角和间距）
  Widget _buildSidebarItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isSelected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        selected: isSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }

  /// 构建工具列表
  Widget _buildToolsList(BuildContext context) {
    return Row(
      children: [
        // "工具"文字区域 - 可拖动区域
        Listener(
          onPointerDown: (event) {
            windowManager.startDragging();
          },
          behavior: HitTestBehavior.translucent,
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: SizedBox(
              width: 48,
              child: Center(
                child: Text(
                  '工具 ',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
        // 工具列表 - 工具按钮可点击，空白区域可拖动
        Expanded(
          child: Row(
            children: [
              // 工具按钮列表（可点击，支持横向滚动）
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_installedTools.length, (index) {
                    final tool = _installedTools[index];
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToolChip(context, tool),
                        if (index < _installedTools.length - 1)
                          // 工具按钮之间的空白区域，可拖动
                          Listener(
                            onPointerDown: (event) {
                              windowManager.startDragging();
                            },
                            behavior: HitTestBehavior.translucent,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.move,
                              child: const SizedBox(width: 10),
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              ),
              // 右侧空白区域，可拖动
              Expanded(
                child: Listener(
                  onPointerDown: (event) {
                    windowManager.startDragging();
                  },
                  behavior: HitTestBehavior.translucent,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Container(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建工具芯片
  Widget _buildToolChip(BuildContext context, Software tool) {
    return SizedBox.square(
      dimension: 32,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            // 启动工具
            final result = await ToolLauncherService.launchTool(tool);
            if (!result.$1) {
              // 启动失败，显示错误提示
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.$2 ?? '启动 ${tool.name} 失败'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } else if (result.$2 == 'WINDOW_ALREADY_RUNNING') {
              // 窗口已运行，显示提示信息
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${tool.name} 已在运行'),
                    backgroundColor: Colors.blue,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle, // 圆形背景
            ),
            padding: const EdgeInsets.all(5),
            child: ClipOval(
              child: AspectRatio(
                aspectRatio: 1.0, // 强制1:1比例
                child: FutureBuilder<String?>(
                  future: _getIconPath(tool),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      // 图标文件存在，显示图标
                      return Image.file(
                        File(snapshot.data!),
                        fit: BoxFit.contain, // 完整显示图标，不裁切
                        errorBuilder: (context, error, stackTrace) {
                          // 图标加载失败，显示应用id
                          return Center(
                            child: Text(
                              tool.id,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w500),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      );
                    } else {
                      // 找不到图标，显示应用id
                      return Center(
                        child: Text(
                          tool.id,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 获取工具图标路径
  /// 获取图标路径，使用 IconService 统一处理
  Future<String?> _getIconPath(Software software) async {
    return await IconService.getIconPath(software);
  }

  @override
  Widget build(BuildContext context) {
    // 每次build时检查路由变化并更新顶栏位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRouteAndUpdateTitleBar();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFF1F2F3);

    return Container(
      color: backgroundColor, // 设置背景色，确保不透明
      child: Stack(
        children: [
          // 左上角模糊渐变
          Positioned(
            top: -150,
            left: -150,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, // -45度方向
                    end: Alignment.bottomRight,
                    colors: const [
                      Color(0xFFBD34FE), // #bd34fe 紫色
                    ],
                    stops: const [1], // 各占50%
                  ),
                ),
              ),
            ),
          ),
          // 主要内容
          Column(
            children: [
              // TitleBar 部分
              Transform.translate(
                offset: Offset(0, _titleBarTopOffset),
                child: TitleBar(
                  title: widget.title,
                  toolsList: _installedTools.isNotEmpty
                      ? _buildToolsList(context)
                      : null,
                ),
              ),
              // Container 部分（主要内容区域，使用独立的 Navigator 确保 dialog 只在此区域显示）
              Expanded(
                child: Navigator(
                  key: _containerNavigatorKey,
                  onGenerateRoute: (settings) {
                    return MaterialPageRoute(
                      builder: (context) => Scaffold(
                        backgroundColor: Colors.transparent,
                        body: Row(
                          children: [
                            // 左侧侧边栏（背景透明）
                            Container(
                              width: 160, // 180 * 0.8
                              color: Colors.transparent, // 背景透明
                              child: ListView(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  top: 10, // 与右侧页面的margin对齐
                                  bottom: 8,
                                ),
                                children: <Widget>[
                                  _buildSidebarItem(
                                    context,
                                    icon: Icons.terminal,
                                    title: '控制台',
                                    isSelected: _currentPage == '控制台',
                                    onTap: () {
                                      setState(() {
                                        _currentPage = '控制台';
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSidebarItem(
                                    context,
                                    icon: Icons.apps,
                                    title: '软件管理',
                                    isSelected: _currentPage == '软件管理',
                                    onTap: () {
                                      setState(() {
                                        _currentPage = '软件管理';
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSidebarItem(
                                    context,
                                    icon: Icons.flash_on,
                                    title: '快捷工具',
                                    isSelected: _currentPage == '快捷工具',
                                    onTap: () {
                                      setState(() {
                                        _currentPage = '快捷工具';
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSidebarItem(
                                    context,
                                    icon: Icons.settings,
                                    title: '设置',
                                    isSelected: _currentPage == '设置',
                                    onTap: () {
                                      setState(() {
                                        _currentPage = '设置';
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // 右侧内容区域（圆角边框和阴影）
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: IndexedStack(
                                    index: _getPageIndex(),
                                    children: _getAllPages(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
