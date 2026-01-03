import 'package:flutter/material.dart';
import '../tools/php_version_tool.dart';
import '../tools/hosts_edit_tool.dart';
import '../tools/mysql_password_reset_tool.dart';
import '../tools/postgresql_password_reset_tool.dart';
import '../tools/tcp_ports_tool.dart';
import 'encode_decode_page.dart';
import 'encrypt_decrypt_page.dart';
import 'generator_page.dart';

/// 工具项数据模型
class _ToolItemData {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  _ToolItemData({required this.icon, required this.title, required this.onTap});
}

/// 快捷工具页面
class QuickToolsPage extends StatefulWidget {
  const QuickToolsPage({super.key});

  @override
  State<QuickToolsPage> createState() => _QuickToolsPageState();
}

class _QuickToolsPageState extends State<QuickToolsPage> {
  int _selectedTabIndex = 0; // 0: 系统, 1: 编解码, 2: 哈希加密, 3: 生成器

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧 Tab 栏（背景透明）
        Container(
          width: 135,
          color: Colors.transparent, // 背景透明
          child: ListView(
            padding: const EdgeInsets.only(
              left: 6,
              right: 2,
              top: 4, // 与右侧页面的padding对齐
              bottom: 8,
            ),
            children: [
              _buildTabItem(context, '系统', 0, Icons.settings),
              const SizedBox(height: 6),
              _buildTabItem(context, '编解码', 1, Icons.code),
              const SizedBox(height: 6),
              _buildTabItem(context, '哈希加密', 2, Icons.lock),
              const SizedBox(height: 6),
              _buildTabItem(context, '生成器', 3, Icons.auto_awesome),
            ],
          ),
        ),
        // 右侧内容区域
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildTabContent(context),
          ),
        ),
      ],
    );
  }

  /// 构建 Tab 项
  Widget _buildTabItem(
    BuildContext context,
    String title,
    int index,
    IconData icon,
  ) {
    final isSelected = _selectedTabIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isSelected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        selected: isSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
      ),
    );
  }

  /// 构建 Tab 内容
  Widget _buildTabContent(BuildContext context) {
    switch (_selectedTabIndex) {
      case 0: // 系统
        return _buildSystemTab(context);
      case 1: // 编解码
        return _buildEncodeDecodeTab(context);
      case 2: // 哈希加密
        return _buildEncryptDecryptTab(context);
      case 3: // 生成器
        return _buildGeneratorTab(context);
      default:
        return _buildSystemTab(context);
    }
  }

  /// 构建系统 Tab 内容
  Widget _buildSystemTab(BuildContext context) {
    final tools = [
      _ToolItemData(
        icon: Icons.code,
        title: '更换PHP版本',
        onTap: () => PhpVersionTool.execute(context),
      ),
      _ToolItemData(
        icon: Icons.edit,
        title: '编辑hosts',
        onTap: () => HostsEditTool.execute(context),
      ),
      _ToolItemData(
        icon: Icons.lock_reset,
        title: '重置MySQL密码',
        onTap: () => MysqlPasswordResetTool.execute(context),
      ),
      _ToolItemData(
        icon: Icons.lock_reset,
        title: '重置PostgreSQL密码',
        onTap: () => PostgresqlPasswordResetTool.execute(context),
      ),
      _ToolItemData(
        icon: Icons.network_check,
        title: 'TCP端口占用',
        onTap: () => TcpPortsTool.execute(context),
      ),
    ];

    // 将工具列表分成两栏
    final leftColumn = <_ToolItemData>[];
    final rightColumn = <_ToolItemData>[];

    for (int i = 0; i < tools.length; i++) {
      if (i % 2 == 0) {
        leftColumn.add(tools[i]);
      } else {
        rightColumn.add(tools[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏
        Expanded(
          child: ListView(
            children: leftColumn
                .map(
                  (tool) => _buildToolItem(
                    context,
                    icon: tool.icon,
                    title: tool.title,
                    onTap: tool.onTap,
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(width: 16),
        // 右栏
        Expanded(
          child: ListView(
            children: rightColumn
                .map(
                  (tool) => _buildToolItem(
                    context,
                    icon: tool.icon,
                    title: tool.title,
                    onTap: tool.onTap,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  /// 构建编解码 Tab 内容
  Widget _buildEncodeDecodeTab(BuildContext context) {
    return const EncodeDecodePage();
  }

  /// 构建哈希加密 Tab 内容
  Widget _buildEncryptDecryptTab(BuildContext context) {
    return const EncryptDecryptPage();
  }

  /// 构建生成器 Tab 内容
  Widget _buildGeneratorTab(BuildContext context) {
    return const GeneratorPage();
  }

  /// 构建工具项（两栏布局：左边图标，右边名称）
  Widget _buildToolItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 左侧图标
              Icon(
                icon,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              // 右侧名称
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
