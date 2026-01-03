import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

/// 哈希算法类型
enum HashAlgorithm { md5, sha1, sha256, sha512 }

/// 哈希加密工具页面
class EncryptDecryptPage extends StatefulWidget {
  const EncryptDecryptPage({super.key});

  @override
  State<EncryptDecryptPage> createState() => _EncryptDecryptPageState();
}

class _EncryptDecryptPageState extends State<EncryptDecryptPage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  HashAlgorithm _selectedAlgorithm = HashAlgorithm.md5;

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  /// 计算哈希
  void _calculateHash() {
    final input = _inputController.text;

    if (input.isEmpty) {
      _outputController.clear();
      return;
    }

    try {
      String hash;
      switch (_selectedAlgorithm) {
        case HashAlgorithm.md5:
          hash = _hashMD5(input);
          break;
        case HashAlgorithm.sha1:
          hash = _hashSHA1(input);
          break;
        case HashAlgorithm.sha256:
          hash = _hashSHA256(input);
          break;
        case HashAlgorithm.sha512:
          hash = _hashSHA512(input);
          break;
      }
      setState(() {
        _outputController.text = hash;
      });
    } catch (e) {
      setState(() {
        _outputController.text = '计算失败: $e';
      });
    }
  }

  /// MD5 哈希
  String _hashMD5(String input) {
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// SHA1 哈希
  String _hashSHA1(String input) {
    final bytes = utf8.encode(input);
    final digest = sha1.convert(bytes);
    return digest.toString();
  }

  /// SHA256 哈希
  String _hashSHA256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// SHA512 哈希
  String _hashSHA512(String input) {
    final bytes = utf8.encode(input);
    final digest = sha512.convert(bytes);
    return digest.toString();
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
                        hintText: '请输入要计算哈希的内容...',
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

        // 中间：操作区（算法选择和计算按钮）
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            children: [
              // 算法选择
              Row(
                children: [
                  const Text(
                    '算法：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<HashAlgorithm>(
                      segments: const [
                        ButtonSegment<HashAlgorithm>(
                          value: HashAlgorithm.md5,
                          label: Text('MD5'),
                        ),
                        ButtonSegment<HashAlgorithm>(
                          value: HashAlgorithm.sha1,
                          label: Text('SHA1'),
                        ),
                        ButtonSegment<HashAlgorithm>(
                          value: HashAlgorithm.sha256,
                          label: Text('SHA256'),
                        ),
                        ButtonSegment<HashAlgorithm>(
                          value: HashAlgorithm.sha512,
                          label: Text('SHA512'),
                        ),
                      ],
                      selected: {_selectedAlgorithm},
                      onSelectionChanged: (Set<HashAlgorithm> newSelection) {
                        setState(() {
                          _selectedAlgorithm = newSelection.first;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 计算按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: _calculateHash,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('计算'),
                  ),
                ],
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
                        hintText: '哈希计算结果将显示在这里...',
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
