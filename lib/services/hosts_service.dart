import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Hosts条目数据模型
class HostsEntry {
  final String ip;
  final String domain;
  final bool enabled;
  final String? trailingComment;
  final int originalLineIndex;
  final String leadingSpaces;

  HostsEntry({
    required this.ip,
    required this.domain,
    required this.enabled,
    this.trailingComment,
    required this.originalLineIndex,
    this.leadingSpaces = '',
  });

  /// 创建新条目（用于新建）
  HostsEntry.newEntry({
    required this.ip,
    required this.domain,
    this.enabled = true,
    this.trailingComment,
    this.leadingSpaces = '',
  }) : originalLineIndex = -1;

  /// 转换为hosts文件行格式
  String toHostsLine() {
    final line = '$ip $domain';
    if (trailingComment != null && trailingComment!.isNotEmpty) {
      return '$line $trailingComment';
    }
    return line;
  }

  /// 复制并修改
  HostsEntry copyWith({
    String? ip,
    String? domain,
    bool? enabled,
    String? trailingComment,
    String? leadingSpaces,
  }) {
    return HostsEntry(
      ip: ip ?? this.ip,
      domain: domain ?? this.domain,
      enabled: enabled ?? this.enabled,
      trailingComment: trailingComment ?? this.trailingComment,
      originalLineIndex: originalLineIndex,
      leadingSpaces: leadingSpaces ?? this.leadingSpaces,
    );
  }
}

/// Hosts文件服务类
class HostsService {
  static const String _hostsPath = r'C:\Windows\System32\drivers\etc\hosts';

  /// 验证IP地址格式（IPv4或IPv6）
  static bool _isValidIp(String ip) {
    // IPv4格式
    final ipv4Regex = RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    );
    if (ipv4Regex.hasMatch(ip)) {
      return true;
    }

    // IPv6格式（简化验证）
    final ipv6Regex = RegExp(
      r'^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^::$',
    );
    if (ipv6Regex.hasMatch(ip)) {
      return true;
    }

    // 支持简化的IPv6格式
    if (ip.contains(':') && ip.split(':').length <= 8) {
      return true;
    }

