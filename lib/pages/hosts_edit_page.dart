import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';

/// Hosts条目数据模型
class HostsEntry {
  final String ip;
  final String domain;
  final bool enabled;
  final String? trailingComment; // 行后的注释内容
  final int originalLineIndex; // 原始行号（用于定位）
  final String leadingSpaces; // 行前的空格（用于保留格式）

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

/// Hosts编辑页面
class HostsEditPage extends StatefulWidget {
  const HostsEditPage({super.key});

  @override
  State<HostsEditPage> createState() => _HostsEditPageState();
}

class _HostsEditPageState extends State<HostsEditPage> {
  List<HostsEntry> _entries = [];
  List<String> _originalLines = []; // 保存原始所有行（包括非匹配行）
  bool _isLoading = true;
  bool _hasChanges = false;
  final String _hostsPath = r'C:\Windows\System32\drivers\etc\hosts';

  @override
  void initState() {
    super.initState();
    _loadHosts();
  }

  /// 加载hosts文件
  Future<void> _loadHosts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final file = File(_hostsPath);
      if (!await file.exists()) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('hosts文件不存在')));
        }
        return;
      }

      final lines = await file.readAsLines();
      _originalLines = List.from(lines);
      _entries = _parseHosts(lines);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取hosts文件失败: $e')));
      }
    }
  }

  /// 解析hosts文件
  List<HostsEntry> _parseHosts(List<String> lines) {
    final entries = <HostsEntry>[];
    // 匹配格式：可选的空格 + 可选的# + IP地址（不允许包含空格）+ 一个或多个空格/制表符 + 域名 + 可选的注释
    // IP地址部分使用更精确的匹配，不允许包含空格
    final regex = RegExp(r'^(\s*)(#?\s*)([0-9a-fA-F:.]+)(\s+)(\S+)(.*)$');

    // 检查是否有17行连续的#开头的注释
    int i = 0;
    while (i < lines.length) {
      // 检查从当前位置开始是否有17行连续的#开头的注释
      if (i + 17 <= lines.length) {
        bool isCommentBlock = true;
        for (int j = 0; j < 17; j++) {
          final line = lines[i + j].trim();
          // 检查是否是#开头的注释行（允许行前有空格）
          if (!line.startsWith('#')) {
            isCommentBlock = false;
            break;
          }
        }

        // 如果找到17行连续的#开头的注释，跳过这个块
        if (isCommentBlock) {
          i += 17;
          continue;
        }
      }

      // 正常处理当前行
      final line = lines[i];
      final trimmed = line.trim();

      // 忽略空行
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

        // 验证IP地址格式
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

  /// 使用PowerShell命令更新hosts文件
  Future<bool> _updateHostsWithPowerShell() async {
    try {
      // 构建完整的文件内容
      final newLines = <String>[];

      // 1. 处理原始文件中的行
      for (int i = 0; i < _originalLines.length; i++) {
        final line = _originalLines[i];
        final regex = RegExp(r'^(\s*)(#?\s*)([0-9a-fA-F:.]+)(\s+)(\S+)(.*)$');
        final match = regex.firstMatch(line);

        if (match != null) {
          // 这是一个hosts条目行
          final entryIndex = _entries.indexWhere(
            (e) => e.originalLineIndex == i && e.originalLineIndex != -1,
          );

          if (entryIndex != -1) {
            // 这个条目被修改了，使用新内容
            final entry = _entries[entryIndex];
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
      final newEntries = _entries
          .where((e) => e.originalLineIndex == -1)
          .toList();
      for (final entry in newEntries) {
        final prefix = entry.enabled ? '' : '# ';
        final lineContent = entry.toHostsLine();
        newLines.add('$prefix$lineContent');
      }

      // 3. 构建完整的文件内容
      final content = newLines.join('\n');

      // 4. 创建临时文件
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}\\hosts.tmp');

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

      // 6. 使用新的PowerShell命令更新hosts文件
      // 转义路径中的反斜杠和引号
      final tempFilePath = tempFile.path
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "''");
      final hostsPath = _hostsPath
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "''");

      // 构建PowerShell命令（静默执行）
      // Start-Process "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile', '-Command', 'whoami /groups | findstr S-1-16; attrib -R C:\Windows\System32\drivers\etc\hosts; Set-Content -Path C:\Windows\System32\drivers\etc\hosts -Value (Get-Content "C:\Users\Administrator\AppData\Local\Temp\hosts.tmp" -Raw)')
      final psCommand =
          'Start-Process "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList @(\'-NoProfile\', \'-Command\', \'whoami /groups | findstr S-1-16; attrib -R "$hostsPath"; Set-Content -Path "$hostsPath" -Value (Get-Content "$tempFilePath" -Raw)\')';

      if (kDebugMode) {
        print('=== 执行PowerShell命令 ===');
        print('临时文件: ${tempFile.path}');
        print('命令: $psCommand');
        print('========================');
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

          // 对比保存前后的内容
          if (hostsContentBefore != null) {
            // 如果内容相同，说明保存失败
            if (hostsContentBefore == hostsContentAfter) {
              success = false;
            } else {
              // 内容不同，说明保存成功
              success = true;
            }
          } else {
            // 如果无法读取保存前的内容，至少检查保存后的内容是否不为空
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
          print('=== PowerShell执行异常 ===');
          print('错误: $e');
          print('========================');
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
        print('=== 更新hosts文件异常 ===');
        print('错误: $e');
        print('========================');
      }
      return false;
    }
  }

  /// 验证IP地址格式（IPv4或IPv6）
  bool _isValidIp(String ip) {
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

  /// 切换条目启用状态
  void _toggleEntry(int index) {
    setState(() {
      _entries[index] = _entries[index].copyWith(
        enabled: !_entries[index].enabled,
      );
      _hasChanges = true;
    });
  }

  /// 删除条目
  void _deleteEntry(int index) {
    setState(() {
      _entries.removeAt(index);
      _hasChanges = true;
    });
  }

  /// 新建条目
  void _addEntry() {
    showDialog(
      context: context,
      builder: (context) => _AddEntryDialog(
        onAdd: (ip, domain) {
          if (!_isValidIp(ip)) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('IP地址格式不正确')));
            return;
          }

          setState(() {
            _entries.add(
              HostsEntry.newEntry(ip: ip, domain: domain, enabled: true),
            );
            _hasChanges = true;
          });
        },
      ),
    );
  }

  /// 编辑条目
  void _editEntry(int index) {
    final entry = _entries[index];
    showDialog(
      context: context,
      builder: (context) => _AddEntryDialog(
        initialIp: entry.ip,
        initialDomain: entry.domain,
        onAdd: (ip, domain) {
          if (!_isValidIp(ip)) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('IP地址格式不正确')));
            return;
          }

          setState(() {
            _entries[index] = entry.copyWith(ip: ip, domain: domain);
            _hasChanges = true;
          });
        },
      ),
    );
  }

  /// 打开hosts文件（使用默认打开方式）
  Future<void> _openHostsFile() async {
    try {
      // 使用 Windows 的 start 命令打开文件
      await Process.run('cmd', [
        '/c',
        'start',
        '',
        _hostsPath,
      ], runInShell: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开hosts文件: $e')));
      }
    }
  }

  /// 保存hosts文件
  Future<void> _saveHosts() async {
    try {
      // 检查文件是否存在
      final file = File(_hostsPath);
      if (!await file.exists()) {
        throw Exception('hosts文件不存在: $_hostsPath');
      }

      // 使用PowerShell命令来修改hosts文件
      final success = await _updateHostsWithPowerShell();

      if (!success) {
        throw Exception(
          '无法保存hosts文件。\n\n'
          '操作可能被拒绝或被杀毒软件拦截。\n\n'
          '请尝试：\n'
          '1. 确保在UAC提示时点击"是"授予管理员权限\n'
          '2. 检查杀毒软件是否拦截了文件修改操作\n'
          '3. 检查hosts文件是否被其他程序占用\n'
          '4. 尝试以管理员身份运行程序',
        );
      }

      // 重新加载
      await _loadHosts();

      setState(() {
        _hasChanges = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        // 显示系统通知
        final errorMessage = e.toString().contains('管理员权限')
            ? e.toString()
            : '保存hosts文件失败，可能需要管理员权限。请尝试以管理员身份运行程序。\n错误详情: $e';
        await NotificationService.showError(
          title: '保存失败',
          message: errorMessage,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // 背景透明
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 8),
        child: Container(
          margin: const EdgeInsets.all(8), // 外部边距
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), // 圆角
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12), // 圆角裁剪
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // 模糊效果
              child: Container(
                decoration: BoxDecoration(
                  color:
                      (Theme.of(context).appBarTheme.backgroundColor ??
                              Theme.of(context).colorScheme.surface)
                          .withValues(alpha: 0.7), // 半透明背景
                  borderRadius: BorderRadius.circular(12), // 圆角
                ),
                child: AppBar(
                  title: const Text('编辑hosts文件'),
                  backgroundColor: Colors.transparent, // 背景透明，使用外层Container的颜色
                  elevation: 0, // 移除阴影
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)), // 圆角
                  ),
                  actions: [
                    // 打开hosts文件按钮
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: _openHostsFile,
                      tooltip: '打开hosts文件',
                    ),
                    if (_hasChanges)
                      IconButton(
                        icon: const Icon(Icons.save),
                        onPressed: _saveHosts,
                        tooltip: '保存',
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 工具栏
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _addEntry,
                        icon: const Icon(Icons.add),
                        label: const Text('新建'),
                      ),
                      const Spacer(),
                      if (_hasChanges)
                        Text(
                          '有未保存的更改',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 条目列表
                Expanded(
                  child: _entries.isEmpty
                      ? Center(
                          child: Text(
                            '暂无hosts条目',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _buildEntryItem(entry, index);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  /// 构建条目项
  Widget _buildEntryItem(HostsEntry entry, int index) {
    return ListTile(
      title: Text(
        entry.domain,
        style: TextStyle(
          decoration: entry.enabled ? null : TextDecoration.lineThrough,
          color: entry.enabled ? null : Colors.grey,
        ),
      ),
      subtitle: Text(
        entry.ip,
        style: TextStyle(color: entry.enabled ? null : Colors.grey),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: entry.enabled, onChanged: (_) => _toggleEntry(index)),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editEntry(index),
            tooltip: '编辑',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _deleteEntry(index),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }
}

/// 添加/编辑条目对话框
class _AddEntryDialog extends StatefulWidget {
  final String? initialIp;
  final String? initialDomain;
  final Function(String ip, String domain) onAdd;

  const _AddEntryDialog({
    this.initialIp,
    this.initialDomain,
    required this.onAdd,
  });

  @override
  State<_AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<_AddEntryDialog> {
  final _ipController = TextEditingController();
  final _domainController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ipController.text = widget.initialIp ?? '';
    _domainController.text = widget.initialDomain ?? '';
  }

  @override
  void dispose() {
    _ipController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialIp == null ? '新建条目' : '编辑条目'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'IP地址',
              hintText: '127.0.0.1 或 ::1',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _domainController,
            decoration: const InputDecoration(
              labelText: '域名',
              hintText: 'example.com',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final ip = _ipController.text.trim();
            final domain = _domainController.text.trim();

            if (ip.isEmpty || domain.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('IP地址和域名不能为空')));
              return;
            }

            widget.onAdd(ip, domain);
            Navigator.of(context).pop();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
