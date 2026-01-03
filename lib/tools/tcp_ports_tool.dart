import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../pages/tcp_ports_page.dart';

/// TCP端口占用信息数据模型
class TcpPortInfo {
  final String exe; // 进程名
  final int pid; // 进程ID
  final String localaddress; // IP地址
  final int port; // 端口
  final String status; // 状态（Listen, Established等）
  final String? exePath; // 可执行文件路径

  TcpPortInfo({
    required this.exe,
    required this.pid,
    required this.localaddress,
    required this.port,
    required this.status,
    this.exePath,
  });
}

/// TCP端口占用列表工具
class TcpPortsTool {
  /// 执行显示TCP端口占用列表操作
  static void execute(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const TcpPortsPage()));
  }

  /// 执行PowerShell命令获取TCP端口占用列表
  static Future<List<TcpPortInfo>> getTcpPorts() async {
    // 创建临时脚本文件
    final tempDir = Directory.systemTemp;
    final scriptFile = File(
      path.join(
        tempDir.path,
        'tcp_ports_${DateTime.now().millisecondsSinceEpoch}.ps1',
      ),
    );

    try {
      // 写入PowerShell脚本
      const powershellScript = r'''
$procMap = @{}
Get-CimInstance Win32_Process | ForEach-Object {
    $procMap[$_.ProcessId] = $_
}

$connections = Get-NetTCPConnection | ForEach-Object {
    $p = $procMap[$_.OwningProcess]
    if ($p) {
        [PSCustomObject]@{
            exe         = $p.Name
            pid         = $_.OwningProcess
            localaddress= $_.LocalAddress
            port        = $_.LocalPort
            status      = $_.State
            exepath     = $p.ExecutablePath
        }
    }
}

$connections | ConvertTo-Json -Compress
''';

      await scriptFile.writeAsString(powershellScript);

      if (kDebugMode) {
        print('[TCP端口工具] 创建临时脚本: ${scriptFile.path}');
      }

      // 执行脚本
      final scriptPath = scriptFile.path.replaceAll('/', '\\');
      final result = await Process.run('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
      ], runInShell: true);

      if (result.exitCode != 0) {
        if (kDebugMode) {
          print('[TCP端口工具] PowerShell执行失败: ${result.stderr}');
          print('[TCP端口工具] PowerShell stdout: ${result.stdout}');
        }
        throw Exception('PowerShell命令执行失败: ${result.stderr}');
      }

      // 解析JSON输出
      final output = result.stdout.toString().trim();
      if (kDebugMode) {
        print('[TCP端口工具] PowerShell输出长度: ${output.length}');
        if (output.isNotEmpty && output.length < 500) {
          print('[TCP端口工具] PowerShell输出内容: $output');
        }
      }

      return _parseJsonOutput(output);
    } finally {
      // 清理临时文件
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
          if (kDebugMode) {
            print('[TCP端口工具] 已删除临时脚本: ${scriptFile.path}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[TCP端口工具] 删除临时脚本失败: $e');
        }
      }
    }
  }

  /// 解析JSON格式的输出
  static List<TcpPortInfo> _parseJsonOutput(String jsonOutput) {
    try {
      // 如果输出为空或无效，返回空列表
      if (jsonOutput.isEmpty) {
        return [];
      }

      // 使用dart:convert解析JSON
      final dynamic jsonData = jsonDecode(jsonOutput);

      final List<TcpPortInfo> ports = [];

      // JSON可能是数组或单个对象
      if (jsonData is List) {
        for (final item in jsonData) {
          if (item is Map) {
            final portInfo = _parseJsonItem(item);
            if (portInfo != null) {
              ports.add(portInfo);
            }
          }
        }
      } else if (jsonData is Map) {
        final portInfo = _parseJsonItem(jsonData);
        if (portInfo != null) {
          ports.add(portInfo);
        }
      }

      // 按端口号排序
      ports.sort((a, b) => a.port.compareTo(b.port));

      return ports;
    } catch (e) {
      if (kDebugMode) {
        print('[TCP端口工具] JSON解析失败: $e');
        print('[TCP端口工具] JSON内容: $jsonOutput');
      }
      // JSON解析失败，尝试使用原来的文本解析方法
      return _parsePowerShellOutput(jsonOutput);
    }
  }

  /// 将TCP连接状态值转换为文本
  static String _convertStateToString(dynamic stateValue) {
    // 如果已经是字符串，直接返回
    if (stateValue is String) {
      return stateValue;
    }

    // 如果是数字，转换为对应的状态文本
    if (stateValue is int) {
      switch (stateValue) {
        case 1:
          return 'Closed';
        case 2:
          return 'Listen';
        case 3:
          return 'SynSent';
        case 4:
          return 'SynReceived';
        case 5:
          return 'Established';
        case 6:
          return 'FinWait1';
        case 7:
          return 'FinWait2';
        case 8:
          return 'CloseWait';
        case 9:
          return 'Closing';
        case 10:
          return 'LastAck';
        case 11:
          return 'TimeWait';
        case 12:
          return 'DeleteTCB';
        case 100:
          return 'Bound';
        default:
          return stateValue.toString();
      }
    }

    // 其他情况，转换为字符串
    return stateValue.toString();
  }

  /// 解析JSON对象中的单个条目
  static TcpPortInfo? _parseJsonItem(Map<dynamic, dynamic> item) {
    try {
      final exe = item['exe']?.toString() ?? '';
      final pid = item['pid'];
      final localaddress = item['localaddress']?.toString() ?? '';
      final port = item['port'];
      final statusValue = item['status'];
      final exePath = item['exepath']?.toString();

      if (exe.isEmpty ||
          pid == null ||
          localaddress.isEmpty ||
          port == null ||
          statusValue == null) {
        return null;
      }

      // 转换状态值为文本
      final status = _convertStateToString(statusValue);

      return TcpPortInfo(
        exe: exe,
        pid: pid is int ? pid : int.tryParse(pid.toString()) ?? 0,
        localaddress: localaddress,
        port: port is int ? port : int.tryParse(port.toString()) ?? 0,
        status: status,
        exePath: exePath?.isEmpty == true ? null : exePath,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[TCP端口工具] 解析条目失败: $e');
      }
      return null;
    }
  }

  /// 解析PowerShell输出（备用方法，当JSON解析失败时使用）
  static List<TcpPortInfo> _parsePowerShellOutput(String output) {
    final List<TcpPortInfo> ports = [];
    final lines = output.split('\n');

    String? exe;
    int? pid;
    String? localaddress;
    int? port;
    String? status;
    String? exePath;

    for (final line in lines) {
      final trimmed = line.trim();

      // 空行表示一个条目结束
      if (trimmed.isEmpty) {
        if (exe != null &&
            pid != null &&
            localaddress != null &&
            port != null &&
            status != null) {
          ports.add(
            TcpPortInfo(
              exe: exe,
              pid: pid,
              localaddress: localaddress,
              port: port,
              status: status,
              exePath: exePath,
            ),
          );
          // 重置变量
          exe = null;
          pid = null;
          localaddress = null;
          port = null;
          status = null;
          exePath = null;
        }
        continue;
      }

      // 解析字段：格式为 "字段名 : 值"
      if (trimmed.contains(':')) {
        final parts = trimmed.split(':');
        if (parts.length >= 2) {
          final fieldName = parts[0].trim().toLowerCase();
          final fieldValue = parts.sublist(1).join(':').trim();

          switch (fieldName) {
            case 'exe':
              exe = fieldValue;
              break;
            case 'pid':
              pid = int.tryParse(fieldValue);
              break;
            case 'localaddress':
              localaddress = fieldValue;
              break;
            case 'port':
              port = int.tryParse(fieldValue);
              break;
            case 'status':
              status = fieldValue;
              break;
            case 'exepath':
              exePath = fieldValue.isEmpty ? null : fieldValue;
              break;
          }
        }
      }
    }

    // 处理最后一个条目（如果输出末尾没有空行）
    if (exe != null &&
        pid != null &&
        localaddress != null &&
        port != null &&
        status != null) {
      ports.add(
        TcpPortInfo(
          exe: exe,
          pid: pid,
          localaddress: localaddress,
          port: port,
          status: status,
          exePath: exePath,
        ),
      );
    }

    // 按端口号排序
    ports.sort((a, b) => a.port.compareTo(b.port));

    return ports;
  }
}
