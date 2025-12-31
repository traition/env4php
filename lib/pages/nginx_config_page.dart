import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/notification_service.dart';

/// Nginx配置页面
class NginxConfigPage extends StatefulWidget {
  final String projectName;
  final String configType; // 'daemon', 'normal', 'static'
  final String? framework; // 仅用于daemon类型
  final String? Function(String serverName, String port, bool enableSsl, String sslPort)? validateServerNameAndPort;

  const NginxConfigPage({
    super.key,
    required this.projectName,
    required this.configType,
    this.framework,
    this.validateServerNameAndPort,
  });

  @override
  State<NginxConfigPage> createState() => _NginxConfigPageState();
}

class _NginxConfigPageState extends State<NginxConfigPage> {
  late TextEditingController _serverNameController;
  late TextEditingController _portController;
  late TextEditingController _sslPortController;
  late TextEditingController _rootController;
  late TextEditingController _upstreamPortsController;
  late TextEditingController _customRulesController;
  late TextEditingController _rewriteRuleController;
  late TextEditingController _certPathController;
  late TextEditingController _keyPathController;

  bool _enableSsl = false;
  bool _useSelfSignedCert = false;
  String? _selectedRewriteRule;

  // 伪静态规则选项（仅用于normal类型）
  static const List<String> rewriteRules = [
    'codeigniter',
    'laravel',
    'symfony',
    'thinkphp',
    'yii',
  ];

  @override
  void initState() {
    super.initState();
    // 生成默认server_name
    final defaultServerName = _generateDefaultServerName(widget.projectName);
    _serverNameController = TextEditingController(text: defaultServerName);
    _portController = TextEditingController(text: '80');
    _sslPortController = TextEditingController(text: '443');
    _rootController = TextEditingController();
    
    // 根据类型设置默认值
    if (widget.configType == 'daemon' && widget.framework != null) {
      final defaultUpstream = widget.framework == 'easyswoole'
          ? '9501'
          : widget.framework == 'webman'
          ? '8787'
          : widget.framework == 'hyperf'
          ? '9501,9502'
          : '';
      _upstreamPortsController = TextEditingController(text: defaultUpstream);
    } else {
      _upstreamPortsController = TextEditingController();
    }
    
    _customRulesController = TextEditingController();
    _rewriteRuleController = TextEditingController();
    _certPathController = TextEditingController();
    _keyPathController = TextEditingController();
  }

  @override
  void dispose() {
    _serverNameController.dispose();
    _portController.dispose();
    _sslPortController.dispose();
    _rootController.dispose();
    _upstreamPortsController.dispose();
    _customRulesController.dispose();
    _rewriteRuleController.dispose();
    _certPathController.dispose();
    _keyPathController.dispose();
    super.dispose();
  }

