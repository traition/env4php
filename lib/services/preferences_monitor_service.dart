import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 监控服务
/// 用于监控特定 key 的变更并通知监听器
class PreferencesMonitorService {
  static PreferencesMonitorService? _instance;
  Timer? _monitorTimer;
  Map<String, dynamic> _lastValues = {};
  final List<Function(String key, dynamic newValue)> _listeners = [];

  PreferencesMonitorService._();

  /// 获取单例实例
  static PreferencesMonitorService getInstance() {
    _instance ??= PreferencesMonitorService._();
    return _instance!;
  }

  /// 开始监控指定的 key
  /// [keys] 要监控的 key 列表
  /// [interval] 检查间隔（默认 1 秒）
  Future<void> startMonitoring(
    List<String> keys, {
    Duration interval = const Duration(seconds: 1),
  }) async {
    // 停止现有的监控
    stopMonitoring();

    // 初始化当前值
    final prefs = await SharedPreferences.getInstance();
    for (final key in keys) {
      final value = prefs.get(key);
      _lastValues[key] = value;
    }

    // 启动定时器
    _monitorTimer = Timer.periodic(interval, (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final key in keys) {
          final currentValue = prefs.get(key);
          final lastValue = _lastValues[key];

          // 检查值是否发生变化
          if (currentValue != lastValue) {
            if (kDebugMode) {
              print(
                '[PreferencesMonitor] Key "$key" 值已变更: $lastValue -> $currentValue',
              );
            }

            // 更新最后的值
            _lastValues[key] = currentValue;

            // 通知所有监听器
            for (final listener in _listeners) {
              try {
                listener(key, currentValue);
              } catch (e) {
                if (kDebugMode) {
                  print('[PreferencesMonitor] 监听器执行错误: $e');
                }
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[PreferencesMonitor] 监控时发生错误: $e');
        }
      }
    });

    if (kDebugMode) {
      print('[PreferencesMonitor] 开始监控 ${keys.length} 个 key');
    }
  }

  /// 停止监控
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _lastValues.clear();
    if (kDebugMode) {
      print('[PreferencesMonitor] 停止监控');
    }
  }

  /// 添加变更监听器
  /// [listener] 监听器回调函数，参数为 (key, newValue)
  void addChangeListener(Function(String key, dynamic newValue) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
      if (kDebugMode) {
        print('[PreferencesMonitor] 添加监听器，当前监听器数量: ${_listeners.length}');
      }
    }
  }

  /// 移除变更监听器
  void removeChangeListener(Function(String key, dynamic newValue) listener) {
    _listeners.remove(listener);
    if (kDebugMode) {
      print('[PreferencesMonitor] 移除监听器，当前监听器数量: ${_listeners.length}');
    }
  }

  /// 检查是否正在监控
  bool get isMonitoring => _monitorTimer != null && _monitorTimer!.isActive;
}

