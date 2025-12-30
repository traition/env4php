import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/software_model.dart';
import '../services/config_service.dart';
import '../services/download_service.dart';
import '../services/extract_service.dart';
import '../services/software_source_service.dart';
import '../utils/nginx_project_helper.dart';

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
        final mysqlInitResult = await _initializeMysql(
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

      // PostgreSQL 特殊处理：初始化数据库并注册服务
      if (software.cate4 != null && software.cate4!.toLowerCase() == 'pgsql') {
        onProgress?.call(
          '正在初始化 PostgreSQL...',
          0.98,
          '开始初始化 PostgreSQL 数据库...',
        );
        final pgsqlInitResult = await _initializePgsql(
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

      // MongoDB 特殊处理：注册服务并配置启动方式
      if (software.cate4 != null &&
          software.cate4!.toLowerCase() == 'mongodb') {
        onProgress?.call('正在初始化 MongoDB...', 0.98, '开始初始化 MongoDB 服务...');
        final mongodbInitResult = await _initializeMongodb(
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

      // phpMyAdmin 特殊处理：创建普通PHP项目
      if (software.cate4 != null &&
          software.cate4!.toLowerCase() == 'phpmyadmin') {
        onProgress?.call('正在初始化 phpMyAdmin...', 0.98, '开始创建 phpMyAdmin 项目...');
        final phpmyadminInitResult = await _initializePhpmyadmin(
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

  /// 检查路径是否在存储目录范围内
  /// [targetPath] 目标路径
  /// [storagePath] 存储根目录
  /// 返回 true 如果在范围内，false 如果超出范围
  static bool _isPathWithinStorage(String targetPath, String storagePath) {
    try {
      final normalizedTarget = path.normalize(path.absolute(targetPath));
      final normalizedStorage = path.normalize(path.absolute(storagePath));

      // 检查目标路径是否以存储路径开头
      return normalizedTarget.startsWith(normalizedStorage);
    } catch (e) {
      return false;
    }
  }

  /// 解析路径并检查是否在存储目录范围内
  /// [pathStr] 路径字符串（可能是相对或绝对路径）
  /// [baseDir] 基础目录（用于解析相对路径）
  /// [storagePath] 存储根目录
  /// 返回 (解析后的路径, 是否在范围内)
  static (String resolvedPath, bool isWithinStorage) _resolveAndCheckPath(
    String pathStr,
    String baseDir,
    String storagePath,
  ) {
    String resolvedPath;
    if (path.isAbsolute(pathStr)) {
      resolvedPath = path.normalize(pathStr);
    } else {
      resolvedPath = path.normalize(path.absolute(baseDir, pathStr));
    }

    final isWithin = _isPathWithinStorage(resolvedPath, storagePath);
    return (resolvedPath, isWithin);
  }

  /// 解析 replace 命令的参数，支持反引号（`）作为字符串定界符
  /// [command] 完整的命令字符串
  /// 返回 (filePath, needle, replace) 或 null 如果解析失败
  static (String filePath, String needle, String replace)? _parseReplaceCommand(
    String command,
  ) {
    // 移除命令名 "replace"
    String remaining = command.substring('replace'.length).trim();
    if (remaining.isEmpty) {
      return null;
    }

    // 解析 filePath（第一个参数，不需要反引号）
    int filePathEnd = remaining.indexOf(' ');
    if (filePathEnd == -1) {
      return null;
    }
    String filePath = remaining.substring(0, filePathEnd);
    remaining = remaining.substring(filePathEnd).trim();

    // 解析 needle（第二个参数，可能用反引号包裹）
    String needle = '';
    if (remaining.startsWith('`')) {
      // 以反引号开头，找到匹配的结束反引号
      int endIndex = remaining.indexOf('`', 1);
      if (endIndex == -1) {
        return null; // 没有找到匹配的结束反引号
      }
      needle = remaining.substring(1, endIndex);
      remaining = remaining.substring(endIndex + 1).trim();
    } else {
      // 没有反引号，找到下一个空格或反引号
      int spaceIndex = remaining.indexOf(' ');
      int backtickIndex = remaining.indexOf('`');
      int endIndex = -1;
      if (spaceIndex != -1 && backtickIndex != -1) {
        endIndex = spaceIndex < backtickIndex ? spaceIndex : backtickIndex;
      } else if (spaceIndex != -1) {
        endIndex = spaceIndex;
      } else if (backtickIndex != -1) {
        endIndex = backtickIndex;
      } else {
        // 没有找到分隔符，整个剩余部分都是 needle
        needle = remaining;
        remaining = '';
      }
      if (endIndex != -1) {
        needle = remaining.substring(0, endIndex);
        remaining = remaining.substring(endIndex).trim();
      }
    }

    // 解析 replace（第三个参数，可能用反引号包裹）
    String replace;
    if (remaining.startsWith('`')) {
      // 以反引号开头，找到匹配的结束反引号
      int endIndex = remaining.indexOf('`', 1);
      if (endIndex == -1) {
        return null; // 没有找到匹配的结束反引号
      }
      replace = remaining.substring(1, endIndex);
    } else {
      // 没有反引号，使用剩余的所有内容
      replace = remaining;
    }

    return (filePath, needle, replace);
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

    // 确保存储路径是绝对路径
    final normalizedStoragePath = path.normalize(path.absolute(storagePath));

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

        switch (cmd) {
          case 'unpack':
            // 解压缩文件至 .7ztemp 文件夹
            // 检查临时目录是否在存储目录内
            final normalizedTempDir = path.normalize(path.absolute(tempDir));
            if (!_isPathWithinStorage(
              normalizedTempDir,
              normalizedStoragePath,
            )) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '临时目录超出存储目录范围: $normalizedTempDir', addedPaths);
            }

            final tempDirectory = Directory(tempDir);
            // 不删除原有内容，只确保目录存在（覆盖解压，保留原有文件）
            if (!await tempDirectory.exists()) {
              await tempDirectory.create(recursive: true);
            }
            currentTempDir = tempDirectory;
            currentWorkDir = tempDir;

            final extractSuccess = await ExtractService.extractFile(
              downloadPath,
              tempDir,
            );

            if (!extractSuccess) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '解压失败', addedPaths);
            }
            onProgress?.call('正在执行安装指令...', progress, '解压完成');
            break;

          case 'skip':
            // 不执行任何操作，下一步
            onProgress?.call('正在执行安装指令...', progress, '跳过此步骤');
            break;

          case 'movedir':
            // 移动文件夹 movedir [source] [destination]
            if (parts.length < 3) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (
                false,
                'movedir 命令需要两个参数: source 和 destination',
                addedPaths,
              );
            }

            String source = parts[1];
            String destination = parts[2];

            // 解析 source 路径
            String sourcePath;
            if (source == '.temp') {
              // .temp 指向存储目录下的子分类文件夹下的 .temp 文件夹
              sourcePath = path.join(storagePath, category, '.temp');
            } else if (path.isAbsolute(source)) {
              sourcePath = source;
            } else {
              sourcePath = path.join(currentWorkDir, source);
            }

            // 解析 destination 路径
            String destPath;
            if (destination == '.temp') {
              // .temp 指向存储目录下的子分类文件夹下的 .temp 文件夹
              destPath = path.join(storagePath, category, '.temp');
            } else if (destination == '/') {
              // '/' 表示当前工作目录（解压的缓存目录）
              destPath = currentWorkDir;
            } else {
              if (path.isAbsolute(destination)) {
                destPath = destination;
              } else {
                destPath = path.join(currentWorkDir, destination);
              }
            }

            final sourceDir = Directory(sourcePath);
            if (!await sourceDir.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源目录不存在: $sourcePath', addedPaths);
            }

            // 如果目标文件夹不存在，则新建
            final destDir = Directory(destPath);
            if (!await destDir.exists()) {
              await destDir.create(recursive: true);
            }

            // 移动源文件夹下的文件到目标文件夹下
            await for (final entity in sourceDir.list()) {
              final destEntityPath = path.join(
                destPath,
                path.basename(entity.path),
              );

              if (entity is Directory) {
                // 如果是文件夹
                final destEntity = Directory(destEntityPath);
                if (await destEntity.exists()) {
                  // 如果目标文件夹已存在，递归合并而不是删除
                  await _mergeDirectory(Directory(entity.path), destEntity);
                  // 合并后删除源文件夹
                  await Directory(entity.path).delete(recursive: true);
                } else {
                  // 如果目标文件夹不存在，直接移动
                  await Directory(entity.path).rename(destEntityPath);
                }
              } else if (entity is File) {
                // 如果是文件
                final destEntity = File(destEntityPath);
                // 如果目标文件已存在，先删除再移动（覆盖）
                if (await destEntity.exists()) {
                  await destEntity.delete();
                }
                await File(entity.path).rename(destEntityPath);
              }
            }

            // 移动完成后删除源文件夹
            await sourceDir.delete(recursive: true);

            // 更新当前工作目录
            if (destination == '/') {
              // '/' 表示当前工作目录，不需要更新
            } else if (destination != '.temp') {
              currentWorkDir = destPath;
            }

            onProgress?.call(
              '正在执行安装指令...',
              progress,
              '移动目录内容: $source -> $destPath',
            );
            break;

          case 'newdir':
            // 创建文件夹 newdir [path]
            // path 默认以软件的预期安装目录为基准
            if (parts.length < 2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'newdir 命令需要一个参数: path', addedPaths);
            }

            String dirPath = parts[1];

            // 解析路径
            String targetPath;
            if (dirPath.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = dirPath.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              targetPath = path.normalize(path.join(softwareDir, relativePath));
            } else if (path.isAbsolute(dirPath)) {
              // 绝对路径，直接使用
              targetPath = dirPath;
            } else {
              // 默认以软件的预期安装目录为基准
              targetPath = path.normalize(path.join(softwareDir, dirPath));
            }

            // 检查路径是否在存储目录内
            if (!_isPathWithinStorage(targetPath, normalizedStoragePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目标路径超出存储目录范围: $targetPath', addedPaths);
            }

            // 创建目录
            final targetDir = Directory(targetPath);
            if (!await targetDir.exists()) {
              await targetDir.create(recursive: true);
              onProgress?.call('正在执行安装指令...', progress, '创建目录: $targetPath');
            } else {
              onProgress?.call('正在执行安装指令...', progress, '目录已存在: $targetPath');
            }
            break;

          case 'del':
            // 删除文件 del [target]
            if (parts.length < 2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'del 命令需要一个参数: target', addedPaths);
            }

            final target = parts[1];

            if (target == 'all') {
              // 删除当前工作目录下的所有文件
              // 检查当前工作目录是否在存储目录内
              if (!_isPathWithinStorage(
                currentWorkDir,
                normalizedStoragePath,
              )) {
                await _rollbackAddedPaths(addedPaths, onProgress);
                return (false, '工作目录超出存储目录范围: $currentWorkDir', addedPaths);
              }

              final workDir = Directory(currentWorkDir);
              if (await workDir.exists()) {
                await for (final entity in workDir.list()) {
                  if (entity is Directory) {
                    await entity.delete(recursive: true);
                  } else if (entity is File) {
                    await entity.delete();
                  }
                }
              }
              onProgress?.call('正在执行安装指令...', progress, '删除所有文件');
            } else {
              // 删除指定文件/目录
              final (targetPath, targetWithin) = _resolveAndCheckPath(
                target,
                currentWorkDir,
                normalizedStoragePath,
              );

              if (!targetWithin) {
                await _rollbackAddedPaths(addedPaths, onProgress);
                return (false, '目标路径超出存储目录范围: $targetPath', addedPaths);
              }

              final targetEntity = FileSystemEntity.typeSync(targetPath);
              if (targetEntity == FileSystemEntityType.directory) {
                await Directory(targetPath).delete(recursive: true);
              } else if (targetEntity == FileSystemEntityType.file) {
                await File(targetPath).delete();
              }
              onProgress?.call('正在执行安装指令...', progress, '删除: $targetPath');
            }
            break;

          case 'move':
            // 移动文件 move [source] [destination]
            // .7ztemp 开头相对于解压缩的目录，bin 开头则为存储目录\bin
            if (parts.length < 3) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'move 命令需要两个参数: source 和 destination', addedPaths);
            }

            String source = parts[1];
            String destination = parts[2];

            // 解析 source 路径
            String sourcePath;
            final categoryDir = path.join(storagePath, category);
            if (source.startsWith('.down')) {
              // .down 开头，将 .down 部分替换为 downloadPath 的目录部分（分类目录）
              String relativePath = source.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(categoryDir, relativePath));
            } else if (source.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = source.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(softwareDir, relativePath));
            } else if (source.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = source.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(tempDir, relativePath));
            } else if (source.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = source.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(source)) {
              sourcePath = source;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              sourcePath = path.join(categoryDir, source);
            }

            // 解析 destination 路径
            String destPath;
            if (destination.startsWith('.down')) {
              // .down 开头，将 .down 部分替换为 downloadPath 的目录部分（分类目录）
              String relativePath = destination.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(categoryDir, relativePath));
            } else if (destination.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = destination.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(softwareDir, relativePath));
            } else if (destination.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = destination.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(tempDir, relativePath));
            } else if (destination.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = destination.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(destination)) {
              destPath = destination;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              destPath = path.join(categoryDir, destination);
            }

            // 确保路径是绝对路径
            // source 路径：如果已经通过前缀解析为绝对路径，直接规范化；否则相对于分类目录
            if (!path.isAbsolute(sourcePath)) {
              sourcePath = path.normalize(
                path.absolute(categoryDir, sourcePath),
              );
            } else {
              sourcePath = path.normalize(sourcePath);
            }

            // destination 路径：如果已经通过前缀解析为绝对路径，直接规范化；否则相对于分类目录
            if (!path.isAbsolute(destPath)) {
              destPath = path.normalize(path.absolute(categoryDir, destPath));
            } else {
              destPath = path.normalize(destPath);
            }

            // 检查路径安全性
            if (!_isPathWithinStorage(sourcePath, normalizedStoragePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源路径超出存储目录范围: $sourcePath', addedPaths);
            }

            if (!_isPathWithinStorage(destPath, normalizedStoragePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目标路径超出存储目录范围: $destPath', addedPaths);
            }

            // 调试输出（仅在调试模式）
            if (kDebugMode) {
              onProgress?.call(
                '正在执行安装指令...',
                progress,
                '[DEBUG] move 路径解析: source="$source" -> "$sourcePath", destination="$destination" -> "$destPath"',
              );
            }

            final sourceFile = File(sourcePath);
            if (!await sourceFile.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源文件不存在: $sourcePath', addedPaths);
            }

            // 如果目标文件已存在，先删除
            final destFile = File(destPath);
            if (await destFile.exists()) {
              await destFile.delete();
            }

            // 确保目标目录存在
            final destDir = Directory(path.dirname(destPath));
            if (!await destDir.exists()) {
              await destDir.create(recursive: true);
            }

            // 移动文件
            await sourceFile.rename(destPath);

            onProgress?.call(
              '正在执行安装指令...',
              progress,
              '移动文件: $sourcePath -> $destPath',
            );
            break;

          case 'copy':
            // 复制文件 copy [source] [destination]
            // 路径处理与 move 相同
            if (parts.length < 3) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'copy 命令需要两个参数: source 和 destination', addedPaths);
            }

            String source = parts[1];
            String destination = parts[2];

            // 解析 source 路径（与 move 相同）
            String sourcePath;
            final categoryDir = path.join(storagePath, category);
            if (source.startsWith('.down')) {
              // .down 开头，将 .down 部分替换为 downloadPath 的目录部分（分类目录）
              String relativePath = source.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(categoryDir, relativePath));
            } else if (source.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = source.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(softwareDir, relativePath));
            } else if (source.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = source.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(tempDir, relativePath));
            } else if (source.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = source.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(source)) {
              sourcePath = source;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              sourcePath = path.join(categoryDir, source);
            }

            // 解析 destination 路径（与 move 相同）
            String destPath;
            if (destination.startsWith('.down')) {
              // .down 开头，将 .down 部分替换为 downloadPath 的目录部分（分类目录）
              String relativePath = destination.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(categoryDir, relativePath));
            } else if (destination.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = destination.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(softwareDir, relativePath));
            } else if (destination.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = destination.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(tempDir, relativePath));
            } else if (destination.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = destination.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(destination)) {
              destPath = destination;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              destPath = path.join(categoryDir, destination);
            }

            // 确保路径是绝对路径
            // source 路径：如果已经通过前缀解析为绝对路径，直接规范化；否则相对于分类目录
            if (!path.isAbsolute(sourcePath)) {
              sourcePath = path.normalize(
                path.absolute(categoryDir, sourcePath),
              );
            } else {
              sourcePath = path.normalize(sourcePath);
            }

            // destination 路径：如果已经通过前缀解析为绝对路径，直接规范化；否则相对于分类目录
            if (!path.isAbsolute(destPath)) {
              destPath = path.normalize(path.absolute(categoryDir, destPath));
            } else {
              destPath = path.normalize(destPath);
            }

            // 检查路径安全性
            if (!_isPathWithinStorage(sourcePath, normalizedStoragePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源路径超出存储目录范围: $sourcePath', addedPaths);
            }

            if (!_isPathWithinStorage(destPath, normalizedStoragePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目标路径超出存储目录范围: $destPath', addedPaths);
            }

            final sourceFile = File(sourcePath);
            if (!await sourceFile.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源文件不存在: $sourcePath', addedPaths);
            }

            // 如果目标文件已存在，先删除
            final destFile = File(destPath);
            if (await destFile.exists()) {
              await destFile.delete();
            }

            // 确保目标目录存在
            final destDir = Directory(path.dirname(destPath));
            if (!await destDir.exists()) {
              await destDir.create(recursive: true);
            }

            // 复制文件（与 move 的区别：使用 copy 而不是 rename）
            await sourceFile.copy(destPath);

            onProgress?.call(
              '正在执行安装指令...',
              progress,
              '复制文件: $sourcePath -> $destPath',
            );
            break;

          case 'addbin2path':
            // 将指定目录加入系统环境变量PATH中 Addbin2Path [dir]
            // 如果dir为空或未定义，则将存储目录\bin加入PATH
            String dirPath;
            if (parts.length < 2 || parts[1].isEmpty) {
              // dir 为空或未定义，使用存储目录\bin
              dirPath = path.join(storagePath, 'bin');
            } else {
              dirPath = parts[1];
            }

            // 解析路径并检查是否在存储目录内
            final (resolvedDirPath, dirWithin) = _resolveAndCheckPath(
              dirPath,
              currentWorkDir,
              normalizedStoragePath,
            );

            if (!dirWithin) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目录路径超出存储目录范围: $resolvedDirPath', addedPaths);
            }

            dirPath = resolvedDirPath;

            final dir = Directory(dirPath);
            if (!await dir.exists()) {
              // 如果目录不存在，创建它
              await dir.create(recursive: true);
              onProgress?.call('正在执行安装指令...', progress, '已创建目录: $dirPath');
            }

            // 检查 PATH 中是否已存在该路径
            final normalizedPath = path.normalize(dirPath);
            final pathEnvResult = await Process.run('powershell', [
              '-Command',
              '[Environment]::GetEnvironmentVariable("PATH", "User")',
            ], runInShell: true);

            String currentPath = '';
            if (pathEnvResult.exitCode == 0) {
              currentPath = pathEnvResult.stdout.toString().trim();
            }

            // 检查路径是否已存在（不区分大小写，处理路径分隔符）
            final normalizedCurrentPath = currentPath.replaceAll('\\', '/');
            final normalizedTargetPath = normalizedPath.replaceAll('\\', '/');
            final pathParts = normalizedCurrentPath.split(';');
            bool pathExists = pathParts.any(
              (part) =>
                  part.trim().replaceAll('\\', '/').toLowerCase() ==
                  normalizedTargetPath.toLowerCase(),
            );

            if (pathExists) {
              onProgress?.call(
                '正在执行安装指令...',
                progress,
                'PATH 中已存在该路径，跳过: $normalizedPath',
              );
            } else {
              // 使用 setx 命令添加到用户环境变量 PATH
              final result = await Process.run('setx', [
                'PATH',
                '$currentPath;$normalizedPath',
              ], runInShell: true);

              if (result.exitCode != 0) {
                // setx 可能返回非零退出码但实际成功，检查输出
                final output =
                    result.stdout.toString() + result.stderr.toString();
                if (!output.toLowerCase().contains('success')) {
                  await _rollbackAddedPaths(addedPaths, onProgress);
                  return (false, '添加环境变量失败: ${result.stderr}', addedPaths);
                }
              }

              onProgress?.call(
                '正在执行安装指令...',
                progress,
                '已添加目录到系统环境变量 PATH: $normalizedPath',
              );
            }
            break;

          case 'replace':
            // 替换文件中的字符串 replace [filepath] [needle] [replace]
            // filepath 相对于软件安装路径（存储目录/子分类文件夹/软件目录/）
            // 如果 filepath 以 .down 开头，则相对于安装包的下载地址
            // 如果 filepath 以 .7ztemp 开头，则相对于解压缩的目录（.7ztemp）
            // 支持反引号（`）作为 needle 和 replace 的定界符
            final parsed = _parseReplaceCommand(command);
            if (parsed == null) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'replace 命令解析失败，请检查命令格式', addedPaths);
            }

            String filePath = parsed.$1;
            String needle = parsed.$2;
            String replace = parsed.$3;

            // 解析文件路径
            String resolvedFilePath;
            String baseDirForCheck; // 用于路径安全检查的基准目录

            // 调试输出（仅在调试模式）
            if (kDebugMode) {
              onProgress?.call(
                '正在执行安装指令...',
                progress,
                '[DEBUG] replace 命令解析: filePath="$filePath", downloadPath="$downloadPath", softwareDir="$softwareDir"',
              );
            }

            if (path.isAbsolute(filePath)) {
              resolvedFilePath = filePath;
              baseDirForCheck = softwareDir;
            } else if (filePath.startsWith('.down')) {
              // .down 开头，将 .down 部分替换为分类目录（$storagePath/$category）
              // 而不是 downloadPath 的目录部分，因为附件可能下载到软件目录下
              final categoryDir = path.join(storagePath, category);
              // 移除 .down 前缀，获取相对路径部分
              String relativePath = filePath.substring('.down'.length);
              // 移除开头的路径分隔符（如果有）
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              // 使用 path.join 确保路径正确拼接
              resolvedFilePath = path.normalize(
                path.join(categoryDir, relativePath),
              );
              baseDirForCheck = categoryDir;

              // 调试输出（仅在调试模式）
              if (kDebugMode) {
                final isMainCommand =
                    onProgress != null &&
                    (onProgress.toString().contains('正在执行安装指令') ||
                        onProgress.toString().contains('正在执行附件指令'));
                onProgress?.call(
                  isMainCommand ? '正在执行安装指令...' : '正在执行附件指令...',
                  progress,
                  '[DEBUG] .down 路径解析: filePath="$filePath", downloadPath="$downloadPath", categoryDir="$categoryDir", relativePath="$relativePath", resolvedFilePath="$resolvedFilePath"',
                );
              }
            } else if (filePath.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录（.7ztemp）
              final relativePath = filePath.substring('.7ztemp'.length);
              if (relativePath.startsWith('/') ||
                  relativePath.startsWith('\\')) {
                resolvedFilePath = path.join(
                  tempDir,
                  relativePath.substring(1),
                );
              } else {
                resolvedFilePath = path.join(tempDir, relativePath);
              }
              baseDirForCheck = tempDir;
            } else {
              // 其他情况，相对于软件安装路径
              resolvedFilePath = path.normalize(
                path.join(softwareDir, filePath),
              );
              baseDirForCheck = softwareDir;
            }

            // 确保 resolvedFilePath 是绝对路径（.down 情况已经在上面处理为绝对路径，这里只处理其他情况）
            if (!filePath.startsWith('.down') &&
                !path.isAbsolute(resolvedFilePath)) {
              resolvedFilePath = path.normalize(
                path.absolute(baseDirForCheck, resolvedFilePath),
              );
            }

            // 调试输出（仅在调试模式，.down 情况已在上面输出）
            if (kDebugMode && !filePath.startsWith('.down')) {
              onProgress?.call(
                '正在执行安装指令...',
                progress,
                '[DEBUG] replace 文件路径解析: $filePath -> $resolvedFilePath (基准: $baseDirForCheck)',
              );
            }

            // 检查路径安全性
            if (!_isPathWithinStorage(
              resolvedFilePath,
              normalizedStoragePath,
            )) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '文件路径超出存储目录范围: $resolvedFilePath', addedPaths);
            }

            final file = File(resolvedFilePath);
            if (!await file.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '文件不存在: $resolvedFilePath', addedPaths);
            }

            // 读取文件内容
            String content = await file.readAsString();

            // 处理 replace 参数的特殊值
            String processedReplace = replace;
            // 将 replace 中的 !softPath! 替换为软件安装路径
            if (processedReplace.contains('!softPath!')) {
              // !softPath! 表示当前安装的软件预期的安装路径
              // 将 softwareDir 中的路径分隔符统一为 Windows 风格（\）
              final normalizedSoftwareDir = softwareDir.replaceAll('/', '\\');
              processedReplace = processedReplace.replaceAll(
                '!softPath!',
                normalizedSoftwareDir,
              );
            }

            // 将 processedReplace 中的所有 / 替换为 \（确保路径分隔符统一为 Windows 风格）
            processedReplace = processedReplace.replaceAll('/', '\\');

            // 执行替换（替换所有匹配的部分）
            if (!content.contains(needle)) {
              onProgress?.call(
                '正在执行安装指令...',
                progress,
                '警告: 文件中未找到匹配的字符串: $needle',
              );
            } else {
              content = content.replaceAll(needle, processedReplace);
              // 写回文件
              await file.writeAsString(content);
              onProgress?.call(
                '正在执行安装指令...',
                progress,
                '已替换文件中的字符串: $resolvedFilePath',
              );
            }
            break;

          default:
            await _rollbackAddedPaths(addedPaths, onProgress);
            return (false, '未知命令: $cmd', addedPaths);
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

    // 确保存储路径是绝对路径
    final normalizedStoragePath = path.normalize(path.absolute(storagePath));

    for (int i = 0; i < commands.length; i++) {
      final command = commands[i].trim();
      if (command.isEmpty) continue;

      final progress = 0.5 + (i / commands.length) * 0.1;
      onProgress?.call(
        '正在执行附件指令...',
        progress,
        '执行指令 ${i + 1}/${commands.length}: $command',
      );

      try {
        // 解析命令
        final parts = command.split(' ');
        final cmd = parts[0].toLowerCase();

        switch (cmd) {
          case 'unpack':
            // 解压缩文件至临时目录
            final normalizedTempDir = path.normalize(path.absolute(tempDir));
            if (!_isPathWithinStorage(
              normalizedTempDir,
              normalizedStoragePath,
            )) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '临时目录超出存储目录范围: $normalizedTempDir', addedPaths);
            }

            final tempDirectory = Directory(tempDir);
            // 不删除原有内容，只确保目录存在
            if (!await tempDirectory.exists()) {
              await tempDirectory.create(recursive: true);
            }
            currentTempDir = tempDirectory;
            currentWorkDir = tempDir; // unpack 后，工作目录仍在临时目录

            final extractSuccess = await ExtractService.extractFile(
              downloadPath,
              tempDir,
            );

            if (!extractSuccess) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '解压失败', addedPaths);
            }
            onProgress?.call('正在执行附件指令...', progress, '解压完成');

            // 调试暂停：等待用户输入 'c' 后继续
            print('\n=== 附件解压完成，临时目录: $tempDir ===');
            print('临时目录内容:');
            try {
              final tempDirObj = Directory(tempDir);
              if (await tempDirObj.exists()) {
                await for (final entity in tempDirObj.list()) {
                  print('  - ${entity.path}');
                }
              }
            } catch (e) {
              print('  无法列出目录内容: $e');
            }

            // 使用 debugger() 断点暂停，检查临时目录后按 F5 继续
            // if (kDebugMode) {
            //   developer.debugger(message: '附件解压完成，检查临时目录后按 F5 继续');
            // }

            // 同时提供控制台输入方式（如果可用）
            String? input;
            try {
              if (stdin.hasTerminal) {
                print('或者在此输入 "c" 继续: ');
                input = stdin.readLineSync();
                if (input == 'c') {
                  print('继续执行...\n');
                }
              }
            } catch (e) {
              print('读取输入失败: $e');
            }

            break;

          case 'skip':
            onProgress?.call('正在执行附件指令...', progress, '跳过此步骤');
            break;

          case 'movedir':
            if (parts.length < 3) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (
                false,
                'movedir 命令需要两个参数: source 和 destination',
                addedPaths,
              );
            }

            String source = parts[1];
            String destination = parts[2];

            // 解析 source 路径
            String sourcePath;
            if (source == '.temp') {
              // .temp 指向存储目录下的子分类文件夹下的 .temp 文件夹
              sourcePath = path.join(storagePath, category, '.temp');
            } else if (path.isAbsolute(source)) {
              sourcePath = source;
            } else {
              sourcePath = path.join(currentWorkDir, source);
            }

            // 解析 destination 路径
            String destPath;
            if (destination == '.temp') {
              // .temp 指向存储目录下的子分类文件夹下的 .temp 文件夹
              destPath = path.join(storagePath, category, '.temp');
            } else if (destination == '/') {
              // 对于附件，'/' 表示软件目录
              destPath = softwareDir;
            } else {
              if (path.isAbsolute(destination)) {
                destPath = destination;
              } else {
                // 对于附件，相对路径相对于软件目录
                destPath = path.join(softwareDir, destination);
              }
            }

            // 检查路径安全性
            final sourceCheck = _resolveAndCheckPath(
              sourcePath,
              currentWorkDir,
              storagePath,
            );
            if (!sourceCheck.$2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源路径超出存储目录范围: ${sourceCheck.$1}', addedPaths);
            }
            sourcePath = sourceCheck.$1;

            final destCheck = _resolveAndCheckPath(
              destPath,
              softwareDir,
              storagePath,
            );
            if (!destCheck.$2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目标路径超出存储目录范围: ${destCheck.$1}', addedPaths);
            }
            destPath = destCheck.$1;

            final sourceDir = Directory(sourcePath);
            if (!await sourceDir.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源目录不存在: $sourcePath', addedPaths);
            }

            // 如果目标文件夹不存在，则新建
            final destDir = Directory(destPath);
            if (!await destDir.exists()) {
              await destDir.create(recursive: true);
            }

            // 移动源文件夹下的文件到目标文件夹下
            await for (final entity in sourceDir.list()) {
              final destEntityPath = path.join(
                destPath,
                path.basename(entity.path),
              );

              if (entity is Directory) {
                // 如果是文件夹
                final destEntity = Directory(destEntityPath);
                if (await destEntity.exists()) {
                  // 如果目标文件夹已存在，递归合并而不是删除
                  await _mergeDirectory(Directory(entity.path), destEntity);
                  // 合并后删除源文件夹
                  await Directory(entity.path).delete(recursive: true);
                } else {
                  // 如果目标文件夹不存在，直接移动
                  await Directory(entity.path).rename(destEntityPath);
                }
              } else if (entity is File) {
                // 如果是文件
                final destEntity = File(destEntityPath);
                // 如果目标文件已存在，先删除再移动（覆盖）
                if (await destEntity.exists()) {
                  await destEntity.delete();
                }
                await File(entity.path).rename(destEntityPath);
              }
            }

            // 移动完成后删除源文件夹
            await sourceDir.delete(recursive: true);

            // 更新工作目录
            if (destination == '/') {
              currentWorkDir = softwareDir;
            } else if (destination != '.temp') {
              currentWorkDir = destPath;
            }

            onProgress?.call(
              '正在执行附件指令...',
              progress,
              '移动目录: $source -> $destPath',
            );
            break;

          case 'newdir':
            // 创建文件夹 newdir [path]
            // path 默认以软件的预期安装目录为基准
            if (parts.length < 2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'newdir 命令需要一个参数: path', addedPaths);
            }

            String dirPath = parts[1];

            // 解析路径
            String targetPath;
            if (dirPath.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = dirPath.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              targetPath = path.normalize(path.join(softwareDir, relativePath));
            } else if (path.isAbsolute(dirPath)) {
              // 绝对路径，直接使用
              targetPath = dirPath;
            } else {
              // 默认以软件的预期安装目录为基准
              targetPath = path.normalize(path.join(softwareDir, dirPath));
            }

            // 检查路径是否在存储目录内
            final pathCheck = _resolveAndCheckPath(
              targetPath,
              softwareDir,
              storagePath,
            );
            if (!pathCheck.$2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目标路径超出存储目录范围: ${pathCheck.$1}', addedPaths);
            }
            targetPath = pathCheck.$1;

            // 创建目录
            final targetDir = Directory(targetPath);
            if (!await targetDir.exists()) {
              await targetDir.create(recursive: true);
              onProgress?.call('正在执行附件指令...', progress, '创建目录: $targetPath');
            } else {
              onProgress?.call('正在执行附件指令...', progress, '目录已存在: $targetPath');
            }
            break;

          case 'del':
            if (parts.length < 2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'del 命令需要一个参数: target', addedPaths);
            }

            final target = parts[1];

            if (target == 'all') {
              if (!_isPathWithinStorage(
                currentWorkDir,
                normalizedStoragePath,
              )) {
                await _rollbackAddedPaths(addedPaths, onProgress);
                return (false, '工作目录超出存储目录范围: $currentWorkDir', addedPaths);
              }

              final workDir = Directory(currentWorkDir);
              if (await workDir.exists()) {
                await for (final entity in workDir.list()) {
                  if (entity is Directory) {
                    await entity.delete(recursive: true);
                  } else if (entity is File) {
                    await entity.delete();
                  }
                }
              }
              onProgress?.call('正在执行附件指令...', progress, '删除所有文件');
            } else {
              // 删除指定文件/目录
              // 解析 target 路径
              String targetPath;
              final categoryDir = path.join(storagePath, category);
              if (target.startsWith('.soft')) {
                // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
                String relativePath = target.substring('.soft'.length);
                if (relativePath.isNotEmpty &&
                    (relativePath[0] == '/' || relativePath[0] == '\\')) {
                  relativePath = relativePath.substring(1);
                }
                targetPath = path.normalize(
                  path.join(softwareDir, relativePath),
                );
              } else if (target.startsWith('.down')) {
                // .down 开头，指向附件的下载目录（软件目录）
                final downloadDir = path.dirname(downloadPath);
                String relativePath = target.substring('.down'.length);
                if (relativePath.isNotEmpty &&
                    (relativePath[0] == '/' || relativePath[0] == '\\')) {
                  relativePath = relativePath.substring(1);
                }
                targetPath = path.normalize(
                  path.join(downloadDir, relativePath),
                );
              } else if (target.startsWith('.7ztemp')) {
                // .7ztemp 开头，相对于解压缩的目录
                String relativePath = target.substring('.7ztemp'.length);
                if (relativePath.isNotEmpty &&
                    (relativePath[0] == '/' || relativePath[0] == '\\')) {
                  relativePath = relativePath.substring(1);
                }
                targetPath = path.normalize(path.join(tempDir, relativePath));
              } else if (target.startsWith('bin')) {
                // bin 开头，则为存储目录\bin
                String relativePath = target.substring('bin'.length);
                if (relativePath.isNotEmpty &&
                    (relativePath[0] == '/' || relativePath[0] == '\\')) {
                  relativePath = relativePath.substring(1);
                }
                targetPath = path.normalize(
                  path.join(storagePath, 'bin', relativePath),
                );
              } else if (path.isAbsolute(target)) {
                targetPath = target;
              } else {
                // 默认相对路径相对于分类目录（存储目录\子分类目录）
                targetPath = path.join(categoryDir, target);
              }

              // 确保路径是绝对路径
              if (!path.isAbsolute(targetPath)) {
                targetPath = path.normalize(
                  path.absolute(categoryDir, targetPath),
                );
              } else {
                targetPath = path.normalize(targetPath);
              }

              // 检查路径安全性
              if (!_isPathWithinStorage(targetPath, storagePath)) {
                await _rollbackAddedPaths(addedPaths, onProgress);
                return (false, '目标路径超出存储目录范围: $targetPath', addedPaths);
              }

              if (await File(targetPath).exists()) {
                await File(targetPath).delete();
                onProgress?.call('正在执行附件指令...', progress, '删除文件: $targetPath');
              } else if (await Directory(targetPath).exists()) {
                await Directory(targetPath).delete(recursive: true);
                onProgress?.call('正在执行附件指令...', progress, '删除目录: $targetPath');
              } else {
                onProgress?.call(
                  '正在执行附件指令...',
                  progress,
                  '文件或目录不存在，跳过删除: $targetPath',
                );
              }
            }
            break;

          case 'move':
            // 移动文件 move [source] [destination]
            // .7ztemp 开头相对于解压缩的目录，bin 开头则为存储目录\bin
            if (parts.length < 3) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'move 命令需要两个参数: source 和 destination', addedPaths);
            }

            String source = parts[1];
            String destination = parts[2];

            // 解析 source 路径
            String sourcePath;
            final categoryDir = path.join(storagePath, category);
            if (source.startsWith('.down')) {
              // .down 开头，指向附件的下载目录（软件目录）
              final downloadDir = path.dirname(downloadPath);
              String relativePath = source.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(downloadDir, relativePath));
            } else if (source.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = source.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(softwareDir, relativePath));
            } else if (source.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = source.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(tempDir, relativePath));
            } else if (source.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = source.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(source)) {
              sourcePath = source;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              sourcePath = path.join(categoryDir, source);
            }

            // 解析 destination 路径
            String destPath;
            if (destination.startsWith('.down')) {
              // .down 开头，指向附件的下载目录（软件目录）
              final downloadDir = path.dirname(downloadPath);
              String relativePath = destination.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(downloadDir, relativePath));
            } else if (destination.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = destination.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(softwareDir, relativePath));
            } else if (destination.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = destination.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(tempDir, relativePath));
            } else if (destination.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = destination.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(destination)) {
              destPath = destination;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              destPath = path.join(categoryDir, destination);
            }

            // 确保路径是绝对路径
            if (!path.isAbsolute(sourcePath)) {
              sourcePath = path.normalize(
                path.absolute(softwareDir, sourcePath),
              );
            } else {
              sourcePath = path.normalize(sourcePath);
            }

            if (!path.isAbsolute(destPath)) {
              destPath = path.normalize(path.absolute(softwareDir, destPath));
            } else {
              destPath = path.normalize(destPath);
            }

            // 检查路径安全性
            if (!_isPathWithinStorage(sourcePath, storagePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源路径超出存储目录范围: $sourcePath', addedPaths);
            }

            if (!_isPathWithinStorage(destPath, storagePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目标路径超出存储目录范围: $destPath', addedPaths);
            }

            // 调试输出（仅在调试模式）
            if (kDebugMode) {
              onProgress?.call(
                '正在执行附件指令...',
                progress,
                '[DEBUG] move 路径解析: source="$source" -> "$sourcePath", destination="$destination" -> "$destPath"',
              );
            }

            final sourceFile = File(sourcePath);
            if (!await sourceFile.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源文件不存在: $sourcePath', addedPaths);
            }

            // 如果目标文件已存在，先删除
            final destFile = File(destPath);
            if (await destFile.exists()) {
              await destFile.delete();
            }

            // 确保目标目录存在
            final destDir = Directory(path.dirname(destPath));
            if (!await destDir.exists()) {
              await destDir.create(recursive: true);
            }

            // 移动文件
            await sourceFile.rename(destPath);

            onProgress?.call(
              '正在执行附件指令...',
              progress,
              '移动文件: $sourcePath -> $destPath',
            );
            break;

          case 'copy':
            // 复制文件 copy [source] [destination]
            // 路径处理与 move 相同
            if (parts.length < 3) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'copy 命令需要两个参数: source 和 destination', addedPaths);
            }

            String source = parts[1];
            String destination = parts[2];

            // 解析 source 路径（与 move 相同）
            String sourcePath;
            final categoryDir = path.join(storagePath, category);
            if (source.startsWith('.down')) {
              // .down 开头，指向附件的下载目录（软件目录）
              final downloadDir = path.dirname(downloadPath);
              String relativePath = source.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(downloadDir, relativePath));
            } else if (source.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = source.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(softwareDir, relativePath));
            } else if (source.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = source.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(path.join(tempDir, relativePath));
            } else if (source.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = source.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              sourcePath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(source)) {
              sourcePath = source;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              sourcePath = path.join(categoryDir, source);
            }

            // 解析 destination 路径（与 move 相同）
            String destPath;
            if (destination.startsWith('.down')) {
              // .down 开头，指向附件的下载目录（软件目录）
              final downloadDir = path.dirname(downloadPath);
              String relativePath = destination.substring('.down'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(downloadDir, relativePath));
            } else if (destination.startsWith('.soft')) {
              // .soft 开头，指向软件目录（存储目录\子分类目录\软件目录）
              String relativePath = destination.substring('.soft'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(softwareDir, relativePath));
            } else if (destination.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录
              String relativePath = destination.substring('.7ztemp'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(path.join(tempDir, relativePath));
            } else if (destination.startsWith('bin')) {
              // bin 开头，则为存储目录\bin
              String relativePath = destination.substring('bin'.length);
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              destPath = path.normalize(
                path.join(storagePath, 'bin', relativePath),
              );
            } else if (path.isAbsolute(destination)) {
              destPath = destination;
            } else {
              // 默认相对路径相对于分类目录（存储目录\子分类目录）
              destPath = path.join(categoryDir, destination);
            }

            // 确保路径是绝对路径
            // source 路径：如果已经通过前缀解析为绝对路径，直接规范化；否则相对于分类目录
            if (!path.isAbsolute(sourcePath)) {
              sourcePath = path.normalize(
                path.absolute(categoryDir, sourcePath),
              );
            } else {
              sourcePath = path.normalize(sourcePath);
            }

            // destination 路径：如果已经通过前缀解析为绝对路径，直接规范化；否则相对于分类目录
            if (!path.isAbsolute(destPath)) {
              destPath = path.normalize(path.absolute(categoryDir, destPath));
            } else {
              destPath = path.normalize(destPath);
            }

            // 检查路径安全性
            if (!_isPathWithinStorage(sourcePath, storagePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源路径超出存储目录范围: $sourcePath', addedPaths);
            }

            if (!_isPathWithinStorage(destPath, storagePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目标路径超出存储目录范围: $destPath', addedPaths);
            }

            final sourceFile = File(sourcePath);
            if (!await sourceFile.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '源文件不存在: $sourcePath', addedPaths);
            }

            // 如果目标文件已存在，先删除
            final destFile = File(destPath);
            if (await destFile.exists()) {
              await destFile.delete();
            }

            // 确保目标目录存在
            final destDir = Directory(path.dirname(destPath));
            if (!await destDir.exists()) {
              await destDir.create(recursive: true);
            }

            // 复制文件（与 move 的区别：使用 copy 而不是 rename）
            await sourceFile.copy(destPath);

            onProgress?.call(
              '正在执行附件指令...',
              progress,
              '复制文件: $sourcePath -> $destPath',
            );
            break;

          case 'addbin2path':
            // 将指定目录加入系统环境变量PATH中 Addbin2Path [dir]
            // 如果dir为空或未定义，则将存储目录\bin加入PATH
            String dirPath;
            if (parts.length < 2 || parts[1].isEmpty) {
              // dir 为空或未定义，使用存储目录\bin
              dirPath = path.join(storagePath, 'bin');
            } else {
              dirPath = parts[1];
            }

            // 对于附件，Addbin2Path 的路径应该相对于软件目录
            final dirCheck = _resolveAndCheckPath(
              dirPath,
              softwareDir, // 使用软件目录作为基准
              storagePath,
            );
            if (!dirCheck.$2) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '目录路径超出存储目录范围: ${dirCheck.$1}', addedPaths);
            }
            final resolvedDirPath = dirCheck.$1;

            final dir = Directory(resolvedDirPath);
            if (!await dir.exists()) {
              // 如果目录不存在，创建它
              await dir.create(recursive: true);
              onProgress?.call(
                '正在执行附件指令...',
                progress,
                '已创建目录: $resolvedDirPath',
              );
            }

            // 检查 PATH 中是否已存在该路径
            final normalizedPath = path.normalize(resolvedDirPath);
            final pathEnvResult = await Process.run('powershell', [
              '-Command',
              '[Environment]::GetEnvironmentVariable("PATH", "User")',
            ], runInShell: true);

            String currentPath = '';
            if (pathEnvResult.exitCode == 0) {
              currentPath = pathEnvResult.stdout.toString().trim();
            }

            // 检查路径是否已存在（不区分大小写，处理路径分隔符）
            final normalizedCurrentPath = currentPath.replaceAll('\\', '/');
            final normalizedTargetPath = normalizedPath.replaceAll('\\', '/');
            final pathParts = normalizedCurrentPath.split(';');
            bool pathExists = pathParts.any(
              (part) =>
                  part.trim().replaceAll('\\', '/').toLowerCase() ==
                  normalizedTargetPath.toLowerCase(),
            );

            if (pathExists) {
              onProgress?.call(
                '正在执行附件指令...',
                progress,
                'PATH 中已存在该路径，跳过: $normalizedPath',
              );
            } else {
              // 使用 setx 命令添加到用户环境变量 PATH
              final result = await Process.run('setx', [
                'PATH',
                '$currentPath;$normalizedPath',
              ], runInShell: true);

              if (result.exitCode != 0) {
                final output =
                    result.stdout.toString() + result.stderr.toString();
                if (!output.toLowerCase().contains('success')) {
                  await _rollbackAddedPaths(addedPaths, onProgress);
                  return (false, '添加环境变量失败: ${result.stderr}', addedPaths);
                }
              }

              onProgress?.call(
                '正在执行附件指令...',
                progress,
                '已添加目录到系统环境变量 PATH: $normalizedPath',
              );
            }
            break;

          case 'replace':
            // 替换文件中的字符串 replace [filepath] [needle] [replace]
            // filepath 相对于软件安装路径（存储目录/子分类文件夹/软件目录/）
            // 如果 filepath 以 .down 开头，则相对于安装包的下载地址
            // 如果 filepath 以 .7ztemp 开头，则相对于解压缩的目录（.7ztemp）
            // 支持反引号（`）作为 needle 和 replace 的定界符
            final parsed = _parseReplaceCommand(command);
            if (parsed == null) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, 'replace 命令解析失败，请检查命令格式', addedPaths);
            }

            String filePath = parsed.$1;
            String needle = parsed.$2;
            String replace = parsed.$3;

            // 解析文件路径
            String resolvedFilePath;
            String baseDirForCheck; // 用于路径安全检查的基准目录
            if (path.isAbsolute(filePath)) {
              resolvedFilePath = filePath;
              baseDirForCheck = softwareDir;
            } else if (filePath.startsWith('.down')) {
              // .down 开头，将 .down 部分替换为分类目录（$storagePath/$category）
              // 而不是 downloadPath 的目录部分，因为附件可能下载到软件目录下
              final categoryDir = path.join(storagePath, category);
              // 移除 .down 前缀，获取相对路径部分
              String relativePath = filePath.substring('.down'.length);
              // 移除开头的路径分隔符（如果有）
              if (relativePath.isNotEmpty &&
                  (relativePath[0] == '/' || relativePath[0] == '\\')) {
                relativePath = relativePath.substring(1);
              }
              // 使用 path.join 确保路径正确拼接
              resolvedFilePath = path.normalize(
                path.join(categoryDir, relativePath),
              );
              baseDirForCheck = categoryDir;

              // 调试输出（仅在调试模式）
              if (kDebugMode) {
                final isMainCommand =
                    onProgress != null &&
                    (onProgress.toString().contains('正在执行安装指令') ||
                        onProgress.toString().contains('正在执行附件指令'));
                onProgress?.call(
                  isMainCommand ? '正在执行安装指令...' : '正在执行附件指令...',
                  progress,
                  '[DEBUG] .down 路径解析: filePath="$filePath", downloadPath="$downloadPath", categoryDir="$categoryDir", relativePath="$relativePath", resolvedFilePath="$resolvedFilePath"',
                );
              }
            } else if (filePath.startsWith('.7ztemp')) {
              // .7ztemp 开头，相对于解压缩的目录（.7ztemp）
              final relativePath = filePath.substring('.7ztemp'.length);
              if (relativePath.startsWith('/') ||
                  relativePath.startsWith('\\')) {
                resolvedFilePath = path.join(
                  tempDir,
                  relativePath.substring(1),
                );
              } else {
                resolvedFilePath = path.join(tempDir, relativePath);
              }
              baseDirForCheck = tempDir;
            } else {
              // 其他情况，相对于软件安装路径
              resolvedFilePath = path.normalize(
                path.join(softwareDir, filePath),
              );
              baseDirForCheck = softwareDir;
            }

            // 确保 resolvedFilePath 是绝对路径
            if (!path.isAbsolute(resolvedFilePath)) {
              resolvedFilePath = path.normalize(
                path.absolute(baseDirForCheck, resolvedFilePath),
              );
            }

            // 检查路径安全性
            if (!_isPathWithinStorage(resolvedFilePath, storagePath)) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '文件路径超出存储目录范围: $resolvedFilePath', addedPaths);
            }

            final file = File(resolvedFilePath);
            if (!await file.exists()) {
              await _rollbackAddedPaths(addedPaths, onProgress);
              return (false, '文件不存在: $resolvedFilePath', addedPaths);
            }

            // 读取文件内容
            String content = await file.readAsString();

            // 处理 replace 参数的特殊值
            String processedReplace = replace;
            // 将 replace 中的 !softPath! 替换为软件安装路径
            if (processedReplace.contains('!softPath!')) {
              // !softPath! 表示当前安装的软件预期的安装路径
              // 将 softwareDir 中的路径分隔符统一为 Windows 风格（\）
              final normalizedSoftwareDir = softwareDir.replaceAll('/', '\\');
              processedReplace = processedReplace.replaceAll(
                '!softPath!',
                normalizedSoftwareDir,
              );
            }

            // 将 processedReplace 中的所有 / 替换为 \（确保路径分隔符统一为 Windows 风格）
            processedReplace = processedReplace.replaceAll('/', '\\');

            // 执行替换（替换所有匹配的部分）
            if (!content.contains(needle)) {
              onProgress?.call(
                '正在执行附件指令...',
                progress,
                '警告: 文件中未找到匹配的字符串: $needle',
              );
            } else {
              content = content.replaceAll(needle, processedReplace);
              // 写回文件
              await file.writeAsString(content);
              onProgress?.call(
                '正在执行附件指令...',
                progress,
                '已替换文件中的字符串: $resolvedFilePath',
              );
            }
            break;

          default:
            await _rollbackAddedPaths(addedPaths, onProgress);
            return (false, '未知命令: $cmd', addedPaths);
        }
      } catch (e) {
        await _rollbackAddedPaths(addedPaths, onProgress);
        return (false, '执行命令 "$command" 时发生错误: $e', addedPaths);
      }
    }

    // 所有命令执行完成，将临时目录内容移动到软件目录（如果临时目录存在）
    if (currentTempDir != null && await currentTempDir.exists()) {
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

  /// 撤销已添加到 PATH 的路径
  static Future<void> _rollbackAddedPaths(
    List<String> addedPaths,
    Function(String step, double progress, String? logMessage)? onProgress,
  ) async {
    if (addedPaths.isEmpty) return;

    onProgress?.call('正在撤销 PATH 修改...', 0.0, '开始撤销已添加的 PATH 路径...');

    try {
      // 获取当前 PATH
      final pathEnvResult = await Process.run('powershell', [
        '-Command',
        '[Environment]::GetEnvironmentVariable("PATH", "User")',
      ], runInShell: true);

      String currentPath = '';
      if (pathEnvResult.exitCode == 0) {
        currentPath = pathEnvResult.stdout.toString().trim();
      }

      // 移除所有已添加的路径
      String normalizedCurrentPath = currentPath.replaceAll('\\', '/');
      for (final addedPath in addedPaths) {
        final normalizedAddedPath = addedPath.replaceAll('\\', '/');
        final pathParts = normalizedCurrentPath.split(';');
        pathParts.removeWhere(
          (part) =>
              part.trim().replaceAll('\\', '/').toLowerCase() ==
              normalizedAddedPath.toLowerCase(),
        );
        normalizedCurrentPath = pathParts.join(';');
      }

      // 更新 PATH
      if (normalizedCurrentPath != currentPath.replaceAll('\\', '/')) {
        final result = await Process.run('setx', [
          'PATH',
          normalizedCurrentPath,
        ], runInShell: true);

        if (result.exitCode == 0) {
          onProgress?.call(
            '正在撤销 PATH 修改...',
            0.0,
            '已撤销 ${addedPaths.length} 个 PATH 路径',
          );
        } else {
          onProgress?.call('正在撤销 PATH 修改...', 0.0, '警告: 撤销 PATH 修改时可能失败');
        }
      }
    } catch (e) {
      onProgress?.call('正在撤销 PATH 修改...', 0.0, '警告: 撤销 PATH 修改时发生错误: $e');
    }
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
  /// 递归合并文件夹：将源文件夹的内容合并到目标文件夹
  /// 如果目标文件夹中已存在同名文件，则覆盖；如果存在同名文件夹，则递归合并
  static Future<void> _mergeDirectory(
    Directory sourceDir,
    Directory destDir,
  ) async {
    // 确保目标文件夹存在
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // 遍历源文件夹中的所有内容
    await for (final entity in sourceDir.list()) {
      final entityName = path.basename(entity.path);
      final destEntityPath = path.join(destDir.path, entityName);

      if (entity is File) {
        // 如果是文件，直接覆盖（如果目标文件存在）
        final destFile = File(destEntityPath);
        if (await destFile.exists()) {
          await destFile.delete();
        }
        await File(entity.path).copy(destFile.path);
      } else if (entity is Directory) {
        // 如果是文件夹，递归合并（只处理源目录中存在的文件，保留目标目录中的其他文件）
        final destSubDir = Directory(destEntityPath);
        await _mergeDirectory(Directory(entity.path), destSubDir);
      }
    }
    // 注意：不会删除目标目录中不在源目录中的文件，只覆盖同名文件
  }

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

  /// MySQL 初始化处理
  /// [mysqlDir] MySQL 安装目录路径
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> _initializeMysql(
    String mysqlDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 执行 mysqld --initialize-insecure
      onProgress?.call(
        '正在初始化 MySQL...',
        0.98,
        '执行 mysqld --initialize-insecure...',
      );
      final mysqldExe = path.join(mysqlDir, 'bin', 'mysqld.exe');
      final mysqldFile = File(mysqldExe);

      if (!await mysqldFile.exists()) {
        return (false, '未找到 mysqld.exe 文件: $mysqldExe');
      }

      final result = await Process.run(
        mysqldExe,
        ['--initialize-insecure'],
        runInShell: true,
        workingDirectory: mysqlDir,
      );

      if (result.exitCode != 0) {
        final errorOutput = result.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call('MySQL 初始化警告', 0.98, 'mysqld 初始化输出: $errorOutput');
        }
        // 即使退出码非0，也继续执行后续步骤（某些情况下可能已经初始化成功）
      } else {
        onProgress?.call('MySQL 初始化', 0.98, 'mysqld 初始化完成');
      }

      // 步骤1.5: 执行 mysqld -install
      onProgress?.call('正在安装 MySQL 服务...', 0.982, '执行 mysqld install...');
      final installResult = await Process.run(
        mysqldExe,
        ['--install-manual'],
        runInShell: true,
        workingDirectory: mysqlDir,
      );

      if (installResult.exitCode != 0) {
        final errorOutput = installResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'MySQL 服务安装警告',
            0.982,
            'mysqld -install 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（服务可能已经安装）
      } else {
        onProgress?.call('MySQL 服务安装', 0.982, 'mysqld 服务安装完成');
      }

      return (true, null);
    } catch (e) {
      return (false, 'MySQL 初始化失败: $e');
    }
  }

  /// PostgreSQL 初始化处理
  /// [pgsqlDir] PostgreSQL 安装目录路径
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> _initializePgsql(
    String pgsqlDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 执行 initdb.exe -D "pgsql目录\data" -E UTF-8 -U postgres
      onProgress?.call('正在初始化 PostgreSQL...', 0.98, '执行 initdb.exe 初始化数据库...');
      final initdbExe = path.join(pgsqlDir, 'bin', 'initdb.exe');
      final initdbFile = File(initdbExe);

      if (!await initdbFile.exists()) {
        return (false, '未找到 initdb.exe 文件: $initdbExe');
      }

      final dataDir = path.join(pgsqlDir, 'data');
      final initdbResult = await Process.run(
        initdbExe,
        ['-D', dataDir, '-E', 'UTF-8', '-U', 'postgres'],
        runInShell: true,
        workingDirectory: pgsqlDir,
      );

      if (initdbResult.exitCode != 0) {
        final errorOutput = initdbResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'PostgreSQL 初始化警告',
            0.98,
            'initdb 初始化输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（某些情况下可能已经初始化成功）
      } else {
        onProgress?.call('PostgreSQL 初始化', 0.98, 'initdb 初始化完成');
      }

      // 步骤2: 执行 pg_ctl.exe register -D "pgsql目录\data" -N PostgreSQL
      onProgress?.call(
        '正在注册 PostgreSQL 服务...',
        0.985,
        '执行 pg_ctl.exe register...',
      );
      final pgCtlExe = path.join(pgsqlDir, 'bin', 'pg_ctl.exe');
      final pgCtlFile = File(pgCtlExe);

      if (!await pgCtlFile.exists()) {
        return (false, '未找到 pg_ctl.exe 文件: $pgCtlExe');
      }

      final registerResult = await Process.run(
        pgCtlExe,
        ['register', '-D', dataDir, '-N', 'PostgreSQL'],
        runInShell: true,
        workingDirectory: pgsqlDir,
      );

      if (registerResult.exitCode != 0) {
        final errorOutput = registerResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'PostgreSQL 服务注册警告',
            0.985,
            'pg_ctl register 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（服务可能已经注册）
      } else {
        onProgress?.call('PostgreSQL 服务注册', 0.985, 'pg_ctl register 完成');
      }

      // 步骤3: 执行 sc config PostgreSQL start= demand
      onProgress?.call(
        '正在配置 PostgreSQL 服务...',
        0.99,
        '执行 sc config PostgreSQL start= demand...',
      );
      final configResult = await Process.run('sc', [
        'config',
        'PostgreSQL',
        'start=',
        'demand',
      ], runInShell: true);

      if (configResult.exitCode != 0) {
        final errorOutput = configResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'PostgreSQL 服务配置警告',
            0.99,
            'sc config 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续（服务可能已经配置）
      } else {
        onProgress?.call('PostgreSQL 服务配置', 0.99, 'sc config 完成');
      }

      return (true, null);
    } catch (e) {
      return (false, 'PostgreSQL 初始化失败: $e');
    }
  }

  /// MongoDB 初始化处理
  /// [mongodbDir] MongoDB 安装目录路径
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> _initializeMongodb(
    String mongodbDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 执行 mongod --config "mongodb目录\mongod.cfg" --install --serviceName "MongoDB"
      onProgress?.call('正在注册 MongoDB 服务...', 0.98, '执行 mongod --install...');
      // 先检查根目录，如果不存在再检查 bin 目录
      String mongodExe = path.join(mongodbDir, 'mongod.exe');
      File mongodFile = File(mongodExe);

      if (!await mongodFile.exists()) {
        // 如果根目录不存在，检查 bin 目录
        mongodExe = path.join(mongodbDir, 'bin', 'mongod.exe');
        mongodFile = File(mongodExe);
        if (!await mongodFile.exists()) {
          return (false, '未找到 mongod.exe 文件（已检查根目录和 bin 目录）');
        }
      }

      final mongodCfg = path.join(mongodbDir, 'mongod.cfg');
      final mongodCfgFile = File(mongodCfg);

      if (!await mongodCfgFile.exists()) {
        return (false, '未找到 mongod.cfg 文件: $mongodCfg');
      }

      final installResult = await Process.run(
        mongodExe,
        ['--config', mongodCfg, '--install', '--serviceName', 'MongoDB'],
        runInShell: true,
        workingDirectory: mongodbDir,
      );

      if (installResult.exitCode != 0) {
        final errorOutput = installResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'MongoDB 服务注册警告',
            0.98,
            'mongod --install 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续执行后续步骤（服务可能已经注册）
      } else {
        onProgress?.call('MongoDB 服务注册', 0.98, 'mongod --install 完成');
      }

      // 步骤2: 执行 sc config MongoDB start= demand
      onProgress?.call(
        '正在配置 MongoDB 服务...',
        0.99,
        '执行 sc config MongoDB start= demand...',
      );
      final configResult = await Process.run('sc', [
        'config',
        'MongoDB',
        'start=',
        'demand',
      ], runInShell: true);

      if (configResult.exitCode != 0) {
        final errorOutput = configResult.stderr.toString();
        if (errorOutput.isNotEmpty) {
          onProgress?.call(
            'MongoDB 服务配置警告',
            0.99,
            'sc config 输出: $errorOutput',
          );
        }
        // 即使退出码非0，也继续（服务可能已经配置）
      } else {
        onProgress?.call('MongoDB 服务配置', 0.99, 'sc config 完成');
      }

      return (true, null);
    } catch (e) {
      return (false, 'MongoDB 初始化失败: $e');
    }
  }

  /// phpMyAdmin 初始化处理
  /// [phpmyadminDir] phpMyAdmin 安装目录路径
  /// [onProgress] 进度回调
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> _initializePhpmyadmin(
    String phpmyadminDir, {
    Function(String step, double progress, String? logMessage)? onProgress,
  }) async {
    try {
      // 步骤1: 检查是否安装了 PHP 和 nginx
      onProgress?.call('正在检查依赖...', 0.98, '检查 PHP 和 nginx 是否已安装...');

      final storagePath = await ConfigService.getStoragePath();
      if (storagePath == null) {
        return (false, '存储目录未设置');
      }

      final softwareSource = await SoftwareSourceService.getSource();
      if (softwareSource == null) {
        return (false, '无法获取软件源');
      }

      // 检查 nginx 是否安装
      final nginx = softwareSource.servers.firstWhere(
        (s) => s.cate4?.toLowerCase() == 'nginx',
        orElse: () => Software(
          id: '',
          name: '',
          byte: 0,
          downloadURL: '',
          commands: [],
          attachments: [],
        ),
      );

      if (nginx.id.isEmpty) {
        return (false, 'nginx 未安装，请先安装 nginx');
      }

      final nginxDir = Directory('$storagePath/servers/${nginx.id}');
      if (!await nginxDir.exists()) {
        return (false, 'nginx 未安装，请先安装 nginx');
      }

      // 检查 PHP 是否安装
      final phpDir = Directory('$storagePath/php');
      if (!await phpDir.exists()) {
        return (false, 'PHP 未安装，请先安装 PHP');
      }

      bool hasPhp = false;
      await for (final entity in phpDir.list()) {
        if (entity is Directory) {
          hasPhp = true;
          break;
        }
      }

      if (!hasPhp) {
        return (false, 'PHP 未安装，请先安装 PHP');
      }

      // 步骤2: 检查是否已有同名项目
      onProgress?.call('正在检查项目...', 0.985, '检查是否已有同名项目...');

      final projectName = 'phpmyadmin';
      final servsDir = Directory(path.join(nginxDir.path, 'servs'));
      if (await servsDir.exists()) {
        final projectConfFile = File(
          path.join(servsDir.path, '$projectName.conf'),
        );
        if (await projectConfFile.exists()) {
          return (false, '项目名称 "$projectName" 已存在');
        }
      }

      // 步骤3: 获取默认 PHP 版本
      onProgress?.call('正在获取 PHP 版本...', 0.99, '获取默认 PHP 版本...');

      final phpBatPath = path.join(storagePath, 'bin', 'php.bat');
      final phpBatFile = File(phpBatPath);
      String? defaultPhpVersionId;

      if (await phpBatFile.exists()) {
        try {
          final content = await phpBatFile.readAsString();
          final lines = content.split('\n');
          if (lines.length >= 2) {
            final match = RegExp(r'"([^"]+)"').firstMatch(lines[1]);
            if (match != null) {
              final phpExePath = match.group(1);
              if (phpExePath != null) {
                final phpExeDir = path.dirname(phpExePath);
                defaultPhpVersionId = path.basename(phpExeDir);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('获取默认 PHP 版本失败: $e');
          }
        }
      }

      // 如果没有默认版本，尝试获取第一个已安装的 PHP 版本
      if (defaultPhpVersionId == null) {
        await for (final entity in phpDir.list()) {
          if (entity is Directory) {
            final phpId = path.basename(entity.path);
            final php = softwareSource.php.firstWhere(
              (s) => s.id == phpId,
              orElse: () => Software(
                id: '',
                name: '',
                byte: 0,
                downloadURL: '',
                commands: [],
                attachments: [],
              ),
            );
            if (php.id.isNotEmpty) {
              defaultPhpVersionId = php.id;
              break;
            }
          }
        }
      }

      if (defaultPhpVersionId == null) {
        return (false, '未找到可用的 PHP 版本');
      }

      // 步骤4: 创建普通 PHP 项目
      onProgress?.call('正在创建项目...', 0.995, '创建 phpMyAdmin 项目...');

      // 准备 nginx 项目环境
      final env = await NginxProjectHelper.prepareNginxProjectEnvironment(
        projectName,
        nginxDir.path,
      );
      if (env == null) {
        return (false, '准备 nginx 项目环境失败');
      }

      final lines = env.lines;

      // 配置 nginx 项目参数
      final nginxConfig = <String, dynamic>{
        'port': '80',
        'serverName': 'phpmyadmin.localhost',
        'root': phpmyadminDir.replaceAll('\\', '/'),
        'enableSsl': false,
        'rewriteRule': null,
      };

      // 修改端口
      NginxProjectHelper.updatePort(lines, nginxConfig['port'] as String);

      // 处理 SSL（不启用）
      final sslSuccess = await NginxProjectHelper.handleSslConfig(
        lines,
        nginxConfig,
        projectName,
        env.servsDir,
        (certPath, keyPath) async => false, // 不生成证书
      );
      if (!sslSuccess) {
        return (false, '处理 SSL 配置失败');
      }

      // 修改 server_name
      NginxProjectHelper.updateServerName(
        lines,
        nginxConfig['serverName'] as String? ?? '',
      );

      // 修改 root 路径
      NginxProjectHelper.updateRootPath(
        lines,
        nginxConfig['root'] as String? ?? '',
      );

      // 修改项目名称行
      NginxProjectHelper.updateProjectNameLines(lines, projectName);

      // 确保 PHP 配置文件存在
      onProgress?.call('正在检查 PHP 配置...', 0.995, '检查 PHP nginx 配置文件...');
      final phpConfigResult = await _ensurePhpConfigExists(
        nginxDir.path,
        defaultPhpVersionId,
      );
      if (!phpConfigResult.$1) {
        return (false, phpConfigResult.$2 ?? 'PHP 配置文件检查失败');
      }

      // 修改 PHP include 行
      NginxProjectHelper.updatePhpInclude(lines, defaultPhpVersionId);

      // 创建 subconf 文件（无伪静态规则）
      await NginxProjectHelper.createNormalPhpSubconf(
        projectName,
        null, // 无伪静态规则
        nginxDir.path,
        env.servsDir,
      );

      // 修改 include conf/preconf 行
      NginxProjectHelper.updatePreconfInclude(lines, projectName);

      // 添加数据库配置（不选择相关软件，传入空列表）
      NginxProjectHelper.addDatabaseConfig(lines, []);

      // 完成项目创建
      final serverName = nginxConfig['serverName'] as String? ?? '';
      final success = await NginxProjectHelper.finalizeProjectCreation(
        nginxDir.path,
        env.projectConfFile,
        lines,
        projectName,
        serverName,
        NginxProjectHelper.checkNginxConfig,
        _showNginxConfigErrorDialog,
        _isNginxRunning,
        _reloadNginx,
      );

      if (!success) {
        return (false, '创建项目失败');
      }

      return (true, null);
    } catch (e) {
      return (false, 'phpMyAdmin 初始化失败: $e');
    }
  }

  /// 确保 PHP 配置文件存在（用于普通 PHP 项目）
  /// [nginxDir] nginx 安装目录
  /// [phpVersionId] PHP 版本 ID
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> _ensurePhpConfigExists(
    String nginxDir,
    String phpVersionId,
  ) async {
    try {
      final phpConfPath = path.join(
        nginxDir,
        'conf',
        'php',
        '$phpVersionId.conf',
      );
      final phpConfFile = File(phpConfPath);

      if (!await phpConfFile.exists()) {
        // 复制示例文件
        final examplePath = path.join(
          nginxDir,
          'conf',
          'php',
          'php.conf.example',
        );
        final exampleFile = File(examplePath);

        if (!await exampleFile.exists()) {
          return (false, 'PHP 配置示例文件不存在: $examplePath');
        }

        final content = await exampleFile.readAsString();
        // 替换 fastcgi_pass 行中的 #--# 为默认端口（普通 PHP 项目通常使用 9000）
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains('fastcgi_pass') && lines[i].contains('#--#')) {
            lines[i] = lines[i].replaceAll('#--#', '9000');
            break;
          }
        }
        await phpConfFile.writeAsString(lines.join('\n'));
      }
      // 如果文件已存在，不需要更新（普通 PHP 项目不需要动态端口）

      return (true, null);
    } catch (e) {
      return (false, '确保 PHP 配置文件存在失败: $e');
    }
  }

  /// 显示 nginx 配置错误对话框（用于 NginxProjectHelper）
  static Future<void> _showNginxConfigErrorDialog(String output) async {
    // 在安装服务中，我们只记录错误，不显示对话框
    if (kDebugMode) {
      print('nginx 配置检查失败: $output');
    }
  }

  /// 检查 nginx 是否正在运行（用于 NginxProjectHelper）
  static Future<bool> _isNginxRunning() async {
    // 简化实现，总是返回 false（不自动重新加载）
    return false;
  }

  /// 重新加载 nginx（用于 NginxProjectHelper）
  static Future<void> _reloadNginx() async {
    // 在安装服务中，不自动重新加载 nginx
    if (kDebugMode) {
      print('跳过 nginx 重新加载（安装过程中）');
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
