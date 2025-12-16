import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/software_model.dart';

/// 软件源服务
class SoftwareSourceService {
  static const String _localFileName = 'soft.json';
  static const String _defaultSourceURL = 'https://conf.e4p.uxyz.fyi/soft.json';
  static String? _sourceURL;

  /// 获取本地软件源文件路径
  static Future<String> getLocalSourcePath() async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/$_localFileName';
  }

  /// 下载软件源（带超时）
  static Future<bool> downloadSource({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final url = getSourceURL();
    if (url.isEmpty) {
      return false;
    }

    HttpClient? httpClient;
    try {
      // 创建 HttpClient，自动使用系统代理
      httpClient = HttpClient();
      // 不设置 findProxy，让 HttpClient 自动使用系统代理设置

      final uri = Uri.parse(url);
      final request = await httpClient.getUrl(uri).timeout(timeout);

      // 设置请求头
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'env4php/1.0');

      // 发送请求并获取响应
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 200) {
        // 读取响应体
        final bytes = await response.expand((chunk) => chunk).toList();
        final contentBytes = Uint8List.fromList(bytes);

        // 尝试检测字符编码
        String content;
        final contentType = response.headers.value('content-type') ?? '';
        if (contentType.contains('charset=')) {
          final charset = contentType.split('charset=')[1].split(';')[0].trim();
          if (kDebugMode) {
            print('检测到字符编码: $charset');
          }
          try {
            content = utf8.decode(contentBytes);
          } catch (e) {
            // 如果 UTF-8 解码失败，尝试其他编码
            if (kDebugMode) {
              print('UTF-8 解码失败，尝试使用原始字节: $e');
            }
            content = String.fromCharCodes(contentBytes);
          }
        } else {
          // 默认使用 UTF-8
          try {
            content = utf8.decode(contentBytes);
          } catch (e) {
            if (kDebugMode) {
              print('UTF-8 解码失败，使用原始字节: $e');
            }
            content = String.fromCharCodes(contentBytes);
          }
        }

        final localPath = await getLocalSourcePath();
        final file = File(localPath);
        // 使用 UTF-8 编码保存文件
        await file.writeAsString(content, encoding: utf8);

        httpClient.close();
        return true;
      }

      httpClient.close();
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('下载软件源失败: $e');
      }
      // 确保在异常情况下也关闭客户端
      if (httpClient != null) {
        try {
          httpClient.close();
        } catch (_) {
          // 忽略关闭错误
        }
      }
      return false;
    }
  }

  /// 检查是否有缓存的软件源
  static Future<bool> hasCachedSource() async {
    final localPath = await getLocalSourcePath();
    final file = File(localPath);
    return await file.exists();
  }

  /// 从本地缓存文件加载软件源
  static Future<SoftwareSource?> loadLocalSource({
    bool isFromCache = false,
  }) async {
    try {
      final localPath = await getLocalSourcePath();
      final file = File(localPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return SoftwareSource.fromJson(json);
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('加载软件源失败: $e');
      }
      return null;
    }
  }

  /// 检查软件源是否有更新
  /// 返回 true 表示有更新，false 表示无更新或检查失败
  static Future<bool> checkForUpdate() async {
    try {
      final url = getSourceURL();
      if (url.isEmpty) {
        return false;
      }

      // 检查是否有本地缓存
      final hasCache = await hasCachedSource();
      if (!hasCache) {
        // 没有缓存，直接下载
        return await downloadSource();
      }

      // 读取本地缓存内容
      final localPath = await getLocalSourcePath();
      final localFile = File(localPath);
      final localContent = await localFile.readAsString();

      // 尝试下载最新版本（使用较短的超时时间）
      HttpClient? httpClient;
      try {
        httpClient = HttpClient();
        final uri = Uri.parse(url);
        final request = await httpClient.getUrl(uri).timeout(
          const Duration(seconds: 5),
        );

        request.headers.set('Accept', 'application/json');
        request.headers.set('User-Agent', 'env4php/1.0');

        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );

        if (response.statusCode == 200) {
          final bytes = await response.expand((chunk) => chunk).toList();
          final contentBytes = Uint8List.fromList(bytes);
          String remoteContent;
          try {
            remoteContent = utf8.decode(contentBytes);
          } catch (e) {
            remoteContent = String.fromCharCodes(contentBytes);
          }

          httpClient.close();

          // 比较内容是否相同
          if (remoteContent != localContent) {
            // 有更新，保存新版本
            await localFile.writeAsString(remoteContent, encoding: utf8);
            return true;
          }

          return false;
        }

        httpClient.close();
        return false;
      } catch (e) {
        if (kDebugMode) {
          print('检查软件源更新失败: $e');
        }
        if (httpClient != null) {
          try {
            httpClient.close();
          } catch (_) {
            // 忽略关闭错误
          }
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('检查软件源更新失败: $e');
      }
      return false;
    }
  }

  /// 获取软件源（只有首次打开或没有缓存时才下载，其余情况从本地加载）
  static Future<SoftwareSource?> getSource() async {
    // 检查是否有本地缓存
    final hasCache = await hasCachedSource();
    if (!hasCache) {
      final downloadSuccess = await downloadSource();

      if (downloadSuccess) {
        return await loadLocalSource(isFromCache: false);
      } else {
        // 下载失败，返回null
        if (kDebugMode) {
          print('下载失败，没有可用缓存');
        }
        return null;
      }
    } else {
      return await loadLocalSource(isFromCache: true);
    }
  }

  /// 获取软件源 URL
  static String getSourceURL() {
    return _sourceURL ?? _defaultSourceURL;
  }

  /// 设置软件源 URL
  static void setSourceURL(String? url) {
    _sourceURL = url;
  }

  /// 初始化（设置默认 URL）
  static void initialize() {
    _sourceURL ??= _defaultSourceURL;
  }
}
