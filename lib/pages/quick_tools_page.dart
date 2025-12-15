import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/install_service.dart';
import 'hosts_edit_page.dart';

/// 工具项数据模型
class _ToolItemData {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  _ToolItemData({required this.icon, required this.title, required this.onTap});
}

/// 快捷工具页面
class QuickToolsPage extends StatefulWidget {
  const QuickToolsPage({super.key});

  @override
  State<QuickToolsPage> createState() => _QuickToolsPageState();
}

class _QuickToolsPageState extends State<QuickToolsPage> {
  int _selectedTabIndex = 0; // 0: 系统, 1: 编解码, 2: 加解密, 3: 生成器

  /// 更换终端的PHP版本
  Future<void> _changePhpVersion(BuildContext context) async {
    // 1. 检查已安装的 PHP 版本
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('存储目录未设置，请先设置存储目录')));
      return;
    }

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法加载软件源')));
      return;
    }

    // 获取已安装的 PHP 软件列表
    final List<Software> installedPhp = [];
    for (final php in softwareSource.php) {
      final dir = Directory('$storagePath/php/${php.id}');
      if (await dir.exists()) {
        installedPhp.add(php);
      }
    }

    // 检查数量
    if (installedPhp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未安装 PHP，请先安装 2 个或以上版本的 PHP')),
      );
      return;
    }

    if (installedPhp.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只安装了一个 PHP 版本，无法更改。请先安装 2 个或以上版本的 PHP')),
      );
      return;
    }

    // 2. 让用户选择 PHP 版本
    final selectedPhp = await showDialog<Software>(
      context: context,
      useRootNavigator: false, // 不在根 Navigator 中显示，只在 Container 区域显示
      builder: (context) => AlertDialog(
        title: const Text('选择 PHP 版本'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: installedPhp.length,
            itemBuilder: (context, index) {
              final php = installedPhp[index];
              return ListTile(
                title: Text(php.name),
                subtitle: php.description != null
                    ? Text(php.description!)
                    : null,
                onTap: () => Navigator.of(context).pop(php),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selectedPhp == null) {
      // 用户取消了选择
      return;
    }

    // 3. 修改 php.bat 文件
    final selectedPhpPath = path.join(storagePath, 'php', selectedPhp.id);

    final updateResult = await InstallService.updatePhpBat(
      selectedPhpPath,
      storagePath,
      onProgress: (step, progress, logMessage) {
        // 可以在这里显示进度，但通常不需要
      },
    );

    if (!updateResult.$1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('替换失败: ${updateResult.$2 ?? "未知错误"}，请重新安装 PHP')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已成功将 PHP 版本切换为 ${selectedPhp.name}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// 编辑hosts文件
  void _editHosts(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const HostsEditPage()));
  }

  /// 重置MySQL root密码（占位函数）
  void _resetMysqlPassword(BuildContext context) {
    // TODO: 实现重置MySQL root密码的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('重置MySQL root密码（功能待实现）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 重置PostgreSQL postgre密码（占位函数）
  void _resetPostgresqlPassword(BuildContext context) {
    // TODO: 实现重置PostgreSQL postgre密码的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('重置PostgreSQL postgre密码（功能待实现）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 显示TCP端口占用列表（占位函数）
  void _showTcpPorts(BuildContext context) {
    // TODO: 实现TCP端口占用列表的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('TCP端口占用列表（功能待实现）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧 Tab 栏（背景透明）
        Container(
          width: 135,
          color: Colors.transparent, // 背景透明
          child: ListView(
            padding: const EdgeInsets.only(
              left: 6,
              right: 2,
              top: 4, // 与右侧页面的padding对齐
              bottom: 8,
            ),
            children: [
              _buildTabItem(context, '系统', 0, Icons.settings),
              const SizedBox(height: 6),
              _buildTabItem(context, '编解码', 1, Icons.code),
              const SizedBox(height: 6),
              _buildTabItem(context, '加解密', 2, Icons.lock),
              const SizedBox(height: 6),
              _buildTabItem(context, '生成器', 3, Icons.auto_awesome),
            ],
          ),
        ),
        // 右侧内容区域
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildTabContent(context),
          ),
        ),
      ],
    );
  }

  /// 构建 Tab 项
  Widget _buildTabItem(
    BuildContext context,
    String title,
    int index,
    IconData icon,
  ) {
    final isSelected = _selectedTabIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
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
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
      ),
    );
  }

  /// 构建 Tab 内容
  Widget _buildTabContent(BuildContext context) {
    switch (_selectedTabIndex) {
      case 0: // 系统
        return _buildSystemTab(context);
      case 1: // 编解码
        return _buildEncodeDecodeTab(context);
      case 2: // 加解密
        return _buildEncryptDecryptTab(context);
      case 3: // 生成器
        return _buildGeneratorTab(context);
      default:
        return _buildSystemTab(context);
    }
  }

  /// 构建系统 Tab 内容
  Widget _buildSystemTab(BuildContext context) {
    final tools = [
      _ToolItemData(
        icon: Icons.code,
        title: '更换PHP版本',
        onTap: () => _changePhpVersion(context),
      ),
      _ToolItemData(
        icon: Icons.edit,
        title: '编辑hosts',
        onTap: () => _editHosts(context),
      ),
      _ToolItemData(
        icon: Icons.lock_reset,
        title: '重置MySQL密码',
        onTap: () => _resetMysqlPassword(context),
      ),
      _ToolItemData(
        icon: Icons.lock_reset,
        title: '重置PostgreSQL密码',
        onTap: () => _resetPostgresqlPassword(context),
      ),
      _ToolItemData(
        icon: Icons.network_check,
        title: 'TCP端口占用',
        onTap: () => _showTcpPorts(context),
      ),
    ];

    // 将工具列表分成两栏
    final leftColumn = <_ToolItemData>[];
    final rightColumn = <_ToolItemData>[];

    for (int i = 0; i < tools.length; i++) {
      if (i % 2 == 0) {
        leftColumn.add(tools[i]);
      } else {
        rightColumn.add(tools[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏
        Expanded(
          child: ListView(
            children: leftColumn
                .map(
                  (tool) => _buildToolItem(
                    context,
                    icon: tool.icon,
                    title: tool.title,
                    onTap: tool.onTap,
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(width: 16),
        // 右栏
        Expanded(
          child: ListView(
            children: rightColumn
                .map(
                  (tool) => _buildToolItem(
                    context,
                    icon: tool.icon,
                    title: tool.title,
                    onTap: tool.onTap,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  /// 构建编解码 Tab 内容
  Widget _buildEncodeDecodeTab(BuildContext context) {
    return Center(
      child: Text(
        '编解码工具（功能待实现）',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 构建加解密 Tab 内容
  Widget _buildEncryptDecryptTab(BuildContext context) {
    return Center(
      child: Text(
        '加解密工具（功能待实现）',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 构建生成器 Tab 内容
  Widget _buildGeneratorTab(BuildContext context) {
    return Center(
      child: Text(
        '生成器工具（功能待实现）',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 构建工具项（两栏布局：左边图标，右边名称）
  Widget _buildToolItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 左侧图标
              Icon(
                icon,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              // 右侧名称
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
