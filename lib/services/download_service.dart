import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as path;

/// 下载服务
class DownloadService {
  /// 下载文件
  /// [url] 下载地址
  /// [savePath] 保存路径（包含文件名）
  /// [onProgress] 进度回调 (已下载字节数, 总字节数)
  /// [cancellationToken] 取消令牌，用于取消下载
  /// 返回 (是否成功, 错误信息)
  static Future<(bool success, String? error)> downloadFile(
    String url,
    String savePath, {
    Function(int downloaded, int total)? onProgress,
    bool Function()? cancellationToken,
  }) async {
    http.Client? client;
    try {
      // 使用系统代理：使用 IOClient 和 HttpClient，不设置 findProxy 让它自动检测系统代理
      final httpClient = HttpClient();
      // 不设置 findProxy，让 HttpClient 自动使用系统代理设置
      client = IOClient(httpClient);
      
      // 在开始下载前检查是否已取消
      if (cancellationToken != null && cancellationToken()) {
        client.close();
        return (false, '下载已取消');
      }

      final request = http.Request('GET', Uri.parse(url));
      http.StreamedResponse response;
      try {
        response = await client.send(request);
      } catch (e) {
        client.close();
        return (false, '网络错误: $e');
      }

      // 在检查响应状态前也检查取消
      if (cancellationToken != null && cancellationToken()) {
        // 关闭响应流
        try {
          response.stream.listen(null).cancel();
        } catch (_) {
          // 忽略取消错误
        }
        client.close();
        return (false, '下载已取消');
      }

      if (response.statusCode != 200) {
        final errorMsg = 'HTTP ${response.statusCode}: ${response.reasonPhrase ?? '未知错误'}';
        // 关闭响应流
        try {
          response.stream.listen(null).cancel();
        } catch (_) {
          // 忽略取消错误
        }
        client.close();
        return (false, errorMsg);
      }

      final contentLength = response.contentLength ?? 0;
      final file = File(savePath);
      IOSink? sink;
      
      try {
        sink = file.openWrite();
        int downloaded = 0;
        
        try {
          await for (final chunk in response.stream) {
            // 检查是否取消
            if (cancellationToken != null && cancellationToken()) {
              // 先关闭文件流
              if (sink != null) {
                await sink.flush();
                await sink.close();
                sink = null;
              }
              // 关闭响应流
              try {
                response.stream.listen(null).cancel();
              } catch (_) {
                // 忽略取消错误
              }
              // 关闭客户端
              client.close();
              // 等待一小段时间确保文件释放
              await Future.delayed(const Duration(milliseconds: 100));
              // 删除部分下载的文件
              await _deleteFileWithRetry(savePath);
              return (false, '下载已取消');
            }
            
            if (sink != null) {
              sink.add(chunk);
              downloaded += chunk.length;
              onProgress?.call(downloaded, contentLength);
            }
          }
          
          // 下载完成，关闭文件流
          if (sink != null) {
            await sink.flush();
            await sink.close();
            sink = null;
          }
          client.close();
          return (true, null);
        } catch (streamError) {
          // 流处理错误
          if (sink != null) {
            try {
              await sink.flush();
              await sink.close();
              sink = null;
            } catch (_) {
              // 忽略关闭错误
            }
          }
          try {
            response.stream.listen(null).cancel();
          } catch (_) {
            // 忽略取消错误
          }
          client.close();
          await Future.delayed(const Duration(milliseconds: 100));
          await _deleteFileWithRetry(savePath);
          return (false, '下载流错误: $streamError');
        }
      } catch (e) {
        // 文件操作错误
        if (sink != null) {
          try {
            await sink.flush();
            await sink.close();
            sink = null;
          } catch (_) {
            // 忽略关闭错误
          }
        }
        try {
          response.stream.listen(null).cancel();
        } catch (_) {
          // 忽略取消错误
        }
        client.close();
        await Future.delayed(const Duration(milliseconds: 100));
        await _deleteFileWithRetry(savePath);
        return (false, '文件操作错误: $e');
      }
    } catch (e) {
      // 确保在异常情况下也关闭客户端
      if (client != null) {
        try {
          client.close();
        } catch (_) {
          // 忽略关闭错误
        }
      }
      // 等待一小段时间确保资源释放
      await Future.delayed(const Duration(milliseconds: 100));
      // 删除部分下载的文件
      await _deleteFileWithRetry(savePath);
      return (false, '下载失败: $e');
    }
  }

  /// 删除文件（带重试机制）
  static Future<void> _deleteFileWithRetry(String filePath, {int maxRetries = 5}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          return; // 删除成功
        }
        return; // 文件不存在，无需删除
      } catch (e) {
        if (i < maxRetries - 1) {
          // 等待后重试
          await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
        } else {
          // 最后一次尝试失败，忽略错误
        }
      }
    }
  }

  /// 获取文件扩展名
  static String getFileExtension(String url) {
    final uri = Uri.parse(url);
    final fileName = path.basename(uri.path);
    final ext = path.extension(fileName).toLowerCase();
    return ext;
  }
}
