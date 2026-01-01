import 'dart:io';
import '../models/software_model.dart';
import '../services/software_source_service.dart';
import '../services/config_service.dart';

/// 软件辅助工具类
/// 提供共享的软件相关工具方法
class SoftwareHelper {
  /// 检查 pgsql 是否已安装
  /// [softwareSource] 软件源（可选，如果不提供则从服务获取）
  /// [storagePath] 存储路径（可选，如果不提供则从服务获取）
  /// [installedSoftware] 已安装的软件列表（可选，如果不提供则从目录检查）
  /// 返回 true 表示 pgsql 已安装
  static Future<bool> isPgsqlInstalled({
    SoftwareSource? softwareSource,
    String? storagePath,
    List<Software>? installedSoftware,
  }) async {
    // 获取软件源
    final source = softwareSource ?? await SoftwareSourceService.getSource();
    if (source == null) return false;

    // 查找 pgsql 软件
    final pgsql = source.databases.firstWhere(
      (s) => s.cate4?.toLowerCase() == 'pgsql',
      orElse: () => Software(
        id: '',
        name: '',
        byte: 0,
        downloadURL: '',
        commands: [],
        attachments: [],
      ),
    );

    if (pgsql.id.isEmpty) return false;

    // 如果提供了已安装软件列表，使用它检查
    if (installedSoftware != null) {
      return installedSoftware.any((s) => s.id == pgsql.id);
    }

    // 否则从目录检查
    final path = storagePath ?? await ConfigService.getStoragePath();
    if (path == null) return false;

    // 检查 pgsql 目录是否存在（可能在 servers 或 databases 目录下）
    final serversDir = Directory('$path/servers/${pgsql.id}');
    final databasesDir = Directory('$path/databases/${pgsql.id}');

    return await serversDir.exists() || await databasesDir.exists();
  }

  /// 创建虚拟的 pgAdmin4 应用
  /// 返回 pgAdmin4 软件对象
  static Software createPgAdmin4Software() {
    return Software(
      id: 'pgadmin4',
      name: 'pgAdmin4',
      description: 'PostgreSQL自带管理工具',
      byte: 0,
      downloadURL: '',
      commands: [],
      attachments: [],
      cate4: 'pgadmin4',
    );
  }
}

