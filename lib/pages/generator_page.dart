import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// 生成器工具页面
class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key});

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<GeneratorPage> {
  final TextEditingController _outputController = TextEditingController();
  
  // 随机密码生成参数
  bool _includeNumbers = true;
  bool _includeLetters = true;
  bool _includeSpecialChars = false;
  int _passwordLength = 16;
  int _passwordCount = 1;
  
  // 当前生成类型
  String _currentGeneratorType = 'password'; // 'password' 或 'uuid'

  @override
  void dispose() {
    _outputController.dispose();
    super.dispose();
  }

  /// 生成随机密码
  void _generatePassword() {
    try {
      final random = Random.secure();
      const numbers = '0123456789';
      const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
      const specialChars = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
      
      String charset = '';
      if (_includeNumbers) charset += numbers;
      if (_includeLetters) charset += letters;
      if (_includeSpecialChars) charset += specialChars;
      
      if (charset.isEmpty) {
        setState(() {
          _outputController.text = '错误: 至少需要选择一种字符类型';
        });
        return;
      }
      
      final passwords = <String>[];
      for (int i = 0; i < _passwordCount; i++) {
        final password = String.fromCharCodes(
          Iterable.generate(
            _passwordLength,
            (_) => charset.codeUnitAt(random.nextInt(charset.length)),
          ),
        );
        passwords.add(password);
      }
      
      setState(() {
        _outputController.text = passwords.join('\n');
      });
    } catch (e) {
      setState(() {
        _outputController.text = '生成失败: $e';
      });
    }
  }

  /// 生成UUID
  void _generateUUID() {
    try {
      const uuid = Uuid();
      final generatedUuid = uuid.v4();
      setState(() {
        _outputController.text = generatedUuid;
      });
    } catch (e) {
      setState(() {
        _outputController.text = '生成失败: $e';
      });
    }
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
        // 中间：操作区（生成类型选择、参数设置和生成按钮）
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            children: [
              // 生成类型选择
              Row(
                children: [
                  const Text(
                    '类型：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'password',
                          label: Text('随机密码'),
                        ),
                        ButtonSegment<String>(
                          value: 'uuid',
                          label: Text('UUID'),
                        ),
                      ],
                      selected: {_currentGeneratorType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _currentGeneratorType = newSelection.first;
                          _outputController.clear();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 根据类型显示不同的配置选项
              if (_currentGeneratorType == 'password') ...[
                // 随机密码配置
                Row(
                  children: [
                    const Text(
                      '字符类型：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Checkbox(
                      value: _includeNumbers,
                      onChanged: (value) {
                        setState(() {
                          _includeNumbers = value ?? true;
                        });
                      },
                    ),
                    const Text('数字'),
                    const SizedBox(width: 16),
                    Checkbox(
                      value: _includeLetters,
                      onChanged: (value) {
                        setState(() {
                          _includeLetters = value ?? true;
                        });
                      },
                    ),
                    const Text('字母'),
                    const SizedBox(width: 16),
                    Checkbox(
                      value: _includeSpecialChars,
                      onChanged: (value) {
                        setState(() {
                          _includeSpecialChars = value ?? false;
                        });
                      },
                    ),
                    const Text('特殊符号'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      '长度：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        controller: TextEditingController(
                          text: _passwordLength.toString(),
                        )..selection = TextSelection.fromPosition(
                          TextPosition(offset: _passwordLength.toString().length),
                        ),
                        onChanged: (value) {
                          final length = int.tryParse(value);
                          if (length != null && length > 0) {
                            setState(() {
                              _passwordLength = length;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      '个数：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        controller: TextEditingController(
                          text: _passwordCount.toString(),
                        )..selection = TextSelection.fromPosition(
                          TextPosition(offset: _passwordCount.toString().length),
                        ),
                        onChanged: (value) {
                          final count = int.tryParse(value);
                          if (count != null && count > 0) {
                            setState(() {
                              _passwordCount = count;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // 生成按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: _currentGeneratorType == 'password'
                        ? _generatePassword
                        : _generateUUID,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('生成'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 下部：输出框
        Expanded(
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
                        hintText: '生成结果将显示在这里...',
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

