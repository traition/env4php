import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../services/config_service.dart';
import '../services/software_source_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadStoragePath();
    _loadSoftwareSourcePath();
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
      // 初始化目录结构
      await ConfigService.initializeStorageDirectories(newPath);
      // 重新加载
      await _loadStoragePath();

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
