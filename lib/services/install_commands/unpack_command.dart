import 'dart:io';
import 'package:path/path.dart' as path;
import '../extract_service.dart';
import 'base_command.dart';
import 'command.dart';

/// 解压缩命令
/// 解压缩文件至临时目录
class UnpackCommand extends BaseCommand {
  @override
  String get name => 'unpack';

  @override
  Future<(bool success, String? error)> execute(CommandContext context) async {
    // 检查临时目录是否在存储目录内
    final normalizedTempDir = path.normalize(path.absolute(context.tempDir));
    if (!isPathWithinStorage(normalizedTempDir, context.storagePath)) {
      return (false, '临时目录超出存储目录范围: $normalizedTempDir');
    }

    final tempDirectory = Directory(context.tempDir);
    // 不删除原有内容，只确保目录存在（覆盖解压，保留原有文件）
    if (!await tempDirectory.exists()) {
      await tempDirectory.create(recursive: true);
    }
    context.currentTempDir = tempDirectory;
    context.currentWorkDir = context.tempDir;

    final extractSuccess = await ExtractService.extractFile(
      context.downloadPath,
      context.tempDir,
    );

    if (!extractSuccess) {
      return (false, '解压失败');
    }

    context.onProgress?.call('正在执行安装指令...', context.progress, '解压完成');
    return (true, null);
  }
}

