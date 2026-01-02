import 'package:flutter/material.dart';

/// TCP端口占用列表工具
class TcpPortsTool {
  /// 执行显示TCP端口占用列表操作
  static void execute(BuildContext context) {
    // TODO: 实现TCP端口占用列表的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('TCP端口占用列表（功能待实现）'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