  /// 生成默认的server_name（基于项目名称，去除_, (), []）
  String _generateDefaultServerName(String projectName) {
    String serverName = projectName
        .replaceAll('_', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('[', '')
        .replaceAll(']', '');
    return '$serverName.localhost';
  }

  /// 验证配置
  Future<String?> _validateConfig() async {
    final serverName = _serverNameController.text.trim();
    final port = _portController.text.trim();
    final sslPort = _sslPortController.text.trim();
    final root = _rootController.text.trim();

    // 检查server_name是否为空或'.localhost'
    if (serverName.isEmpty || serverName == '.localhost') {
      return 'server_name不能为空';
    }

    // 检查port是否为空
    if (port.isEmpty) {
      return '端口不能为空';
    }

    // 如果启用了SSL，检查SSL端口是否为空
    if (_enableSsl && sslPort.isEmpty) {
      return 'SSL端口不能为空';
    }

    // 检查root路径
    if (root.isEmpty) {
      return 'root路径不能为空';
    }

    // 如果是daemon类型，检查upstream端口
    if (widget.configType == 'daemon') {
      final upstreamPorts = _upstreamPortsController.text.trim();
      if (upstreamPorts.isEmpty) {
        return 'upstream端口不能为空';
      }
    }

    // 使用外部验证函数验证server_name和port
    if (widget.validateServerNameAndPort != null) {
      final validationError = widget.validateServerNameAndPort!(
        serverName,
        port,
        _enableSsl,
        sslPort,
      );
      if (validationError != null) {
        return validationError;
      }
    }

    return null;
  }

  /// 保存配置
  Future<void> _saveConfig() async {
    final validationError = await _validateConfig();
    if (validationError != null) {
      await NotificationService.showError(
        title: '验证失败',
        message: validationError,
      );
      return;
    }

    final config = <String, dynamic>{
      'serverName': _serverNameController.text.trim(),
      'port': _portController.text.trim(),
      'enableSsl': _enableSsl,
      'sslPort': _sslPortController.text.trim(),
      'useSelfSignedCert': _useSelfSignedCert,
      'certPath': _certPathController.text.trim().isNotEmpty
          ? _certPathController.text.trim()
          : null,
      'keyPath': _keyPathController.text.trim().isNotEmpty
          ? _keyPathController.text.trim()
          : null,
      'root': _rootController.text.trim(),
    };

    if (widget.configType == 'daemon') {
      config['upstreamPorts'] = _upstreamPortsController.text.trim();
      config['customRules'] = _customRulesController.text.trim();
    } else if (widget.configType == 'normal') {
      config['rewriteRule'] = _selectedRewriteRule;
    } else if (widget.configType == 'static') {
      config['customRules'] = _customRulesController.text.trim();
    }

    if (mounted) {
      Navigator.of(context).pop(config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AppBar(
                title: const Text('配置nginx'),
                centerTitle: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveConfig,
                    child: const Text('确定'),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // server_name
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: TextField(
                controller: _serverNameController,
                decoration: const InputDecoration(
                  labelText: 'server_name',
                  hintText: '例如: example.localhost',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 端口
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '默认: 80',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            // SSL开关
            SwitchListTile(
              title: const Text('启用SSL'),
              value: _enableSsl,
              onChanged: (value) => setState(() => _enableSsl = value),
            ),
            if (_enableSsl) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _sslPortController,
                decoration: const InputDecoration(
                  labelText: 'SSL端口',
                  hintText: '默认: 443',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('使用自签证书'),
                value: _useSelfSignedCert,
                onChanged: (value) => setState(() => _useSelfSignedCert = value),
              ),
              if (!_useSelfSignedCert) ...[
                const SizedBox(height: 16),
                // 证书内容文本域（带导入按钮）
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _certPathController,
                        decoration: const InputDecoration(
                          labelText: '证书内容',
                          hintText: '请输入证书内容（PEM格式）或点击导入按钮从文件导入',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        minLines: 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: IconButton(
                        icon: const Icon(Icons.file_upload),
                        tooltip: '导入证书文件',
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['pem', 'crt', 'cer'],
                          );
                          if (result != null && result.files.single.path != null) {
                            try {
                              final file = File(result.files.single.path!);
                              final content = await file.readAsString();
                              setState(() {
                                _certPathController.text = content;
                              });
                            } catch (e) {
                              await NotificationService.showError(
                                title: '导入失败',
                                message: '无法读取证书文件: $e',
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 密钥内容文本域（带导入按钮）
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keyPathController,
                        decoration: const InputDecoration(
                          labelText: '密钥内容',
                          hintText: '请输入密钥内容（PEM格式）或点击导入按钮从文件导入',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        minLines: 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: IconButton(
                        icon: const Icon(Icons.file_upload),
                        tooltip: '导入密钥文件',
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['key', 'pem'],
                          );
                          if (result != null && result.files.single.path != null) {
                            try {
                              final file = File(result.files.single.path!);
                              final content = await file.readAsString();
                              setState(() {
                                _keyPathController.text = content;
                              });
                            } catch (e) {
                              await NotificationService.showError(
                                title: '导入失败',
                                message: '无法读取密钥文件: $e',
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 16),
            // root路径
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rootController,
                    decoration: const InputDecoration(
                      labelText: 'root路径',
                      hintText: '项目根目录路径',
                      border: OutlineInputBorder(),
                    ),
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.getDirectoryPath();
                    if (result != null) {
                      setState(() {
                        _rootController.text = result;
                      });
                    }
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择'),
                ),
              ],
            ),
            // 根据类型显示不同的字段
            if (widget.configType == 'daemon') ...[
              const SizedBox(height: 16),
              // upstream端口
              TextField(
                controller: _upstreamPortsController,
                decoration: const InputDecoration(
                  labelText: 'upstream端口',
                  hintText: '用半角逗号分隔，例如: 9501,9502',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // 自定义规则
              TextField(
                controller: _customRulesController,
                decoration: const InputDecoration(
                  labelText: '自定义server{}块规则',
                  hintText: '可选，留空则不添加',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
            ] else if (widget.configType == 'normal') ...[
              const SizedBox(height: 16),
              // 伪静态规则
              DropdownButtonFormField<String>(
                value: _selectedRewriteRule,
                decoration: const InputDecoration(
                  labelText: '伪静态规则',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('无')),
                  ...rewriteRules.map(
                    (rule) => DropdownMenuItem(value: rule, child: Text(rule)),
                  ),
                ],
                onChanged: (value) => setState(() => _selectedRewriteRule = value),
              ),
            ] else if (widget.configType == 'static') ...[
              const SizedBox(height: 16),
              // 自定义规则
              TextField(
                controller: _customRulesController,
                decoration: const InputDecoration(
                  labelText: '自定义server{}块规则',
                  hintText: '可选，留空则不添加',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

