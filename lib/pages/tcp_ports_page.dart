import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../tools/tcp_ports_tool.dart';
import '../services/notification_service.dart';

/// TCP端口占用列表页面
class TcpPortsPage extends StatefulWidget {
  const TcpPortsPage({super.key});

  @override
  State<TcpPortsPage> createState() => _TcpPortsPageState();
}

class _TcpPortsPageState extends State<TcpPortsPage> {
  Future<List<TcpPortInfo>>? _portsFuture;
  String? _sortColumn;
  bool _sortAscending = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _portsFuture = TcpPortsTool.getTcpPorts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshPorts() async {
    setState(() {
      _portsFuture = TcpPortsTool.getTcpPorts();
    });
  }

  /// 筛选和排序端口列表
  List<TcpPortInfo> _filterAndSortPorts(List<TcpPortInfo> ports) {
    // 筛选 - 直接从controller读取，避免状态更新导致的输入法问题
    List<TcpPortInfo> filtered = ports;
    final searchKeyword = _searchController.text;
    if (searchKeyword.isNotEmpty) {
      final keyword = searchKeyword.toLowerCase();
      filtered = ports.where((port) {
        return port.exe.toLowerCase().contains(keyword) ||
            port.pid.toString().contains(keyword) ||
            port.localaddress.toLowerCase().contains(keyword) ||
            port.port.toString().contains(keyword) ||
            port.status.toLowerCase().contains(keyword) ||
            (port.exePath?.toLowerCase().contains(keyword) ?? false);
      }).toList();
    }

    // 排序
    if (_sortColumn != null) {
      filtered.sort((a, b) {
        int comparison = 0;
        switch (_sortColumn) {
          case 'exe':
            comparison = a.exe.compareTo(b.exe);
            break;
          case 'pid':
            comparison = a.pid.compareTo(b.pid);
            break;
          case 'localaddress':
            comparison = a.localaddress.compareTo(b.localaddress);
            break;
          case 'port':
            comparison = a.port.compareTo(b.port);
            break;
          case 'status':
            comparison = a.status.compareTo(b.status);
            break;
          case 'exepath':
            final aPath = a.exePath ?? '';
            final bPath = b.exePath ?? '';
            comparison = aPath.compareTo(bPath);
            break;
        }
        return _sortAscending ? comparison : -comparison;
      });
    }

    return filtered;
  }

