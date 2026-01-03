import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 编解码算法类型
enum EncodeDecodeAlgorithm { base64, url }

/// 编解码工具页面
class EncodeDecodePage extends StatefulWidget {
  const EncodeDecodePage({super.key});

  @override
  State<EncodeDecodePage> createState() => _EncodeDecodePageState();
}

class _EncodeDecodePageState extends State<EncodeDecodePage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  EncodeDecodeAlgorithm _selectedAlgorithm = EncodeDecodeAlgorithm.base64;

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  /// 编码
  void _encode() {
    final input = _inputController.text;
    if (input.isEmpty) {
      _outputController.clear();
      return;
    }

    try {
      String encoded;
      switch (_selectedAlgorithm) {
        case EncodeDecodeAlgorithm.base64:
          encoded = base64Encode(utf8.encode(input));
          break;
        case EncodeDecodeAlgorithm.url:
          encoded = Uri.encodeComponent(input);
          break;
      }
      setState(() {
        _outputController.text = encoded;
      });
    } catch (e) {
      setState(() {
        _outputController.text = '编码失败: $e';
      });
    }
  }

  /// 解码
  void _decode() {
    final input = _inputController.text;
    if (input.isEmpty) {
      _outputController.clear();
      return;
    }

    try {
      String decoded;
      switch (_selectedAlgorithm) {
        case EncodeDecodeAlgorithm.base64:
          decoded = utf8.decode(base64Decode(input));
          break;
        case EncodeDecodeAlgorithm.url:
          decoded = Uri.decodeComponent(input);
          break;
      }
      setState(() {
        _outputController.text = decoded;
      });
    } catch (e) {
      setState(() {
        _outputController.text = '解码失败: $e';
      });
    }
  }

  /// 清空输入
  void _clearInput() {
    setState(() {
      _inputController.clear();
      _outputController.clear();
    });
  }

  /// 清空输出
  void _clearOutput() {
    setState(() {
      _outputController.clear();
    });
  }

  /// 复制输出
  Future<void> _copyOutput() async {
    final output = _outputController.text;
    if (output.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: output));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 上部：输入框
        Expanded(
          flex: 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 输入框标题栏
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '输入',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _clearInput,
                        tooltip: '清空',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                ),
                // 输入框
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _inputController,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '请输入要编码或解码的内容...',
                        contentPadding: EdgeInsets.all(8),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 中间：操作区（算法选择和编码/解码按钮）
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              // 算法选择
              const Text('算法：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              SegmentedButton<EncodeDecodeAlgorithm>(
                segments: const [
                  ButtonSegment<EncodeDecodeAlgorithm>(
                    value: EncodeDecodeAlgorithm.base64,
                    label: Text('Base64'),
                  ),
                  ButtonSegment<EncodeDecodeAlgorithm>(
                    value: EncodeDecodeAlgorithm.url,
                    label: Text('URL编码'),
                  ),
                ],
                selected: {_selectedAlgorithm},
                onSelectionChanged: (Set<EncodeDecodeAlgorithm> newSelection) {
                  setState(() {
                    _selectedAlgorithm = newSelection.first;
                  });
                },
              ),
              const Spacer(),
              // 编码按钮
              ElevatedButton.icon(
                onPressed: _encode,
                label: const Text('编码'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 解码按钮
              ElevatedButton.icon(
                onPressed: _decode,
                label: const Text('解码'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 下部：输出框
        Expanded(
          flex: 1,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 输出框标题栏
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '输出',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: _copyOutput,
                        tooltip: '复制',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _clearOutput,
                        tooltip: '清空',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                ),
                // 输出框
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _outputController,
                      maxLines: null,
                      expands: true,
                      readOnly: true,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '编码或解码结果将显示在这里...',
                        contentPadding: EdgeInsets.all(8),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
