import '../../models/software_model.dart';
import 'software_manager.dart';
import 'nginx_manager.dart';
import 'php_manager.dart';
import 'mysql_manager.dart';
import 'pgsql_manager.dart';
import 'mongodb_manager.dart';
import 'redis_manager.dart';
import 'rudis_manager.dart';
import 'phpmyadmin_manager.dart';

/// 软件管理器工厂
/// 根据软件的 cate4 返回对应的管理器实例
class SoftwareManagerFactory {
  static final Map<String, SoftwareManager> _managers = {
    'nginx': NginxManager(),
    'php': PhpManager(),
    'mysql': MysqlManager(),
    'pgsql': PgsqlManager(),
    'mongodb': MongodbManager(),
    'redis': RedisManager(),
    'rudis': RudisManager(),
  };

  /// phpMyAdmin 管理器（特殊处理，不是 SoftwareManager）
  static final PhpmyadminManager _phpmyadminManager = PhpmyadminManager();

  /// 根据软件获取对应的管理器
  /// [software] 软件信息
  /// 返回管理器实例，如果不存在则返回 null
  static SoftwareManager? getManager(Software software) {
    final cate4 = software.cate4?.toLowerCase();
    if (cate4 == null) {
      return null;
    }

    // phpMyAdmin 特殊处理：不是 SoftwareManager
    if (cate4 == 'phpmyadmin') {
      return null; // phpMyAdmin 不使用 SoftwareManager 接口
    }

    return _managers[cate4];
  }

  /// 获取 phpMyAdmin 管理器（用于初始化）
  /// 返回 phpMyAdmin 管理器实例
  static PhpmyadminManager getPhpmyadminManager() {
    return _phpmyadminManager;
  }

  /// 检查软件是否有对应的管理器
  /// [software] 软件信息
  /// 返回是否有管理器
  static bool hasManager(Software software) {
    return getManager(software) != null;
  }

  /// 获取所有支持的管理器类型
  /// 返回 cate4 列表
  static List<String> getSupportedTypes() {
    return _managers.keys.toList();
  }
}

