import 'package:flutter/material.dart';
import '../pages/hosts_edit_page.dart';

/// 编辑hosts文件工具
class HostsEditTool {
  /// 执行编辑hosts文件操作
  static void execute(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const HostsEditPage()));
  }
}

