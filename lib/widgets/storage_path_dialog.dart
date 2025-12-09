import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 存储目录选择对话框
class StoragePathDialog extends StatefulWidget {
  const StoragePathDialog({super.key});

  @override
  State<StoragePathDialog> createState() => _StoragePathDialogState();
}

class _StoragePathDialogState extends State<StoragePathDialog> {
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _initDefaultPath();
  }

  Future<void> _initDefaultPath() async {
    // 默认使用应用文档目录
    final documentsDir = await getApplicationDocumentsDirectory();
    setState(() {
      _selectedPath = '${documentsDir.path}/env4php';
    });
  }

  Future<void> _selectPath() async {
    // 注意：Flutter 桌面端需要使用 file_picker 或 file_selector 包来选择目录
    // 这里先使用一个简单的文本输入方式
    // 实际项目中应该使用 file_selector: ^2.0.0 或 file_picker: ^6.0.0
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PathInputDialog(initialPath: _selectedPath ?? ''),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _selectedPath = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置存储目录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请选择软件安装的存储目录：'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedPath ?? '未选择',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectPath,
                child: const Text('选择'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _selectedPath != null
              ? () => Navigator.of(context).pop(_selectedPath)
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 路径输入对话框（临时方案，实际应使用目录选择器）
class _PathInputDialog extends StatefulWidget {
  final String initialPath;

  const _PathInputDialog({required this.initialPath});

  @override
  State<_PathInputDialog> createState() => _PathInputDialogState();
}

class _PathInputDialogState extends State<_PathInputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPath);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入存储路径'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          hintText: '请输入完整的目录路径',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