  /// 切换排序
  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  /// 构建可排序的表头
  Widget _buildSortableHeader(
    String label,
    String column,
    double width, {
    bool numeric = false,
    bool center = false,
  }) {
    final isSorted = _sortColumn == column;
    return InkWell(
      onTap: () => _onSort(column),
      child: Container(
        alignment: Alignment.center, // 所有表头居中
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // 所有表头居中
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: isSorted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 4),
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建表格单元格
  Widget _buildTableCell(
    String text,
    double width, {
    bool center = false,
    bool left = true,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        alignment: center
            ? Alignment.center
            : (left ? Alignment.centerLeft : Alignment.centerRight),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Tooltip(
          message: text,
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            textAlign: center
                ? TextAlign.center
                : (left ? TextAlign.left : TextAlign.right),
          ),
        ),
      ),
    );
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
                  title: const Text('TCP端口占用列表'),
                  backgroundColor: Colors.transparent, // 背景透明，使用外层Container的颜色
                  elevation: 0, // 移除阴影
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)), // 圆角
                  ),
                  actions: [
                    // 搜索框
                    SizedBox(
                      width: 250,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            isDense: true,
                          ),
                          onChanged: (value) {
                            // 只更新UI，不触发其他状态更新，避免输入法问题
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshPorts,
                      tooltip: '刷新',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<TcpPortInfo>>(
        future: _portsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('获取端口占用信息失败: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshPorts,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          final allPorts = snapshot.data ?? [];

          if (allPorts.isEmpty) {
            return const Center(child: Text('没有端口占用信息'));
          }

          // 筛选和排序
          final filteredPorts = _filterAndSortPorts(allPorts);

          return Column(
            children: [
              // 列表
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 计算可用宽度（减去padding和列间距）
                    final availableWidth = constraints.maxWidth;
                    const columnSpacing = 12.0;
                    const totalSpacing = columnSpacing * 5; // 6列之间有5个间距
                    final usableWidth = availableWidth - totalSpacing;

                    // 定义列的权重比例（总和为1.0）
                    // 列顺序：pid | 进程名 | 端口 | 状态 | 本地地址 | 可执行路径
                    const columnWeights = {
                      'pid': 0.10, // PID 10%
                      'exe': 0.25, // 进程名 25%（包含菜单按钮）
                      'port': 0.10, // 端口 10%
                      'status': 0.12, // 状态 15%
                      'localaddress': 0.15, // 本地地址 18%
                      'exepath': 0.33, // 可执行路径 22%
                    };

                    // 计算每列的实际宽度（按新顺序）
                    final pidWidth = usableWidth * columnWeights['pid']!;
                    final exeWidth = usableWidth * columnWeights['exe']!;
                    final portWidth = usableWidth * columnWeights['port']!;
                    final statusWidth = usableWidth * columnWeights['status']!;
                    final localaddressWidth =
                        usableWidth * columnWeights['localaddress']!;
                    final exepathWidth =
                        usableWidth * columnWeights['exepath']!;

                    return SingleChildScrollView(
                      child: Table(
                        columnWidths: {
                          0: FixedColumnWidth(pidWidth),
                          1: FixedColumnWidth(exeWidth),
                          2: FixedColumnWidth(portWidth),
                          3: FixedColumnWidth(statusWidth),
                          4: FixedColumnWidth(localaddressWidth),
                          5: FixedColumnWidth(exepathWidth),
                        },
                        border: TableBorder(
                          horizontalInside: BorderSide(
                            color: Theme.of(context).dividerColor,
                            width: 0.5,
                          ),
                        ),
                        children: [
                          // 表头
                          TableRow(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                            ),
                            children: [
                              _buildSortableHeader(
                                'PID',
                                'pid',
                                pidWidth,
                                numeric: true,
                                center: true,
                              ),
                              _buildSortableHeader('进程名', 'exe', exeWidth),
                              _buildSortableHeader(
                                '端口',
                                'port',
                                portWidth,
                                numeric: true,
                                center: true,
                              ),
                              _buildSortableHeader(
                                '状态',
                                'status',
                                statusWidth,
                                center: true,
                              ),
                              _buildSortableHeader(
                                '本地地址',
                                'localaddress',
                                localaddressWidth,
                              ),
                              _buildSortableHeader(
                                '可执行路径',
                                'exepath',
                                exepathWidth,
                              ),
                            ],
                          ),
                          // 数据行
                          ...filteredPorts.map((port) {
                            return TableRow(
                              children: [
                                // 列顺序：pid | 进程名 | 端口 | 状态 | 本地地址 | 可执行路径
                                _buildTableCell(
                                  port.pid.toString(),
                                  pidWidth,
                                  center: true,
                                ),
                                TableCell(
                                  verticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Tooltip(
                                            message: port.exe,
                                            child: Text(
                                              port.exe,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                              textAlign: TextAlign.left,
                                            ),
                                          ),
                                        ),
                                        // 菜单按钮（缩小）- 仅当可执行路径不为空且进程名不是svchost.exe时显示
                                        if (port.exePath != null &&
                                            port.exePath!.isNotEmpty &&
                                            port.exe.toLowerCase() !=
                                                'svchost.exe')
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                              Icons.more_vert,
                                              size: 16,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 24,
                                              minHeight: 24,
                                            ),
                                            iconSize: 16,
                                            onSelected: (value) {
                                              if (value == 'open_directory') {
                                                if (port.exePath != null &&
                                                    port.exePath!.isNotEmpty) {
                                                  _openDirectory(
                                                    context,
                                                    port.exePath!,
                                                  );
                                                }
                                              } else if (value ==
                                                  'kill_process') {
                                                _killProcess(
                                                  context,
                                                  port.pid,
                                                  port.exe,
                                                );
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              if (port.exePath != null &&
                                                  port.exePath!.isNotEmpty)
                                                const PopupMenuItem<String>(
                                                  value: 'open_directory',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.folder_open,
                                                        size: 18,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text('打开目录'),
                                                    ],
                                                  ),
                                                ),
                                              const PopupMenuItem<String>(
                                                value: 'kill_process',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.cancel,
                                                      size: 18,
                                                      color: Colors.red,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text('杀死进程'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                _buildTableCell(
                                  port.port.toString(),
                                  portWidth,
                                  center: true,
                                ),
                                _buildTableCell(
                                  port.status,
                                  statusWidth,
                                  center: true,
                                ),
                                _buildTableCell(
                                  port.localaddress,
                                  localaddressWidth,
                                ),
                                _buildTableCell(
                                  port.exePath ?? '',
                                  exepathWidth,
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // 底部信息栏
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(children: [Text('共 ${filteredPorts.length} 个连接')]),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 打开程序目录
  Future<void> _openDirectory(BuildContext context, String exePath) async {
    try {
      final file = File(exePath);
      if (!await file.exists()) {
        await NotificationService.showError(
          title: '错误',
          message: '文件不存在: $exePath',
        );
        return;
      }

      final dirPath = path.dirname(exePath);
      final normalizedPath = dirPath.replaceAll('/', '\\');

      if (kDebugMode) {
        print('[TCP端口工具] 打开目录: $normalizedPath');
      }

      final result = await Process.run('explorer', [
        normalizedPath,
      ], runInShell: true);

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      if (context.mounted) {
        await NotificationService.showError(
          title: '打开失败',
          message: '打开目录时发生错误: $e',
        );
      }
    }
  }

  /// 杀死进程
  Future<void> _killProcess(
    BuildContext context,
    int pid,
    String exeName,
  ) async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('确认杀死进程'),
        content: Text('确定要杀死进程 "$exeName" (PID: $pid) 吗？\n\n此操作可能导致程序异常退出。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认杀死'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (kDebugMode) {
        print('[TCP端口工具] 杀死进程: PID=$pid, 名称=$exeName');
      }

      // 使用 taskkill 命令杀死进程
      final result = await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        pid.toString(),
      ], runInShell: true);

      if (result.exitCode == 0) {
        await NotificationService.showSuccess(
          title: '成功',
          message: '进程 "$exeName" (PID: $pid) 已终止',
        );
        // 刷新列表
        _refreshPorts();
      } else {
        final errorMsg = result.stderr.toString();
        await NotificationService.showError(
          title: '失败',
          message: '无法终止进程: $errorMsg',
        );
      }
    } catch (e) {
      if (context.mounted) {
        await NotificationService.showError(
          title: '错误',
          message: '杀死进程时发生错误: $e',
        );
      }
    }
  }
}
