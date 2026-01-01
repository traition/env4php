import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/download_service.dart';
import '../services/extract_service.dart';
import '../services/software_source_service.dart';
import '../services/software_managers/software_manager_factory.dart';
import '../services/software_managers/software_manager.dart';
import '../services/install_commands/command.dart';
import '../services/install_commands/command_factory.dart';
import '../services/install_commands/command_helper.dart';

/// 安装服务
class InstallService {
  /// 安装结果
  static const String errorMainDownloadFailed = '主安装包下载失败';
  static const String errorExtractFailed = '解压失败';
  static const String errorAttachmentDownloadFailed = '附件下载失败';
  static const String errorHashMismatch = '哈希校验失败';
  static const String statusHashMismatch = 'HASH_MISMATCH'; // 需要用户确认的状态

  /// 计算文件的 XXH64 哈希值（使用 7za.exe）
  static Future<String> calculateXxh64(
    String filePath, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    try {
      // 获取 7za.exe 路径（软件目录下的 assets\7z\7za_2501.exe）
      final exePath = await ExtractService.get7zaPath();
      return await _calculateHashWith7za(
        exePath,
        filePath,
        onProgress: onProgress,
      );
    } catch (e) {
      throw Exception('计算哈希值失败: $e');
    }
  }

  /// 使用 7za.exe 计算文件哈希值
  static Future<String> _calculateHashWith7za(
    String exePath,
    String filePath, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 7za h -scrcxxh64 "文件路径"
      // 注意：参数应该是小写的 xxh64
      final result = await Process.run(exePath, [
        'h',
        '-scrcxxh64',
        filePath,
      ], runInShell: true);

      // 在 debug 模式下输出 7za 的完整输出
      if (kDebugMode) {
        final stdout = result.stdout.toString();
        final stderr = result.stderr.toString();

        if (stdout.isNotEmpty) {
          // 将输出按行分割并逐行输出
          final lines = stdout.split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty) {
              onProgress?.call('正在验证文件完整性...', 0.45, '[7za] $trimmed');
            }
          }
        }

