import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'config_service.dart';

/// 存储目录监控服务
/// 监控存储目录下的 databases、php、servers、tools 目录的子目录变更
class StorageMonitorService {
  static final StorageMonitorService _instance =
      StorageMonitorService._internal();
  factory StorageMonitorService() => _instance;
  StorageMonitorService._internal();

  StreamSubscription<FileSystemEvent>? _databasesSubscription;
  StreamSubscription<FileSystemEvent>? _phpSubscription;
  StreamSubscription<FileSystemEvent>? _serversSubscription;
  StreamSubscription<FileSystemEvent>? _toolsSubscription;
  StreamSubscription<FileSystemEvent>? _sourcesSubscription;

  final List<Function()> _listeners = [];

  /// 添加变更监听器
  /// [listener] 当检测到变更时调用的回调函数
  void addChangeListener(Function() listener) {
    _listeners.add(listener);
  }

  /// 移除变更监听器
  void removeChangeListener(Function() listener) {
    _listeners.remove(listener);
  }

  /// 通知所有监听器
  void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        if (kDebugMode) {
          print('[存储监控] 通知监听器时发生错误: $e');
        }
      }
    }
  }

  /// 开始监控
  Future<void> startMonitoring() async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) {
      if (kDebugMode) {
        print('[存储监控] 存储目录未设置，无法开始监控');
      }
      return;
    }

    // 停止现有监控
    await stopMonitoring();

    // 监控的目录列表（不包含 sources，sources 由设置页面单独监控）
    final directories = [
      ('databases', path.join(storagePath, 'databases')),
      ('php', path.join(storagePath, 'php')),
      ('servers', path.join(storagePath, 'servers')),
      ('tools', path.join(storagePath, 'tools')),
    ];

    for (final (category, dirPath) in directories) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          // 目录不存在，创建它
          await dir.create(recursive: true);
        }

        // 开始监控目录
        final stream = dir.watch(recursive: false);
        StreamSubscription<FileSystemEvent>? subscription;

        subscription = stream.listen(
          (event) {
            _handleFileSystemEvent(event, category);
          },
          onError: (error) {
            if (kDebugMode) {
              print('[存储监控] 监控 $category 目录时发生错误: $error');
            }
          },
        );

        // 保存订阅
        switch (category) {
          case 'databases':
            _databasesSubscription = subscription;
            break;
          case 'php':
            _phpSubscription = subscription;
            break;
          case 'servers':
            _serversSubscription = subscription;
            break;
          case 'tools':
            _toolsSubscription = subscription;
            break;
          case 'sources':
            _sourcesSubscription = subscription;
            break;
        }

        if (kDebugMode) {
          print('[存储监控] 开始监控 $category 目录: $dirPath');
        }
      } catch (e) {
        if (kDebugMode) {
          print('[存储监控] 监控 $category 目录失败: $e');
        }
      }
    }
  }

  /// 停止监控
  Future<void> stopMonitoring() async {
    await _databasesSubscription?.cancel();
    await _phpSubscription?.cancel();
    await _serversSubscription?.cancel();
    await _toolsSubscription?.cancel();

    _databasesSubscription = null;
    _phpSubscription = null;
    _serversSubscription = null;
    _toolsSubscription = null;

    if (kDebugMode) {
      print('[存储监控] 已停止所有监控');
    }
  }

  /// 开始监控 sources 目录（用于设置页面）
  Future<void> startSourcesMonitoring(Function() onChanged) async {
    final storagePath = await ConfigService.getStoragePath();
    if (storagePath == null) {
      if (kDebugMode) {
        print('[存储监控] 存储目录未设置，无法监控 sources 目录');
      }
      return;
    }

    // 停止现有的 sources 监控
    await stopSourcesMonitoring();

    try {
      final sourcesDir = Directory(path.join(storagePath, 'sources'));
      if (!await sourcesDir.exists()) {
        await sourcesDir.create(recursive: true);
      }

      // 开始监控目录（递归监控，包括文件和子目录）
      final stream = sourcesDir.watch(recursive: true);
      _sourcesSubscription = stream.listen(
        (event) {
          _handleSourcesFileSystemEvent(event, onChanged);
        },
        onError: (error) {
          if (kDebugMode) {
            print('[存储监控] 监控 sources 目录时发生错误: $error');
          }
        },
      );

      if (kDebugMode) {
        print('[存储监控] 开始监控 sources 目录: ${sourcesDir.path}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[存储监控] 监控 sources 目录失败: $e');
      }
    }
  }

  /// 停止监控 sources 目录
  Future<void> stopSourcesMonitoring() async {
    await _sourcesSubscription?.cancel();
    _sourcesSubscription = null;

    if (kDebugMode) {
      print('[存储监控] 已停止 sources 目录监控');
    }
  }

  /// 处理 sources 目录的文件系统事件（监控文件和目录）
  void _handleSourcesFileSystemEvent(
    FileSystemEvent event,
    Function() onChanged,
  ) {
    // 处理所有类型的事件（包括文件创建、删除、修改）
    if (event.type == FileSystemEvent.create ||
        event.type == FileSystemEvent.delete ||
        event.type == FileSystemEvent.modify) {
      // 延迟处理，避免频繁触发
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          if (kDebugMode) {
            print(
              '[存储监控] 检测到 sources 目录变更: ${event.type} - ${path.basename(event.path)}',
            );
          }
          onChanged();
        } catch (e) {
          if (kDebugMode) {
            print('[存储监控] 处理 sources 文件系统事件时发生错误: $e');
          }
        }
      });
    }
  }

  /// 处理文件系统事件
  void _handleFileSystemEvent(FileSystemEvent event, String category) {
    // 只处理目录相关的事件
    if (event.type == FileSystemEvent.create ||
        event.type == FileSystemEvent.delete ||
        event.type == FileSystemEvent.modify) {
      final entity = event.path;
      final dir = Directory(entity);

      // 延迟处理，避免频繁触发
      Future.delayed(const Duration(milliseconds: 300), () async {
        try {
          // 对于 create 和 modify 事件，检查是否是目录
          if (event.type == FileSystemEvent.create ||
              event.type == FileSystemEvent.modify) {
            if (await dir.exists()) {
              final stat = await dir.stat();
              if (stat.type == FileSystemEntityType.directory) {
                if (kDebugMode) {
                  print(
                    '[存储监控] 检测到 $category 目录变更: ${event.type} - ${path.basename(entity)}',
                  );
                }
                _notifyListeners();
              }
            }
          } else if (event.type == FileSystemEvent.delete) {
            // 删除事件，直接通知
            if (kDebugMode) {
              print('[存储监控] 检测到 $category 目录删除: ${path.basename(entity)}');
            }
            _notifyListeners();
          }
        } catch (e) {
          if (kDebugMode) {
            print('[存储监控] 处理文件系统事件时发生错误: $e');
          }
        }
      });
    }
  }
}