    return false;
  }

  /// 解析hosts文件
  static List<HostsEntry> _parseHosts(List<String> lines) {
    final entries = <HostsEntry>[];
    final regex = RegExp(r'^(\s*)(#?\s*)([0-9a-fA-F:.]+)(\s+)(\S+)(.*)$');

    // 检查是否有17行连续的#开头的注释
    int i = 0;
    while (i < lines.length) {
      if (i + 17 <= lines.length) {
        bool isCommentBlock = true;
        for (int j = 0; j < 17; j++) {
          final line = lines[i + j].trim();
          if (!line.startsWith('#')) {
            isCommentBlock = false;
            break;
          }
        }

        if (isCommentBlock) {
          i += 17;
          continue;
        }
      }

      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      final match = regex.firstMatch(line);
      if (match != null) {
        final leadingSpaces = match.group(1) ?? '';
        final isCommented = (match.group(2) ?? '').contains('#');
        final ip = match.group(3)?.trim() ?? '';
        final domain = match.group(5)?.trim() ?? '';
        final trailing = match.group(6)?.trim() ?? '';

        if (_isValidIp(ip) && domain.isNotEmpty) {
          entries.add(
            HostsEntry(
              ip: ip,
              domain: domain,
              enabled: !isCommented,
              trailingComment: trailing.isNotEmpty ? trailing : null,
              originalLineIndex: i,
              leadingSpaces: leadingSpaces,
            ),
          );
        }
      }

      i++;
    }

    return entries;
  }

  /// 读取并解析hosts文件
  static Future<({List<HostsEntry> entries, List<String> originalLines})> loadHosts() async {
    final file = File(_hostsPath);
    if (!await file.exists()) {
      throw Exception('hosts文件不存在');
    }

    final lines = await file.readAsLines();
    final entries = _parseHosts(lines);

    return (entries: entries, originalLines: lines);
  }

  /// 更新hosts文件
  static Future<bool> updateHosts(
    List<HostsEntry> entries,
    List<String> originalLines,
  ) async {
    try {
      // 构建完整的文件内容
      final newLines = <String>[];

      // 1. 处理原始文件中的行
      for (int i = 0; i < originalLines.length; i++) {
        final line = originalLines[i];
        final regex = RegExp(r'^(\s*)(#?\s*)([0-9a-fA-F:.]+)(\s+)(\S+)(.*)$');
        final match = regex.firstMatch(line);

        if (match != null) {
          // 这是一个hosts条目行
          final entryIndex = entries.indexWhere(
            (e) => e.originalLineIndex == i && e.originalLineIndex != -1,
          );

          if (entryIndex != -1) {
            // 这个条目被修改了，使用新内容
            final entry = entries[entryIndex];
            final prefix = entry.enabled ? '' : '# ';
            final lineContent = entry.toHostsLine();
            newLines.add('${entry.leadingSpaces}$prefix$lineContent');
          }
          // 如果条目被删除，不添加到新内容中
        } else {
          // 不是hosts条目行，保留原样
          newLines.add(line);
        }
      }

      // 2. 添加新建的条目
      final newEntries = entries.where((e) => e.originalLineIndex == -1).toList();
      for (final entry in newEntries) {
        final prefix = entry.enabled ? '' : '# ';
        final lineContent = entry.toHostsLine();
        newLines.add('$prefix$lineContent');
      }

      // 3. 构建完整的文件内容
      final content = newLines.join('\n');

      // 4. 创建临时文件
      final tempDir = Directory.systemTemp;
      final tempFile = File(path.join(tempDir.path, 'hosts.tmp'));

      // 写入临时文件
      await tempFile.writeAsString(content);

      // 5. 读取保存前的hosts文件内容用于对比
      String? hostsContentBefore;
      try {
        hostsContentBefore = await File(_hostsPath).readAsString();
      } catch (e) {
        if (kDebugMode) {
          print('读取保存前的hosts文件失败: $e');
        }
      }

      // 6. 使用PowerShell命令更新hosts文件
      final tempFilePath = tempFile.path
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "''");
      final hostsPath = _hostsPath
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "''");

      final psCommand =
          'Start-Process "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList @(\'-NoProfile\', \'-Command\', \'whoami /groups | findstr S-1-16; attrib -R "$hostsPath"; Set-Content -Path "$hostsPath" -Value (Get-Content "$tempFilePath" -Raw)\')';

      if (kDebugMode) {
        print('=== 执行PowerShell命令更新hosts ===');
        print('临时文件: ${tempFile.path}');
        print('命令: $psCommand');
      }

      // 执行PowerShell命令（静默执行）
      bool success = false;
      try {
        await Process.run('powershell', [
          '-Command',
          psCommand,
        ], runInShell: true);

        // 等待操作完成
        await Future.delayed(const Duration(milliseconds: 2000));

        // 读取保存后的hosts文件内容进行对比
        try {
          final hostsContentAfter = await File(_hostsPath).readAsString();

          if (hostsContentBefore != null) {
            if (hostsContentBefore == hostsContentAfter) {
              success = false;
            } else {
              success = true;
            }
          } else {
            success = hostsContentAfter.isNotEmpty;
          }
        } catch (e) {
          if (kDebugMode) {
            print('读取保存后的hosts文件失败: $e');
          }
          success = false;
        }
      } catch (e) {
        if (kDebugMode) {
          print('PowerShell执行异常: $e');
        }
        success = false;
      }

      // 清理临时文件
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // 忽略清理错误
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('更新hosts文件异常: $e');
      }
      return false;
    }
  }

  /// 确保域名在hosts文件中指向127.0.0.1
  /// 如果域名已存在但指向其他IP，则修改为127.0.0.1
  /// 如果域名不存在，则新建一个指向127.0.0.1的条目
  static Future<bool> ensureDomainPointsToLocalhost(String domain) async {
    try {
      // 加载hosts文件
      final result = await loadHosts();
      final entries = result.entries;
      final originalLines = result.originalLines;

      // 查找域名是否已存在
      final existingEntryIndex = entries.indexWhere((e) => e.domain == domain);

      if (existingEntryIndex != -1) {
        // 域名已存在
        final entry = entries[existingEntryIndex];
        if (entry.ip == '127.0.0.1' && entry.enabled) {
          // 已经指向127.0.0.1且已启用，无需修改
          return true;
        } else {
          // 修改为指向127.0.0.1并启用
          entries[existingEntryIndex] = entry.copyWith(
            ip: '127.0.0.1',
            enabled: true,
          );
        }
      } else {
        // 域名不存在，新建一个指向127.0.0.1的条目
        entries.add(
          HostsEntry.newEntry(
            ip: '127.0.0.1',
            domain: domain,
            enabled: true,
          ),
        );
      }

      // 更新hosts文件
      return await updateHosts(entries, originalLines);
    } catch (e) {
      if (kDebugMode) {
        print('确保域名指向localhost失败: $e');
      }
      return false;
    }
  }

  /// 检查是否为IPv4地址
  static bool isIPv4(String address) {
    final ipv4Regex = RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    );
    return ipv4Regex.hasMatch(address);
  }

  /// 检查是否为IPv6地址
  static bool isIPv6(String address) {
    final ipv6Regex = RegExp(
      r'^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^::$',
    );
    if (ipv6Regex.hasMatch(address)) {
      return true;
    }
    // 支持简化的IPv6格式
    if (address.contains(':') && address.split(':').length <= 8) {
      return true;
    }
    return false;
  }
}