        if (stderr.isNotEmpty) {
          final lines = stderr.split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty) {
              onProgress?.call('正在验证文件完整性...', 0.45, '[7za stderr] $trimmed');
            }
          }
        }
      }

      if (result.exitCode != 0) {
        // 如果 XXH64 不支持，检查错误信息
        final errorOutput = result.stderr.toString();
        if (errorOutput.toLowerCase().contains('unsupported') ||
            errorOutput.toLowerCase().contains('unknown') ||
            errorOutput.toLowerCase().contains('invalid')) {
          throw Exception('7za 不支持 XXH64 算法。请检查 7za 版本或使用其他哈希算法。');
        }
        throw Exception('7za 计算哈希值失败: $errorOutput');
      }

      // 解析输出，提取哈希值
      final output = result.stdout.toString();
      final hash = _parseHashFrom7zaOutput(
        output,
        16,
      ); // XXH64 是 64 位，即 16 个十六进制字符

      if (hash.isEmpty) {
        throw Exception('无法从 7za 输出中解析哈希值。输出: $output');
      }

      return hash.toUpperCase();
    } catch (e) {
      if (e.toString().contains('不支持')) {
        rethrow; // 重新抛出不支持的错误
      }
      throw Exception('执行 7za 命令失败: $e');
    }
  }

  /// 从 7za 输出中解析哈希值
  /// 输出格式示例：
  /// XXH64  for data:              494933485A08B45B
  static String _parseHashFrom7zaOutput(String output, int expectedLength) {
    final lines = output.split('\n');

    // 优先查找 "XXH64  for data:" 这一行
    for (final line in lines) {
      final trimmed = line.trim();

      // 查找 "XXH64  for data:" 或 "XXH64 for data:" 行
      if (trimmed.toLowerCase().contains('xxh64') &&
          trimmed.toLowerCase().contains('for data')) {
        // 提取这一行中的哈希值（16个十六进制字符）
        final hashPattern = RegExp(
          r'([0-9A-Fa-f]{' + expectedLength.toString() + r'})',
        );
        final match = hashPattern.firstMatch(trimmed);
        if (match != null) {
          return match.group(1)!;
        }
      }
    }

    // 如果没找到 "for data" 行，查找包含哈希值的表格行
    // 格式：494933485A08B45B     334929717  postgresql-18.1-1-windows-x64-binaries.zip
    for (final line in lines) {
      final trimmed = line.trim();

      // 跳过标题行和错误信息
      if (trimmed.isEmpty ||
          trimmed.toLowerCase().contains('scanning') ||
          trimmed.toLowerCase().contains('error') ||
          trimmed.toLowerCase().contains('7-zip') ||
          trimmed.toLowerCase().contains('creating') ||
          trimmed.toLowerCase().startsWith('scanning') ||
          trimmed.startsWith('--') ||
          trimmed.toLowerCase().contains('size') &&
              trimmed.toLowerCase().contains('name')) {
        continue;
      }

      // 尝试提取连续的十六进制字符（应该是第一个匹配的）
      final hashPattern = RegExp(
        r'^([0-9A-Fa-f]{' + expectedLength.toString() + r'})',
      );
      final match = hashPattern.firstMatch(trimmed);
      if (match != null) {
        return match.group(1)!;
      }

      // 如果没找到完整匹配，尝试从行中提取所有十六进制字符
      final hexChars = trimmed.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (hexChars.length >= expectedLength) {
        // 取前 expectedLength 个字符（哈希值通常在开头）
        return hexChars.substring(0, expectedLength);
      }
    }

    // 如果都没找到，尝试从所有输出中提取
    final allHex = output.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (allHex.length >= expectedLength) {
      // 取最后 expectedLength 个字符
      return allHex.substring(allHex.length - expectedLength);
    }

    return '';
  }

  /// 更新 php.bat 文件中的 PHP 路径
  /// [phpDir] PHP 安装目录路径
  /// [storagePath] 存储目录路径
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> updatePhpBat(
    String phpDir,
    String storagePath, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
      final phpBatFile = File(phpBatPath);

      if (!await phpBatFile.exists()) {
        return (false, 'php.bat 文件不存在: $phpBatPath');
      }

      // 读取文件内容
      String content = await phpBatFile.readAsString();

      // 匹配 "任意字符php.exe" 的模式（使用正则表达式）
      // 匹配模式：".*php.exe" 或 '.*php.exe'
      final pattern = RegExp(r'''["'].*php\.exe["']''');

      if (!pattern.hasMatch(content)) {
        return (false, '无法在 php.bat 中找到匹配的模式');
      }

      // 获取 PHP 的路径
      final phpExePath = path.join(phpDir, 'php.exe');
      // 确保路径使用反斜杠（Windows 风格）
      final normalizedPhpPath = phpExePath.replaceAll('/', '\\');

      // 替换匹配的内容
      final newContent = content.replaceAll(pattern, '"$normalizedPhpPath"');

      // 写回文件
      await phpBatFile.writeAsString(newContent);

      onProgress?.call('更新 php.bat', 1.0, '已更新 php.bat 中的 PHP 路径');
      return (true, null);
    } catch (e) {
      return (false, '更新 php.bat 失败: $e');
    }
  }

  /// 安装软件
  /// [software] 软件信息
  /// [category] 软件类别 (servers, databases, php, tools)
  /// [onProgress] 进度回调 (当前步骤, 进度百分比, 日志消息)
  /// [userConfirmedHashMismatch] 用户是否确认继续安装（当哈希不匹配时）
  /// [cancellationToken] 取消令牌，用于取消下载
  /// 返回 (是否成功, 错误信息或状态, 计算出的XXH64哈希值)
  static Future<(bool success, String? error, String? calculatedHash)>
  installSoftware(
    Software software,
    String category, {
    Function(String step, double progress, String? logMessage)? onProgress,
    bool userConfirmedHashMismatch = false,
    bool Function()? cancellationToken,
  }) async {
    String? downloadPath;
    File? downloadFile;
    Directory? softwareDir;
    Directory? softwareSourceDir;
    String? calculatedHash;

    try {
      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) {
        return (false, '存储目录未设置', null);
      }

      // 步骤0: 检查存储空间
      final requiredSpace = (software.byte * 1.8).round(); // 需要 1.8 倍的空间
      final spaceCheck = await _checkAvailableSpace(storagePath, requiredSpace);
      if (!spaceCheck.$1) {
        final neededMB = (spaceCheck.$2 / 1024 / 1024).toStringAsFixed(2);
        return (false, '存储空间不足，需要额外 ${neededMB}MB 空间', null);
      }

      // 步骤1: 下载主安装包
      final fileName = path.basename(Uri.parse(software.downloadURL).path);
      downloadPath = '$storagePath/$category/$fileName';
      downloadFile = File(downloadPath);

      // 如果文件已存在且用户已确认哈希不匹配，跳过下载
      final fileExists = await downloadFile.exists();
      if (fileExists && userConfirmedHashMismatch) {
        onProgress?.call('跳过下载', 0.4, '文件已存在，跳过下载步骤');
      } else {
        onProgress?.call('正在下载安装包...', 0.1, '开始下载: ${software.downloadURL}');
        final categoryDir = Directory('$storagePath/$category');
        if (!await categoryDir.exists()) {
          await categoryDir.create(recursive: true);
        }

        // 如果文件已存在，删除它（覆盖）
        if (fileExists) {
          await downloadFile.delete();
        }

        final downloadResult = await DownloadService.downloadFile(
          software.downloadURL,
          downloadPath,
          cancellationToken: cancellationToken,
          onProgress: (downloaded, total) {
            if (total > 0) {
              final progress = 0.1 + (downloaded / total) * 0.3;
              final downloadedMB = (downloaded / 1024 / 1024).toStringAsFixed(
                2,
              );
              final totalMB = (total / 1024 / 1024).toStringAsFixed(2);
              final percentage = ((downloaded / total) * 100).toStringAsFixed(
                1,
              );
              // 使用特殊标记表示这是进度更新消息，需要替换而不是追加
              onProgress?.call(
                '正在下载安装包...',
                progress,
                'PROGRESS_UPDATE:已下载: $downloadedMB MB / $totalMB MB ($percentage%)',
              );
            }
          },
        );

        final downloadSuccess = downloadResult.$1;
        final downloadError = downloadResult.$2;

        // 检查是否被取消
        if (cancellationToken != null && cancellationToken()) {
          // 删除下载文件
          await _deleteFileWithRetry(downloadPath);
          return (false, '下载已取消', null);
        }

        if (!downloadSuccess) {
          // 输出错误信息
          onProgress?.call(
            '下载失败',
            0.4,
            '错误: ${downloadError ?? errorMainDownloadFailed}',
          );
          // 清除下载文件痕迹（使用重试机制）
          await _deleteFileWithRetry(downloadPath);
          return (false, downloadError ?? errorMainDownloadFailed, null);
        }

        onProgress?.call('下载完成', 0.4, '下载完成: $downloadPath');
      }

      // 步骤1.5: 验证哈希值（如果提供了）
      if (software.xxh64 != null && software.xxh64!.isNotEmpty) {
        onProgress?.call('正在验证文件完整性...', 0.4, '正在计算 XXH64 哈希值...');
        try {
          calculatedHash = await calculateXxh64(
            downloadPath,
            onProgress: onProgress,
          );
          final expectedHash = software.xxh64!.toUpperCase();

          onProgress?.call('正在验证文件完整性...', 0.45, 'XXH64: $calculatedHash');
          onProgress?.call('正在验证文件完整性...', 0.45, '预期值: $expectedHash');

          if (calculatedHash != expectedHash) {
            onProgress?.call('正在验证文件完整性...', 0.45, '警告: 哈希值不匹配！');
            // 哈希不匹配
            if (!userConfirmedHashMismatch) {
              // 用户未确认，删除下载文件并返回特殊状态
              await _deleteFileWithRetry(downloadPath);
              return (false, statusHashMismatch, calculatedHash);
            }
            // 用户已确认继续，继续安装流程
            onProgress?.call('正在验证文件完整性...', 0.45, '用户已确认继续安装');
          } else {
            // 哈希匹配，继续安装
            onProgress?.call('正在验证文件完整性...', 0.45, '哈希值验证通过');
          }
        } catch (e) {
          // 哈希计算失败，清除下载文件
          await _deleteFileWithRetry(downloadPath);
          return (false, '哈希验证失败: $e', null);
        }
      }

      // 步骤2: 根据 commands 数组决定安装流程
      softwareDir = Directory('$storagePath/$category/${software.id}');
      if (await softwareDir.exists()) {
        // 如果已存在，删除（覆盖）
        await softwareDir.delete(recursive: true);
      }

      // 创建软件目录
      await softwareDir.create(recursive: true);

      // PHP 特殊处理：重写安装逻辑
      if (category == 'php') {
        return await _installPhp(
          software,
          downloadPath,
          softwareDir,
          storagePath,
          calculatedHash: calculatedHash,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      }

      // 检查 commands 数组是否为空
      if (software.commands.isEmpty) {
        // commands 为空：直接解压到软件 id 目录
        onProgress?.call('正在解压...', 0.5, '开始解压安装包到软件目录...');
        final extractSuccess = await ExtractService.extractFile(
          downloadPath,
          softwareDir.path,
        );

        if (!extractSuccess) {
          // 解压失败，删除下载文件和软件目录
          await _deleteFileWithRetry(downloadPath);
          if (await softwareDir.exists()) {
            await _deleteDirectoryWithRetry(softwareDir.path);
          }
          return (false, errorExtractFailed, calculatedHash);
        }

        onProgress?.call('解压完成', 0.6, '文件解压完成。');
      } else {
        // commands 不为空：按顺序执行命令
        onProgress?.call('正在执行安装指令...', 0.5, '开始执行安装指令...');
        final tempDir = '$storagePath/$category/.7ztemp';

        try {
          final commandResult = await _executeCommands(
            software.commands,
            downloadPath,
            softwareDir.path,
            tempDir,
            storagePath,
            category,
            onProgress,
          );

          if (!commandResult.$1) {
            // 命令执行失败，删除下载文件和软件目录
            await _deleteFileWithRetry(downloadPath);
            if (await softwareDir.exists()) {
              await _deleteDirectoryWithRetry(softwareDir.path);
            }
            return (false, commandResult.$2 ?? '命令执行失败', calculatedHash);
          }

          onProgress?.call('指令执行完成', 0.6, '所有安装指令已执行完成。');
        } catch (e) {
          // 执行安装指令时发生错误，删除下载文件和软件目录
          await _deleteFileWithRetry(downloadPath);
          if (await softwareDir.exists()) {
            await _deleteDirectoryWithRetry(softwareDir.path);
          }
          return (false, '执行安装指令时发生错误: $e', calculatedHash);
        }
      }

      // 步骤3: 处理附件
      if (software.attachments.isNotEmpty) {
        onProgress?.call(
          '正在下载附件...',
          0.7,
          '开始下载附件 (${software.attachments.length} 个)...',
        );

        // 先创建 sources 目录结构（如果有附件）
        final sourcesDir = Directory('$storagePath/sources');
        if (!await sourcesDir.exists()) {
          await sourcesDir.create(recursive: true);
        }
        softwareSourceDir = Directory('$storagePath/sources/${software.id}');
        if (!await softwareSourceDir.exists()) {
          await softwareSourceDir.create(recursive: true);
        }

        for (int i = 0; i < software.attachments.length; i++) {
          final attachment = software.attachments[i];
          final progress = 0.7 + (i / software.attachments.length) * 0.2;
          final attachmentFileName = path.basename(
            Uri.parse(attachment.downloadURL).path,
          );
          onProgress?.call(
            '正在下载附件 ${i + 1}/${software.attachments.length}...',
            progress,
            '下载附件: $attachmentFileName',
          );
          final attachmentPath = '${softwareDir.path}/$attachmentFileName';

          // 如果文件已存在，删除它（覆盖）
          final attachmentFile = File(attachmentPath);
          if (await attachmentFile.exists()) {
            await attachmentFile.delete();
          }

          // 下载附件
          final attachmentResult = await DownloadService.downloadFile(
            attachment.downloadURL,
            attachmentPath,
            cancellationToken: cancellationToken,
          );

          final attachmentDownloadSuccess = attachmentResult.$1;
          final attachmentError = attachmentResult.$2;

          // 检查是否被取消
          if (cancellationToken != null && cancellationToken()) {
            // 附件下载失败，清除所有痕迹
            // 等待一小段时间确保资源释放
            await Future.delayed(const Duration(milliseconds: 100));
            // 1. 删除软件目录
            await _deleteDirectoryWithRetry(softwareDir.path);
            // 2. 删除 sources 目录
            await _deleteDirectoryWithRetry(softwareSourceDir.path);
            // 3. 删除主安装包
            await _deleteFileWithRetry(downloadPath);
            return (false, '下载已取消', calculatedHash);
          }

          if (!attachmentDownloadSuccess) {
            // 输出错误信息
            onProgress?.call(
              '附件下载失败',
              progress,
              '错误: ${attachmentError ?? errorAttachmentDownloadFailed}',
            );
            // 附件下载失败，清除所有痕迹
            // 1. 删除软件目录
            if (await softwareDir.exists()) {
              try {
                await softwareDir.delete(recursive: true);
              } catch (e) {
                // 忽略删除错误
              }
            }
            // 2. 删除 sources 目录
            if (await softwareSourceDir.exists()) {
              try {
                await softwareSourceDir.delete(recursive: true);
              } catch (e) {
                // 忽略删除错误
              }
            }
            // 3. 删除主安装包
            if (await downloadFile.exists()) {
              try {
                await downloadFile.delete();
              } catch (e) {
                // 忽略删除错误
              }
            }
            return (
              false,
              attachmentError ?? errorAttachmentDownloadFailed,
              calculatedHash,
            );
          }

          // 先保存附件到 sources（在执行 commands 之前）
          final attachmentSourcePath =
              '${softwareSourceDir.path}/$attachmentFileName';
          final attachmentSourceFile = File(attachmentSourcePath);
          if (await attachmentSourceFile.exists()) {
            await attachmentSourceFile.delete();
          }
          await attachmentFile.copy(attachmentSourcePath);

          // 执行附件的 commands（如果存在）
          if (attachment.commands.isNotEmpty) {
            onProgress?.call(
              '正在处理附件 ${i + 1}/${software.attachments.length}...',
              progress,
              '开始执行附件指令...',
            );

            // 为附件创建临时解压目录（使用与主安装包相同的 .7ztemp 目录结构）
            // 使用存储目录下的 .7ztemp，与主安装包保持一致
            final attachmentTempDir = '$storagePath/$category/.7ztemp';
            final attachmentTempDirectory = Directory(attachmentTempDir);

            try {
              // 对于附件，需要特殊处理：unpack 解压到临时目录，但其他命令（如 Addir2Path）应该相对于软件目录
              // 所以我们需要在执行命令时，将 currentWorkDir 设置为软件目录
              final attachmentCommandResult = await _executeAttachmentCommands(
                attachment.commands,
                attachmentPath,
                softwareDir.path, // 附件的工作目录是软件目录
                attachmentTempDir,
                storagePath,
                category,
                onProgress,
              );

              if (!attachmentCommandResult.$1) {
                // 附件命令执行失败，按照用户取消下载来处理
                // 撤销已执行的 Addbin2Path（已在 _executeAttachmentCommands 中处理）
                onProgress?.call(
                  '附件处理失败',
                  progress,
                  '错误: ${attachmentCommandResult.$2 ?? "附件命令执行失败"}',
                );
                // 清除下载痕迹
                await Future.delayed(const Duration(milliseconds: 100));
                // 1. 删除软件目录
                if (await softwareDir.exists()) {
                  await _deleteDirectoryWithRetry(softwareDir.path);
                }
                // 2. 删除 sources 目录
                if (await softwareSourceDir.exists()) {
                  await _deleteDirectoryWithRetry(softwareSourceDir.path);
                }
                // 3. 删除主安装包
                if (await downloadFile.exists()) {
                  await _deleteFileWithRetry(downloadFile.path);
                }
                // 4. 清理附件临时目录
                if (await attachmentTempDirectory.exists()) {
                  await _deleteDirectoryWithRetry(attachmentTempDirectory.path);
                }
                // 5. 删除附件文件
                if (await attachmentFile.exists()) {
                  await _deleteFileWithRetry(attachmentFile.path);
                }
                // 中断安装流程
                return (
                  false,
                  attachmentCommandResult.$2 ?? '附件命令执行失败',
                  calculatedHash,
                );
              }

              onProgress?.call('附件处理完成', progress, '附件 ${i + 1} 处理完成');

              // 清理附件临时目录（如果还存在）
              if (await attachmentTempDirectory.exists()) {
                await _deleteDirectoryWithRetry(attachmentTempDirectory.path);
              }
            } catch (e) {
              // 附件命令执行失败，按照用户取消下载来处理
              onProgress?.call('附件处理失败', progress, '错误: $e');
              // 清除下载痕迹
              await Future.delayed(const Duration(milliseconds: 100));
              // 1. 删除软件目录
              if (await softwareDir.exists()) {
                await _deleteDirectoryWithRetry(softwareDir.path);
              }
              // 2. 删除 sources 目录
              if (await softwareSourceDir.exists()) {
                await _deleteDirectoryWithRetry(softwareSourceDir.path);
              }
              // 3. 删除主安装包
              if (await downloadFile.exists()) {
                await _deleteFileWithRetry(downloadFile.path);
              }
              // 4. 清理附件临时目录
              if (await attachmentTempDirectory.exists()) {
                await _deleteDirectoryWithRetry(attachmentTempDirectory.path);
              }
              // 5. 删除附件文件
              if (await attachmentFile.exists()) {
                await _deleteFileWithRetry(attachmentFile.path);
              }
              // 中断安装流程
              return (false, '附件处理时发生错误: $e', calculatedHash);
            }
          } else {
            // 如果没有 commands，使用默认解压逻辑
            final attachmentExt = DownloadService.getFileExtension(
              attachment.downloadURL,
            );
            if ([
              '.zip',
              '.7z',
              '.tar',
              '.gz',
              '.bz2',
            ].contains(attachmentExt)) {
              await ExtractService.extractFile(
                attachmentPath,
                softwareDir.path,
              );
              // 删除压缩包
              await attachmentFile.delete();
            }
          }
        }
      }

      // 步骤4: 保存安装包到 sources 目录
      onProgress?.call('正在保存安装包...', 0.95, '正在保存安装包到 sources 目录...');
      final sourcesDir = Directory('$storagePath/sources');
      if (!await sourcesDir.exists()) {
        await sourcesDir.create(recursive: true);
      }

      if (software.attachments.isNotEmpty) {
        // 有附件，创建软件 id 文件夹
        final softwareSourceDirForMain = Directory(
          '$storagePath/sources/${software.id}',
        );
        if (!await softwareSourceDirForMain.exists()) {
          await softwareSourceDirForMain.create(recursive: true);
        }

        // 复制主安装包
        final sourceMainFile = File(
          '${softwareSourceDirForMain.path}/$fileName',
        );
        if (await sourceMainFile.exists()) {
          await sourceMainFile.delete();
        }
        await downloadFile.copy(sourceMainFile.path);

        // 附件已经在步骤3中保存到 sources 了，这里不需要再处理
      } else {
        // 没有附件，直接保存到 sources 目录
        final sourceFile = File('$storagePath/sources/$fileName');
        if (await sourceFile.exists()) {
          await sourceFile.delete();
        }
        await downloadFile.copy(sourceFile.path);
      }

      // 检查 commands 中是否有 skip 指令
      final hasSkipCommand = software.commands.any(
        (cmd) => cmd.trim().toLowerCase() == 'skip',
      );

      // 如果有 skip 指令，不删除下载的文件，只复制到 sources
      // 如果没有 skip 指令，删除下载的临时文件
      if (!hasSkipCommand) {
        if (await downloadFile.exists()) {
          await downloadFile.delete();
        }
      }

      // MySQL 特殊处理：初始化数据库并清理注册表
      if (software.cate4 != null && software.cate4!.toLowerCase() == 'mysql') {
        onProgress?.call('正在初始化 MySQL...', 0.98, '开始初始化 MySQL 数据库...');
        final manager = SoftwareManagerFactory.getManager(software);
        if (manager != null && manager is InitializableSoftwareManager) {
          final mysqlInitResult = await manager.initialize(
            softwareDir.path,
            onProgress: onProgress,
          );
          if (!mysqlInitResult.$1) {
            // MySQL 初始化失败，但不影响安装成功（因为文件已安装）
            onProgress?.call(
              'MySQL 初始化警告',
              0.99,
              '警告: ${mysqlInitResult.$2 ?? "MySQL 初始化失败，但安装已完成"}',
            );
          } else {
            onProgress?.call('MySQL 初始化完成', 0.99, 'MySQL 数据库初始化完成');
          }
        }
      }

      // PostgreSQL 特殊处理：初始化数据库并注册服务
      if (software.cate4 != null && software.cate4!.toLowerCase() == 'pgsql') {
        onProgress?.call(
          '正在初始化 PostgreSQL...',
          0.98,
          '开始初始化 PostgreSQL 数据库...',
        );
        final manager = SoftwareManagerFactory.getManager(software);
        if (manager != null && manager is InitializableSoftwareManager) {
          final pgsqlInitResult = await manager.initialize(
            softwareDir.path,
            onProgress: onProgress,
          );
          if (!pgsqlInitResult.$1) {
            // PostgreSQL 初始化失败，但不影响安装成功（因为文件已安装）
            onProgress?.call(
              'PostgreSQL 初始化警告',
              0.99,
              '警告: ${pgsqlInitResult.$2 ?? "PostgreSQL 初始化失败，但安装已完成"}',
            );
          } else {
            onProgress?.call('PostgreSQL 初始化完成', 0.99, 'PostgreSQL 数据库初始化完成');
          }
        }
      }

      // MongoDB 特殊处理：注册服务并配置启动方式
      if (software.cate4 != null &&
          software.cate4!.toLowerCase() == 'mongodb') {
        onProgress?.call('正在初始化 MongoDB...', 0.98, '开始初始化 MongoDB 服务...');
        final manager = SoftwareManagerFactory.getManager(software);
        if (manager != null && manager is InitializableSoftwareManager) {
          final mongodbInitResult = await manager.initialize(
            softwareDir.path,
            onProgress: onProgress,
          );
          if (!mongodbInitResult.$1) {
            // MongoDB 初始化失败，但不影响安装成功（因为文件已安装）
            onProgress?.call(
              'MongoDB 初始化警告',
              0.99,
              '警告: ${mongodbInitResult.$2 ?? "MongoDB 初始化失败，但安装已完成"}',
            );
          } else {
            onProgress?.call('MongoDB 初始化完成', 0.99, 'MongoDB 服务初始化完成');
          }
        }
      }

      // phpMyAdmin 特殊处理：创建普通PHP项目
      if (software.cate4 != null &&
          software.cate4!.toLowerCase() == 'phpmyadmin') {
        onProgress?.call('正在初始化 phpMyAdmin...', 0.98, '开始创建 phpMyAdmin 项目...');
        final phpmyadminManager = SoftwareManagerFactory.getPhpmyadminManager();
        final phpmyadminInitResult = await phpmyadminManager.initialize(
          softwareDir.path,
          onProgress: onProgress,
        );
        if (!phpmyadminInitResult.$1) {
          // phpMyAdmin 初始化失败，删除下载文件和软件目录
          await _deleteFileWithRetry(downloadPath);
          if (await softwareDir.exists()) {
            await _deleteDirectoryWithRetry(softwareDir.path);
          }
          if (softwareSourceDir != null && await softwareSourceDir.exists()) {
            await _deleteDirectoryWithRetry(softwareSourceDir.path);
          }
          return (
            false,
            phpmyadminInitResult.$2 ?? 'phpMyAdmin 初始化失败',
            calculatedHash,
          );
        } else {
          onProgress?.call('phpMyAdmin 初始化完成', 0.99, 'phpMyAdmin 项目创建完成');
        }
      }

      onProgress?.call('安装完成', 1.0, '安装完成！');
      return (true, null, calculatedHash);
    } catch (e) {
      // 发生异常，清除所有痕迹
      // 等待一小段时间确保资源释放
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        if (downloadFile != null) {
          await _deleteFileWithRetry(downloadFile.path);
        }
        if (softwareDir != null) {
          await _deleteDirectoryWithRetry(softwareDir.path);
        }
        if (softwareSourceDir != null) {
          await _deleteDirectoryWithRetry(softwareSourceDir.path);
        }
      } catch (cleanupError) {
        // 忽略清理错误
      }
      return (false, '安装过程中发生错误: $e', null);
    }
  }

  /// 执行安装命令
  /// [commands] 命令列表
  /// [downloadPath] 下载的文件路径
  /// [softwareDir] 软件安装目录
  /// [tempDir] 临时解压目录
  /// [storagePath] 存储根目录
  /// [category] 软件类别
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息, 已执行的Addbin2Path路径列表)
  static Future<(bool success, String? error, List<String> addedPaths)>
  _executeCommands(
    List<String> commands,
    String downloadPath,
    String softwareDir,
    String tempDir,
    String storagePath,
    String category,
    Function(String step, double progress, String? logMessage)? onProgress,
  ) async {
    Directory? currentTempDir;
    String currentWorkDir = tempDir; // 当前工作目录（解压缓存目录）
    List<String> addedPaths = []; // 记录已执行的 Addbin2Path 添加的路径

    for (int i = 0; i < commands.length; i++) {
      final command = commands[i].trim();
      if (command.isEmpty) continue;

      final progress = 0.5 + (i / commands.length) * 0.1;
      onProgress?.call(
        '正在执行安装指令...',
        progress,
        '执行指令 ${i + 1}/${commands.length}: $command',
      );

      try {
        // 解析命令
        final parts = command.split(' ');
        final cmd = parts[0].toLowerCase();

        // 使用命令工厂获取命令实例
        final commandInstance = CommandFactory.getCommand(cmd);
        if (commandInstance == null) {
          await _rollbackAddedPaths(addedPaths, onProgress);
          return (false, '未知命令: $cmd', addedPaths);
        }

        // 创建命令上下文
        final context = CommandContext(
          command: command,
          args: parts,
          downloadPath: downloadPath,
          softwareDir: softwareDir,
          tempDir: tempDir,
          storagePath: storagePath,
          category: category,
          currentWorkDir: currentWorkDir,
          currentTempDir: currentTempDir,
          addedPaths: addedPaths,
          onProgress: onProgress,
          progress: progress,
        );

        // 执行命令
        final result = await commandInstance.execute(context);

        // 更新上下文状态
        currentWorkDir = context.currentWorkDir;
        currentTempDir = context.currentTempDir;
        addedPaths = context.addedPaths;

        // 检查执行结果
        if (!result.$1) {
          await _rollbackAddedPaths(addedPaths, onProgress);
          return (false, result.$2 ?? '命令执行失败', addedPaths);
        }

        // 处理 addbin2path 命令的特殊情况（需要记录添加的路径）
        if (cmd == 'addbin2path') {
          // 路径已在命令执行时添加到 addedPaths
        }
      } catch (e) {
        await _rollbackAddedPaths(addedPaths, onProgress);
        return (false, '执行命令 "$command" 时发生错误: $e', addedPaths);
      }
    }

    // 所有命令执行完成，将临时目录内容移动到软件目录（如果临时目录存在）
    if (currentTempDir != null && await currentTempDir.exists()) {
      // 将临时目录内容移动到软件目录
      await for (final entity in currentTempDir.list()) {
        final destPath = path.join(softwareDir, path.basename(entity.path));
        if (entity is Directory) {
          if (await Directory(destPath).exists()) {
            await Directory(destPath).delete(recursive: true);
          }
          await Directory(entity.path).rename(destPath);
        } else if (entity is File) {
          if (await File(destPath).exists()) {
            await File(destPath).delete();
          }
          await File(entity.path).rename(destPath);
        }
      }

      // 删除临时目录
      try {
        await currentTempDir.delete(recursive: true);
      } catch (e) {
        // 忽略删除错误
      }
    }

    return (true, null, addedPaths);
  }

  /// 执行附件命令（特殊处理：unpack 解压到临时目录，其他命令相对于软件目录）
  /// [commands] 命令列表
  /// [downloadPath] 下载的文件路径
  /// [softwareDir] 软件安装目录（作为工作目录基准）
  /// [tempDir] 临时解压目录
  /// [storagePath] 存储根目录
  /// [category] 软件类别
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息, 已执行的Addbin2Path路径列表)
  static Future<(bool success, String? error, List<String> addedPaths)>
  _executeAttachmentCommands(
    List<String> commands,
    String downloadPath,
    String softwareDir,
    String tempDir,
    String storagePath,
    String category,
    Function(String step, double progress, String? logMessage)? onProgress,
  ) async {
    Directory? currentTempDir;
    String currentWorkDir = tempDir; // 初始工作目录为临时目录（用于 unpack）
    List<String> addedPaths = []; // 记录已执行的 Addbin2Path 添加的路径

    for (int i = 0; i < commands.length; i++) {
      final command = commands[i].trim();
      if (command.isEmpty) continue;

      final progress = 0.7 + (i / commands.length) * 0.1;
      onProgress?.call(
        '正在执行附件指令...',
        progress,
        '执行附件指令 ${i + 1}/${commands.length}: $command',
      );

      try {
        // 解析命令
        final parts = command.split(' ');
        final cmd = parts[0].toLowerCase();

        // 使用命令工厂获取命令实例
        final commandInstance = CommandFactory.getCommand(cmd);
        if (commandInstance == null) {
          await _rollbackAddedPaths(addedPaths, onProgress);
          return (false, '未知命令: $cmd', addedPaths);
        }

        // 创建命令上下文（附件命令的特殊处理）
        final context = CommandContext(
          command: command,
          args: parts,
          downloadPath: downloadPath,
          softwareDir: softwareDir,
          tempDir: tempDir,
          storagePath: storagePath,
          category: category,
          currentWorkDir: currentWorkDir,
          currentTempDir: currentTempDir,
          addedPaths: addedPaths,
          onProgress: onProgress,
          progress: progress,
        );

        // 执行命令（附件命令需要特殊处理路径解析）
        final result = await commandInstance.execute(context);

        // 更新上下文状态
        currentWorkDir = context.currentWorkDir;
        currentTempDir = context.currentTempDir;
        addedPaths = context.addedPaths;

        // 检查执行结果
        if (!result.$1) {
          await _rollbackAddedPaths(addedPaths, onProgress);
          return (false, result.$2 ?? '命令执行失败', addedPaths);
        }
      } catch (e) {
        await _rollbackAddedPaths(addedPaths, onProgress);
        return (false, '执行命令 "$command" 时发生错误: $e', addedPaths);
      }
    }

    return (true, null, addedPaths);
  }

  /// 撤销已添加到 PATH 的路径
  static Future<void> _rollbackAddedPaths(
    List<String> addedPaths,
    Function(String step, double progress, String? logMessage)? onProgress,
  ) async {
    await CommandHelper.rollbackAddedPaths(addedPaths, onProgress);
  }

  /// 删除文件（带重试机制）
  static Future<void> _deleteFileWithRetry(
    String filePath, {
    int maxRetries = 5,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          return; // 删除成功
        }
        return; // 文件不存在，无需删除
      } catch (e) {
        if (i < maxRetries - 1) {
          // 等待后重试，每次等待时间递增
          await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
        } else {
          // 最后一次尝试失败，忽略错误
        }
      }
    }
  }

  /// 删除目录（带重试机制）
  static Future<void> _deleteDirectoryWithRetry(
    String dirPath, {
    int maxRetries = 5,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          return; // 删除成功
        }
        return; // 目录不存在，无需删除
      } catch (e) {
        if (i < maxRetries - 1) {
          // 等待后重试，每次等待时间递增
          await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
        } else {
          // 最后一次尝试失败，忽略错误
        }
      }
    }
  }

  /// 检查目录的可用空间
  /// [dirPath] 目录路径
  /// [requiredBytes] 需要的字节数
  /// 返回 (是否有足够空间, 缺少的字节数)
  static Future<(bool hasEnoughSpace, int missingBytes)> _checkAvailableSpace(
    String dirPath,
    int requiredBytes,
  ) async {
    try {
      // 在 Windows 上使用 fsutil 命令获取可用空间
      // fsutil volume diskfree <路径>
      final result = await Process.run('fsutil', [
        'volume',
        'diskfree',
        dirPath,
      ], runInShell: true);

      if (result.exitCode == 0) {
        // 解析输出，格式类似：
        // Total free bytes        : 1234567890
        // Total bytes             : 9876543210
        // Total available bytes   : 1234567890
        final output = result.stdout.toString();
        final lines = output.split('\n');

        int? availableBytes;
        for (final line in lines) {
          if (line.toLowerCase().contains('total available bytes') ||
              line.toLowerCase().contains('total free bytes')) {
            // 提取数字
            final match = RegExp(r':\s*(\d+)').firstMatch(line);
            if (match != null) {
              availableBytes = int.tryParse(match.group(1)!);
              break;
            }
          }
        }

        if (availableBytes != null) {
          if (availableBytes >= requiredBytes) {
            return (true, 0);
          } else {
            return (false, requiredBytes - availableBytes);
          }
        }
      }

      // 如果 fsutil 失败，尝试使用 wmic（Windows Management Instrumentation）
      // 获取目录所在驱动器的可用空间
      final driveLetter = dirPath.substring(0, 2); // 例如 "C:"
      final wmicResult = await Process.run('wmic', [
        'logicaldisk',
        'where',
        'name="$driveLetter"',
        'get',
        'freespace',
        '/format:value',
      ], runInShell: true);

      if (wmicResult.exitCode == 0) {
        final output = wmicResult.stdout.toString();
        final match = RegExp(r'FreeSpace=(\d+)').firstMatch(output);
        if (match != null) {
          final availableBytes = int.tryParse(match.group(1)!);
          if (availableBytes != null) {
            if (availableBytes >= requiredBytes) {
              return (true, 0);
            } else {
              return (false, requiredBytes - availableBytes);
            }
          }
        }
      }

      // 如果都失败了，假设空间足够（避免阻止下载）
      return (true, 0);
    } catch (e) {
      // 如果检查失败，假设空间足够（避免阻止下载）
      return (true, 0);
    }
  }

  /// PHP 专用安装逻辑
  /// [software] PHP 软件信息
  /// [downloadPath] 下载的安装包路径
  /// [softwareDir] 软件安装目录
  /// [storagePath] 存储目录
  /// [calculatedHash] 计算出的哈希值
  /// [onProgress] 进度回调
  /// [cancellationToken] 取消令牌
  /// 返回 (是否成功, 错误信息或状态, 计算出的XXH64哈希值)
  static Future<(bool success, String? error, String? calculatedHash)>
  _installPhp(
    Software software,
    String downloadPath,
    Directory softwareDir,
    String storagePath, {
    String? calculatedHash,
    Function(String step, double progress, String? logMessage)? onProgress,
    bool Function()? cancellationToken,
  }) async {
    try {
      // 步骤3: 解压至名为软件id的文件夹
      onProgress?.call('正在解压...', 0.5, '开始解压安装包到软件目录...');
      final extractSuccess = await ExtractService.extractFile(
        downloadPath,
        softwareDir.path,
      );

      if (!extractSuccess) {
        await _deleteFileWithRetry(downloadPath);
        return (false, errorExtractFailed, calculatedHash);
      }

      onProgress?.call('解压完成', 0.6, '文件解压完成。');

      // 步骤4: 下载 php-cgi-spawner
      final softwareSource = await SoftwareSourceService.getSource();
      if (softwareSource == null || softwareSource.phpCgiSpawner == null) {
        await _deleteFileWithRetry(downloadPath);
        if (await softwareDir.exists()) {
          await softwareDir.delete(recursive: true);
        }
        return (false, '无法获取 php-cgi-spawner 下载地址', calculatedHash);
      }

      onProgress?.call(
        '正在下载 php-cgi-spawner...',
        0.65,
        '开始下载 php-cgi-spawner...',
      );
      final spawnerFileName = path.basename(
        Uri.parse(softwareSource.phpCgiSpawner!).path,
      );
      final spawnerPath = path.join(softwareDir.path, spawnerFileName);
      final spawnerFile = File(spawnerPath);

      if (await spawnerFile.exists()) {
        await spawnerFile.delete();
      }

      final spawnerDownloadResult = await DownloadService.downloadFile(
        softwareSource.phpCgiSpawner!,
        spawnerPath,
        cancellationToken: cancellationToken,
        onProgress: (downloaded, total) {
          if (total > 0) {
            final progress = 0.65 + (downloaded / total) * 0.05;
            onProgress?.call(
              '正在下载 php-cgi-spawner...',
              progress,
              '已下载: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB / ${(total / 1024 / 1024).toStringAsFixed(2)} MB',
            );
          }
        },
      );

      if (!spawnerDownloadResult.$1) {
        await _deleteFileWithRetry(downloadPath);
        if (await softwareDir.exists()) {
          await softwareDir.delete(recursive: true);
        }
        return (
          false,
          'php-cgi-spawner 下载失败: ${spawnerDownloadResult.$2}',
          calculatedHash,
        );
      }

      onProgress?.call('php-cgi-spawner 下载完成', 0.7, 'php-cgi-spawner 下载完成');

      // 步骤5: 将 php.ini-development 复制并重命名为 php.ini
      onProgress?.call('正在配置 PHP...', 0.75, '正在复制 php.ini-development...');
      final phpIniDev = File(
        path.join(softwareDir.path, 'php.ini-development'),
      );
      final phpIni = File(path.join(softwareDir.path, 'php.ini'));

      if (!await phpIniDev.exists()) {
        await _deleteFileWithRetry(downloadPath);
        if (await softwareDir.exists()) {
          await softwareDir.delete(recursive: true);
        }
        return (false, 'php.ini-development 文件不存在', calculatedHash);
      }

      if (await phpIni.exists()) {
        await phpIni.delete();
      }

      await phpIniDev.copy(phpIni.path);
      onProgress?.call('配置完成', 0.8, '已创建 php.ini');

      // 步骤6: 检查并处理 php.bat
      onProgress?.call('正在检查 php.bat...', 0.85, '正在检查 php.bat 文件...');
      final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
      final phpBatFile = File(phpBatPath);
      final binDir = Directory(path.join(storagePath, 'bin'));

      if (!await phpBatFile.exists()) {
        // php.bat 不存在，需要下载解压
        onProgress?.call('正在下载 php.bat...', 0.85, 'php.bat 不存在，开始下载...');

        // 获取 php.bat 下载地址（从软件源中获取）
        if (softwareSource.phpCmd == null) {
          await _deleteFileWithRetry(downloadPath);
          if (await softwareDir.exists()) {
            await softwareDir.delete(recursive: true);
          }
          return (false, '无法获取 php-cmd 下载地址', calculatedHash);
        }

        // 创建 bin 目录
        if (!await binDir.exists()) {
          await binDir.create(recursive: true);
        }

        // 下载 php-cmd 压缩包到临时目录
        final phpCmdFileName = path.basename(
          Uri.parse(softwareSource.phpCmd!).path,
        );
        final phpCmdTempPath = path.join(binDir.path, phpCmdFileName);
        final phpCmdTempFile = File(phpCmdTempPath);

        if (await phpCmdTempFile.exists()) {
          await phpCmdTempFile.delete();
        }

        final phpCmdDownloadResult = await DownloadService.downloadFile(
          softwareSource.phpCmd!,
          phpCmdTempPath,
          cancellationToken: cancellationToken,
          onProgress: (downloaded, total) {
            if (total > 0) {
              final progress = 0.85 + (downloaded / total) * 0.03;
              onProgress?.call(
                '正在下载 php.bat...',
                progress,
                '已下载: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB / ${(total / 1024 / 1024).toStringAsFixed(2)} MB',
              );
            }
          },
        );

        if (!phpCmdDownloadResult.$1) {
          await _deleteFileWithRetry(downloadPath);
          if (await softwareDir.exists()) {
            await softwareDir.delete(recursive: true);
          }
          return (
            false,
            'php-cmd 下载失败: ${phpCmdDownloadResult.$2}',
            calculatedHash,
          );
        }

        // 解压 php-cmd 到 bin 目录
        onProgress?.call('正在解压 php.bat...', 0.88, '正在解压 php-cmd...');
        final extractSuccess = await ExtractService.extractFile(
          phpCmdTempPath,
          binDir.path,
        );

        // 删除临时下载文件
        await _deleteFileWithRetry(phpCmdTempPath);

        if (!extractSuccess) {
          await _deleteFileWithRetry(downloadPath);
          if (await softwareDir.exists()) {
            await softwareDir.delete(recursive: true);
          }
          return (false, 'php-cmd 解压失败', calculatedHash);
        }

        onProgress?.call('php.bat 下载完成', 0.9, 'php.bat 已下载并解压');

        // 执行 Addbin2Path 指令
        onProgress?.call('正在添加环境变量...', 0.9, '正在将 bin 目录添加到 PATH...');
        final binPath = binDir.path.replaceAll('/', '\\');
        final pathEnvResult = await Process.run('powershell', [
          '-Command',
          '[Environment]::GetEnvironmentVariable("PATH", "User")',
        ], runInShell: true);

        String currentPath = '';
        if (pathEnvResult.exitCode == 0) {
          currentPath = pathEnvResult.stdout.toString().trim();
        }

        final normalizedCurrentPath = currentPath.replaceAll('\\', '/');
        final normalizedTargetPath = binPath.replaceAll('\\', '/');
        final pathParts = normalizedCurrentPath.split(';');
        bool pathExists = pathParts.any(
          (part) =>
              part.trim().replaceAll('\\', '/').toLowerCase() ==
              normalizedTargetPath.toLowerCase(),
        );

        if (!pathExists) {
          final setxResult = await Process.run('setx', [
            'PATH',
            '$currentPath;$binPath',
          ], runInShell: true);

          if (setxResult.exitCode != 0) {
            final output =
                setxResult.stdout.toString() + setxResult.stderr.toString();
            if (!output.toLowerCase().contains('success')) {
              await _deleteFileWithRetry(downloadPath);
              if (await softwareDir.exists()) {
                await softwareDir.delete(recursive: true);
              }
              return (false, '添加环境变量失败: ${setxResult.stderr}', calculatedHash);
            }
          }

          onProgress?.call('环境变量已添加', 0.92, '已添加 bin 目录到 PATH');
        } else {
          onProgress?.call('环境变量已存在', 0.92, 'PATH 中已存在 bin 目录');
        }
      } else {
        onProgress?.call('php.bat 已存在', 0.9, 'php.bat 文件已存在，跳过下载');
      }

      // 步骤7: 更新 php.bat 文件
      onProgress?.call('正在更新 php.bat...', 0.93, '正在更新 php.bat 中的 PHP 路径...');
      final updateResult = await updatePhpBat(
        softwareDir.path,
        storagePath,
        onProgress: onProgress,
      );

      if (!updateResult.$1) {
        await _deleteFileWithRetry(downloadPath);
        if (await softwareDir.exists()) {
          await softwareDir.delete(recursive: true);
        }
        return (false, updateResult.$2 ?? '更新 php.bat 失败', calculatedHash);
      }

      // 步骤8: 将下载的安装包移至 sources\php 目录下
      onProgress?.call('正在保存安装包...', 0.95, '正在保存安装包到 sources 目录...');
      final sourcesPhpDir = Directory('$storagePath/sources/php');
      if (!await sourcesPhpDir.exists()) {
        await sourcesPhpDir.create(recursive: true);
      }

      final sourceFile = File(
        path.join(sourcesPhpDir.path, path.basename(downloadPath)),
      );
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }

      await File(downloadPath).copy(sourceFile.path);
      await _deleteFileWithRetry(downloadPath);

      // 步骤9: 修改 php.ini 文件
      onProgress?.call('正在配置 php.ini...', 0.97, '正在修改 php.ini 配置...');
      final phpIniResult = await _configurePhpIni(
        softwareDir.path,
        onProgress: onProgress,
      );
      if (!phpIniResult.$1) {
        // php.ini 配置失败，但不影响安装成功（因为文件已安装）
        onProgress?.call(
          'php.ini 配置警告',
          0.99,
          '警告: ${phpIniResult.$2 ?? "php.ini 配置失败，但安装已完成"}',
        );
      } else {
        onProgress?.call('php.ini 配置完成', 0.99, 'php.ini 配置完成');
      }

      onProgress?.call('安装完成', 1.0, 'PHP 安装完成！');
      return (true, null, calculatedHash);
    } catch (e) {
      // 清理下载文件
      await _deleteFileWithRetry(downloadPath);
      // 清理软件目录
      if (await softwareDir.exists()) {
        try {
          await softwareDir.delete(recursive: true);
        } catch (_) {
          // 忽略删除错误
        }
      }
      return (false, 'PHP 安装失败: $e', calculatedHash);
    }
  }

  /// 配置 php.ini 文件
  /// [phpDir] PHP 安装目录路径
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> _configurePhpIni(
    String phpDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 查找 php.ini 文件（可能在根目录或根目录下的某个位置）
      final phpIniPath = path.join(phpDir, 'php.ini');
      final phpIniFile = File(phpIniPath);

      if (!await phpIniFile.exists()) {
        // 如果根目录下没有，尝试查找 php.ini-development 或 php.ini-production
        final phpIniDev = File(path.join(phpDir, 'php.ini-development'));
        final phpIniProd = File(path.join(phpDir, 'php.ini-production'));

        if (await phpIniDev.exists()) {
          // 复制 php.ini-development 为 php.ini
          await phpIniDev.copy(phpIniPath);
          onProgress?.call(
            '正在配置 php.ini...',
            0.97,
            '从 php.ini-development 创建 php.ini',
          );
        } else if (await phpIniProd.exists()) {
          // 复制 php.ini-production 为 php.ini
          await phpIniProd.copy(phpIniPath);
          onProgress?.call(
            '正在配置 php.ini...',
            0.97,
            '从 php.ini-production 创建 php.ini',
          );
        } else {
          return (false, '未找到 php.ini 文件或模板文件');
        }
      }

      // 读取 php.ini 文件内容
      final content = await phpIniFile.readAsString();
      final lines = content.split('\n');

      // 需要取消注释的扩展列表
      final extensionsToEnable = [
        'extension=bz2',
        'extension=curl',
        'extension=ffi',
        'extension=fileinfo',
        'extension=gettext',
        'extension=intl',
        'extension=mbstring',
        'extension=gd',
        'extension=exif',
        'extension=mysqli',
        'extension=openssl',
        'extension=pdo_mysql',
        'extension=pdo_pgsql',
        'extension=pdo_sqlite',
        'extension=pgsql',
        'extension=sqlite3',
        'zend_extension=opcache',
      ];

      // 修改每一行
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmedLine = line.trim();

        if (trimmedLine.startsWith(';opcache.enable=1') ||
            trimmedLine == ';opcache.enable=1') {
          lines[i] = line.replaceFirst(';opcache.enable=1', 'opcache.enable=1');
          onProgress?.call('正在配置 php.ini...', 0.97, '启用 opcache.enable');
          continue;
        }

        if (trimmedLine.startsWith(';opcache.enable_cli=0') ||
            trimmedLine == ';opcache.enable_cli=0') {
          lines[i] = line.replaceFirst(
            ';opcache.enable_cli=0',
            'opcache.enable_cli=1',
          );
          onProgress?.call('正在配置 php.ini...', 0.97, '启用 opcache.enable_cli');
          continue;
        }

        // 2. 修改 extension_dir
        // 匹配 ;extension_dir = "ext" 或类似格式（可能有空格）
        if ((RegExp(r'^\s*;extension_dir\s*=\s*"ext"').hasMatch(trimmedLine)) ||
            (RegExp(r"^\s*;extension_dir\s*=\s*'ext'").hasMatch(trimmedLine))) {
          lines[i] = line.replaceFirst(RegExp(r'^\s*;'), '');
          onProgress?.call('正在配置 php.ini...', 0.97, '启用 extension_dir');
          continue;
        }

        // 3. 取消注释指定的扩展
        for (final extension in extensionsToEnable) {
          // 匹配以分号开头，后跟扩展名的行（可能有空格）
          final pattern = RegExp(r'^\s*;' + RegExp.escape(extension));
          if (pattern.hasMatch(trimmedLine)) {
            // 删除行首的分号（保留其他空格）
            lines[i] = line.replaceFirst(RegExp(r'^\s*;'), '');
            onProgress?.call('正在配置 php.ini...', 0.97, '启用 $extension');
            break;
          }
        }
      }

      // 写回文件
      await phpIniFile.writeAsString(lines.join('\n'));

      return (true, null);
    } catch (e) {
      return (false, '配置 php.ini 失败: $e');
    }
  }
}
