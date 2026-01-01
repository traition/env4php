import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../services/config_service.dart';
import '../services/software_source_service.dart';
import '../services/storage_monitor_service.dart';
import '../services/notification_service.dart';
import '../widgets/storage_path_dialog.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _storagePath;
  String? _softwareSourcePath;
  bool _isLoading = true;
  String? _sourceFolderSize;
  bool _isCalculatingSize = false;
  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 初始化数据
  Future<void> _initialize() async {
    await _loadStoragePath();
    _loadSoftwareSourcePath();
    // 等待存储路径加载完成后再计算大小
    if (_storagePath != null && _storagePath!.isNotEmpty) {
      await _calculateSourceFolderSize();
      // 开始监控 sources 目录
      await StorageMonitorService().startSourcesMonitoring(_onSourcesChanged);
    }
  }

  @override
  void dispose() {
    // 停止监控 sources 目录
    StorageMonitorService().stopSourcesMonitoring();
    super.dispose();
  }

  /// Sources 目录变更回调
  void _onSourcesChanged() {
    if (mounted && _storagePath != null && _storagePath!.isNotEmpty) {
      _calculateSourceFolderSize();
    }
  }

  Future<void> _loadStoragePath() async {
    final path = await ConfigService.getStoragePath();
    setState(() {
      _storagePath = path;
      _isLoading = false;
    });
  }

  Future<void> _loadSoftwareSourcePath() async {
    if (kDebugMode) {
      final path = await SoftwareSourceService.getLocalSourcePath();
      setState(() {
        _softwareSourcePath = path;
      });
    }
  }

  Future<void> _changeStoragePath() async {
    final newPath = await showDialog<String>(
      useRootNavigator: false, // 不在根 Navigator 中显示，只在 Container 区域显示
      context: context,
      builder: (context) => const StoragePathDialog(),
    );

    if (newPath != null && newPath.isNotEmpty) {
      // 保存新路径
      await ConfigService.setStoragePath(newPath);
      // 重新启动存储目录监控
      await StorageMonitorService().startMonitoring();
      // 初始化目录结构
      await ConfigService.initializeStorageDirectories(newPath);
      // 重新加载
      await _loadStoragePath();
      // 重新计算 Source 文件夹大小
      await _calculateSourceFolderSize();
      // 重新启动 sources 目录监控
      if (_storagePath != null && _storagePath!.isNotEmpty) {
        await StorageMonitorService().startSourcesMonitoring(_onSourcesChanged);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('存储目录已更新'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _openStoragePath() async {
    if (_storagePath == null || _storagePath!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('存储目录未设置')));
      return;
    }

    final storageDir = Directory(_storagePath!);
    if (!await storageDir.exists()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('存储目录不存在')));
      return;
    }

    // 在 Windows 上使用 explorer 打开目录
    try {
      await Process.run('explorer', [_storagePath!], runInShell: true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开目录: $e')));
    }
  }

  /// 计算 Source 文件夹大小
  Future<void> _calculateSourceFolderSize() async {
    if (_storagePath == null || _storagePath!.isEmpty) {
      if (mounted) {
        setState(() {
          _sourceFolderSize = '存储目录未设置';
        });
      }
      return;
    }

    setState(() {
      _isCalculatingSize = true;
    });

    try {
      final sourcesDir = Directory(path.join(_storagePath!, 'sources'));
      if (!await sourcesDir.exists()) {
        setState(() {
          _sourceFolderSize = '0 B';
          _isCalculatingSize = false;
        });
        return;
      }

      final size = await _getDirectorySize(sourcesDir);
      setState(() {
        _sourceFolderSize = _formatFileSize(size);
        _isCalculatingSize = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _sourceFolderSize = '计算失败';
          _isCalculatingSize = false;
        });
      }
    }
  }

  /// 计算目录大小（递归）
  Future<int> _getDirectorySize(Directory dir) async {
    int size = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            size += stat.size;
          } catch (e) {
            // 忽略无法访问的文件
          }
        }
      }
    } catch (e) {
      // 忽略无法访问的目录
    }
    return size;
  }

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 清理 Source 文件夹
  Future<void> _cleanSourceFolder() async {
    if (_storagePath == null || _storagePath!.isEmpty) {
      await NotificationService.showError(title: '错误', message: '存储目录未设置');
      return;
    }

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('确认清理'),
        content: const Text('清理 Source 文件夹后，已下载的安装包将被删除，可能将无法重新下载。\n确定要继续吗？'),
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
            child: const Text('确定清理'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isCleaning = true;
    });

    try {
      final sourcesDir = Directory(path.join(_storagePath!, 'sources'));
      if (await sourcesDir.exists()) {
        await sourcesDir.delete(recursive: true);
      }

      // 重新计算大小
      await _calculateSourceFolderSize();

      if (mounted) {
        await NotificationService.showSuccess(
          title: '清理成功',
          message: 'Source 文件夹已清理',
        );
      }
    } catch (e) {
      if (mounted) {
        await NotificationService.showError(
          title: '清理失败',
          message: '清理 Source 文件夹时发生错误: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCleaning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.folder),
                    title: const Text('存储目录'),
                    subtitle: _storagePath != null && _storagePath!.isNotEmpty
                        ? Text(
                            _storagePath!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : const Text(
                            '未设置',
                            style: TextStyle(color: Colors.red),
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_storagePath != null && _storagePath!.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.folder_open),
                            tooltip: '打开目录',
                            onPressed: _openStoragePath,
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: '修改目录',
                          onPressed: _changeStoragePath,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Source 文件夹清理
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_special),
                  title: const Text('Source 目录'),
                  subtitle: _isCalculatingSize
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('正在计算大小...'),
                          ],
                        )
                      : Text(
                          _sourceFolderSize ?? '未知',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                  trailing: ElevatedButton.icon(
                    onPressed:
                        _isCleaning ||
                            _isCalculatingSize ||
                            _sourceFolderSize == '0 B' ||
                            _sourceFolderSize == '存储目录未设置'
                        ? null
                        : _cleanSourceFolder,
                    icon: _isCleaning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(_isCleaning ? '清理中...' : '清理'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Debug 模式下显示软件源文件地址
          if (kDebugMode) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.code),
                title: const Text('软件源文件（Debug）'),
                subtitle: _softwareSourcePath != null
                    ? Text(
                        _softwareSourcePath!,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const Text('加载中...'),
                trailing: _softwareSourcePath != null
                    ? IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: '打开目录',
                        onPressed: () async {
                          final file = File(_softwareSourcePath!);
                          final dir = file.parent;
                          if (await dir.exists()) {
                            try {
                              await Process.run('explorer', [
                                dir.path,
                              ], runInShell: true);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('无法打开目录: $e')),
                                );
                              }
                            }
                          }
                        },
                      )
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
