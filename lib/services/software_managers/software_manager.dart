import '../../models/software_model.dart';

/// 软件管理器接口
/// 定义所有软件类型必须实现的基本操作
abstract class SoftwareManager {
  /// 获取支持的软件类型标识（cate4 值，小写）
  String get supportedCate4;

  /// 启动软件
  /// [server] 软件信息
  /// 返回 (是否成功, 错误信息)
  Future<(bool success, String? error)> start(Software server);

  /// 停止软件（静默模式，不显示通知）
  /// [server] 软件信息
  /// 返回 (是否成功, 错误信息)
  Future<(bool success, String? error)> stopSilently(Software server);

  /// 停止软件（显示通知）
  /// [server] 软件信息
  /// 返回 (是否成功, 错误信息)
  Future<(bool success, String? error)> stop(Software server);

  /// 重启软件
  /// [server] 软件信息
  /// 返回 (是否成功, 错误信息)
  Future<(bool success, String? error)> restart(Software server);
}

/// 支持初始化的软件管理器接口
/// 在安装完成后需要进行额外初始化步骤的软件实现此接口
abstract class InitializableSoftwareManager extends SoftwareManager {
  /// 初始化软件（在安装完成后调用）
  /// [softwareDir] 软件安装目录
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息)
  Future<(bool success, String? error)> initialize(
    String softwareDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  });
}

