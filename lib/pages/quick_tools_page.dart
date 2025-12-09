import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/install_service.dart';

/// 快捷工具页面
class QuickToolsPage extends StatelessWidget {
  const QuickToolsPage({super.key});

  /// 更换终端的PHP版本
  Future<void> _changePhpVersion(BuildContext context) async {
    // 1. 检查已安装的 PHP 版本
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('存储目录未设置，请先设置存储目录'),
        ),
      );
      return;
    }

    final softwareSource = await SoftwareSourceService.getSource();
    if (softwareSource == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法加载软件源'),
        ),
      );
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
        const SnackBar(
          content: Text('未安装 PHP，请先安装 2 个或以上版本的 PHP'),
        ),
      );
      return;
    }

    if (installedPhp.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('只安装了一个 PHP 版本，无法更改。请先安装 2 个或以上版本的 PHP'),
        ),
      );
      return;
    }

    // 2. 让用户选择 PHP 版本
    final selectedPhp = await showDialog<Software>(
      context: context,
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
                subtitle: php.description != null ? Text(php.description!) : null,
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
        SnackBar(
          content: Text('替换失败: ${updateResult.$2 ?? "未知错误"}，请重新安装 PHP'),
        ),
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

  /// 编辑hosts文件（占位函数）
  void _editHosts(BuildContext context) {
    // TODO: 实现hosts编辑的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('编辑hosts文件（功能待实现）'),
        duration: Duration(seconds: 2),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '快捷工具',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
              children: [
                _buildToolCard(
                  context,
                  icon: Icons.code,
                  title: '更换PHP版本',
                  subtitle: '更换终端的PHP版本',
                  onTap: () => _changePhpVersion(context),
                ),
                _buildToolCard(
                  context,
                  icon: Icons.edit,
                  title: '编辑hosts',
                  subtitle: '编辑系统hosts文件',
                  onTap: () => _editHosts(context),
                ),
                _buildToolCard(
                  context,
                  icon: Icons.lock_reset,
                  title: '重置MySQL密码',
                  subtitle: '重置root@mysql密码',
                  onTap: () => _resetMysqlPassword(context),
                ),
                _buildToolCard(
                  context,
                  icon: Icons.lock_reset,
                  title: '重置PostgreSQL密码',
                  subtitle: '重置postgre@pgsql密码',
                  onTap: () => _resetPostgresqlPassword(context),
                ),
                _buildToolCard(
                  context,
                  icon: Icons.network_check,
                  title: 'TCP端口占用',
                  subtitle: '查看TCP端口占用列表',
                  onTap: () => _showTcpPorts(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建工具卡片
  Widget _buildToolCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

