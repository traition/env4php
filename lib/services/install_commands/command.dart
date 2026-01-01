import 'dart:io';

/// 安装命令接口
/// 所有安装命令必须实现此接口
abstract class Command {
  /// 命令名称（小写）
  String get name;

  /// 执行命令
  /// [context] 命令执行上下文
  /// 返回 (是否成功, 错误信息)
  Future<(bool success, String? error)> execute(CommandContext context);
}

/// 命令执行上下文
/// 包含执行命令所需的所有上下文信息
class CommandContext {
  /// 原始命令字符串
  final String command;

  /// 命令参数（已解析）
  final List<String> args;

  /// 下载的文件路径
  final String downloadPath;

  /// 软件安装目录
  final String softwareDir;

  /// 临时解压目录
  final String tempDir;

  /// 存储根目录
  final String storagePath;

  /// 软件类别
  final String category;

  /// 当前工作目录（可能被命令修改）
  String currentWorkDir;

  /// 当前临时目录（可能被命令修改）
  Directory? currentTempDir;

  /// 已执行的 Addbin2Path 添加的路径列表
  final List<String> addedPaths;

  /// 进度回调
  final Function(String step, double progress, String? logMessage)? onProgress;

  /// 当前命令的进度（0.0-1.0）
  final double progress;

  CommandContext({
    required this.command,
    required this.args,
    required this.downloadPath,
    required this.softwareDir,
    required this.tempDir,
    required this.storagePath,
    required this.category,
    required this.currentWorkDir,
    this.currentTempDir,
    required this.addedPaths,
    this.onProgress,
    required this.progress,
  });
}

