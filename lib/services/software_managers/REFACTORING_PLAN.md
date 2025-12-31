# 软件管理器重构方案

## 目标
将每个 cate4 软件的启停、安装、管理逻辑从 `console_page.dart` 和 `install_service.dart` 中提取出来，独立成单独的 dart 文件，提高代码可读性和可维护性。

## 目录结构
```
lib/services/software_managers/
├── software_manager.dart              # 基础接口
├── software_manager_factory.dart      # 管理器工厂
├── nginx_manager.dart                 # Nginx 管理器
├── php_manager.dart                   # PHP 管理器
├── mysql_manager.dart                 # MySQL 管理器
├── pgsql_manager.dart                 # PostgreSQL 管理器
├── mongodb_manager.dart               # MongoDB 管理器
├── redis_manager.dart                 # Redis 管理器
├── rudis_manager.dart                 # Rudis 管理器
└── phpmyadmin_manager.dart            # phpMyAdmin 管理器（仅初始化）
```

## 接口设计

### SoftwareManager（基础接口）
- `start(Software server)` - 启动软件
- `stop(Software server)` - 停止软件（显示通知）
- `stopSilently(Software server)` - 停止软件（静默模式）
- `restart(Software server)` - 重启软件

### InitializableSoftwareManager（支持初始化）
继承自 `SoftwareManager`，额外提供：
- `initialize(String softwareDir, {onProgress})` - 初始化软件（安装后调用）

## 迁移清单

### console_page.dart 需要提取的方法
- [ ] `_startMysql` → `MysqlManager.start`
- [ ] `_stopMysql` → `MysqlManager.stop`
- [ ] `_restartMysql` → `MysqlManager.restart`
- [ ] `_startPgsql` → `PgsqlManager.start`
- [ ] `_stopPgsql` → `PgsqlManager.stop`
- [ ] `_restartPgsql` → `PgsqlManager.restart`
- [ ] `_startMongodb` → `MongodbManager.start`
- [ ] `_stopMongodb` → `MongodbManager.stop`
- [ ] `_restartMongodb` → `MongodbManager.restart`
- [ ] `_startRedis` → `RedisManager.start`
- [ ] `_stopRedis` → `RedisManager.stop`
- [ ] `_restartRedis` → `RedisManager.restart`
- [ ] `_startRudis` → `RudisManager.start`
- [ ] `_stopRudis` → `RudisManager.stop`
- [ ] `_restartRudis` → `RudisManager.restart`
- [ ] `_startPhp` → `PhpManager.start`
- [ ] `_stopPhp` → `PhpManager.stop`
- [ ] `_restartPhp` → `PhpManager.restart`
- [ ] `_startNginx` → `NginxManager.start`
- [ ] `_stopNginx` → `NginxManager.stop`
- [ ] `_restartNginx` → `NginxManager.restart`

### install_service.dart 需要提取的方法
- [ ] `_initializeMysql` → `MysqlManager.initialize`
- [ ] `_initializePgsql` → `PgsqlManager.initialize`
- [ ] `_initializeMongodb` → `MongodbManager.initialize`
- [ ] `_initializePhpmyadmin` → `PhpmyadminManager.initialize`

## 注意事项

1. **状态管理**：管理器不应该直接操作 UI 状态，而是返回操作结果，由调用者（console_page）负责更新 UI
2. **依赖注入**：管理器需要访问 ConfigService、NotificationService 等服务，可以直接使用（因为是静态服务）
3. **错误处理**：管理器负责执行操作和错误处理，通过返回值通知调用者
4. **回调函数**：对于需要更新状态的情况，可以通过回调函数或返回值来处理

## 实施步骤

1. ✅ 创建基础接口和工厂类
2. 创建 MySQL 管理器作为示例
3. 更新 console_page.dart 使用 MySQL 管理器
4. 更新 install_service.dart 使用 MySQL 管理器
5. 依次完成其他管理器的创建和迁移
6. 测试验证所有功能正常

