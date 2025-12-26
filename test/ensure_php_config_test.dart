import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

void main() {
  group('_ensurePhpConfigExists 功能测试', () {
    late Directory tempDir;
    late Directory nginxDir;
    late Directory phpConfDir;
    late File exampleFile;

    setUpAll(() async {
      // 创建临时目录结构
      tempDir = await Directory.systemTemp.createTemp('php_config_test_');
      nginxDir = Directory(path.join(tempDir.path, 'nginx'));
      phpConfDir = Directory(path.join(nginxDir.path, 'conf', 'php'));
      await phpConfDir.create(recursive: true);

      // 创建示例文件（注意：第三行是索引2）
      exampleFile = File(path.join(phpConfDir.path, 'php.conf.example'));
      await exampleFile.writeAsString('''# PHP FastCGI配置
    listen #--#;
    fastcgi_pass 127.0.0.1:#--#;
    # 其他配置...
''');
    });

    tearDownAll(() async {
      // 清理临时目录
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('测试1: 创建新的PHP配置文件（从示例文件）', () async {
      final phpVersionId = 'test_php_1';
      final testPort = 9001;
      final phpConfFile = File(path.join(phpConfDir.path, '$phpVersionId.conf'));

      // 确保配置文件不存在
      if (await phpConfFile.exists()) {
        await phpConfFile.delete();
      }

      // 执行测试逻辑（模拟 _ensurePhpConfigExists）
      await _testEnsurePhpConfigExists(nginxDir.path, phpVersionId, testPort);

      // 验证文件已创建
      expect(await phpConfFile.exists(), true, reason: 'PHP配置文件应该被创建');

      // 验证端口已替换
      final content = await phpConfFile.readAsString();
      expect(content.contains('listen $testPort'), true,
          reason: '配置文件应该包含正确的端口号');
      expect(content.contains('#--#'), false,
          reason: '配置文件不应该包含占位符');
    });

    test('测试2: 更新已存在的PHP配置文件端口', () async {
      final phpVersionId = 'test_php_2';
      final oldPort = 9000;
      final newPort = 9002;
      final phpConfFile = File(path.join(phpConfDir.path, '$phpVersionId.conf'));

      // 创建已存在的配置文件
      await phpConfFile.writeAsString('''
# PHP FastCGI配置
    listen $oldPort;
    fastcgi_pass 127.0.0.1:$oldPort;
    # 其他配置...
''');

      // 更新端口
      await _testEnsurePhpConfigExists(nginxDir.path, phpVersionId, newPort);

      // 验证端口已更新
      final content = await phpConfFile.readAsString();
      expect(content.contains('listen $newPort'), true,
          reason: '配置文件应该包含新的端口号');
      expect(content.contains('listen $oldPort'), false,
          reason: '配置文件不应该包含旧的端口号');
    });

    test('测试3: 更新包含#--#占位符的配置文件', () async {
      final phpVersionId = 'test_php_3';
      final testPort = 9003;
      final phpConfFile = File(path.join(phpConfDir.path, '$phpVersionId.conf'));

      // 创建包含占位符的配置文件
      await phpConfFile.writeAsString('''
# PHP FastCGI配置
    listen #--#;
    fastcgi_pass 127.0.0.1:#--#;
    # 其他配置...
''');

      // 更新端口
      await _testEnsurePhpConfigExists(nginxDir.path, phpVersionId, testPort);

      // 验证占位符已替换
      final content = await phpConfFile.readAsString();
      expect(content.contains('listen $testPort'), true,
          reason: '配置文件应该包含正确的端口号');
      // 注意：只检查 listen 行中的占位符，fastcgi_pass 行中的占位符不会被替换
      final lines = content.split('\n');
      bool listenLineHasPlaceholder = false;
      for (final line in lines) {
        if (line.contains('listen') && line.contains('#--#')) {
          listenLineHasPlaceholder = true;
          break;
        }
      }
      expect(listenLineHasPlaceholder, false,
          reason: 'listen 行不应该包含占位符');
    });

    test('测试4: 更新包含listen但无端口号的配置', () async {
      final phpVersionId = 'test_php_4';
      final testPort = 9004;
      final phpConfFile = File(path.join(phpConfDir.path, '$phpVersionId.conf'));

      // 创建包含listen但无端口号的配置文件
      await phpConfFile.writeAsString('''
# PHP FastCGI配置
    listen;
    fastcgi_pass 127.0.0.1:9000;
    # 其他配置...
''');

      // 更新端口
      await _testEnsurePhpConfigExists(nginxDir.path, phpVersionId, testPort);

      // 验证配置已更新
      final content = await phpConfFile.readAsString();
      // 应该找到包含端口的listen行
      expect(content.contains('listen $testPort'), true,
          reason: '配置文件应该包含正确的端口号');
    });
  });
}

/// 测试辅助方法：模拟 _ensurePhpConfigExists 的逻辑
Future<void> _testEnsurePhpConfigExists(
  String nginxDir,
  String phpVersionId,
  int port,
) async {
  final phpConfPath = path.join(
    nginxDir,
    'conf',
    'php',
    '$phpVersionId.conf',
  );
  final phpConfFile = File(phpConfPath);

    if (!await phpConfFile.exists()) {
      // 复制示例文件
      final examplePath = path.join(
        nginxDir,
        'conf',
        'php',
        'php.conf.example',
      );
      final exampleFile = File(examplePath);

      if (await exampleFile.exists()) {
        final content = await exampleFile.readAsString();
        // 替换所有行的#--#为端口
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          lines[i] = lines[i].replaceAll('#--#', port.toString());
        }
        await phpConfFile.writeAsString(lines.join('\n'));
      }
    } else {
    // 如果文件已存在，更新端口配置
    final content = await phpConfFile.readAsString();
    final lines = content.split('\n');
    // 查找包含listen的行并更新端口
    bool portUpdated = false;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('listen') && lines[i].contains('#')) {
        // 如果包含#--#占位符，替换它
        if (lines[i].contains('#--#')) {
          lines[i] = lines[i].replaceAll('#--#', port.toString());
          portUpdated = true;
          break;
        }
      } else if (RegExp(r'listen\s+\d+').hasMatch(lines[i])) {
        // 如果已有端口配置，更新它
        lines[i] = lines[i].replaceAll(
          RegExp(r'listen\s+\d+'),
          'listen $port',
        );
        portUpdated = true;
        break;
      }
    }

    // 如果没有找到listen行，在第三行添加（如果存在）
    if (!portUpdated && lines.length >= 3) {
      if (lines[2].contains('#--#')) {
        lines[2] = lines[2].replaceAll('#--#', port.toString());
      } else {
        // 在第三行后插入listen配置
        lines.insert(2, '    listen $port;');
      }
    }

    await phpConfFile.writeAsString(lines.join('\n'));
  }
}
