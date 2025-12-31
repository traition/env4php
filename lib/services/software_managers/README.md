# 软件管理器模块

## 概述

本模块将每个 cate4 软件的启停、安装、管理逻辑从 `console_page.dart` 和 `install_service.dart` 中提取出来，独立成单独的 dart 文件，提高了代码的可读性和可维护性。

## 目录结构

```
lib/services/software_managers/
├── software_manager.dart              # 基础接口
├── software_manager_factory.dart      # 管理器工厂
├── software_manager_helper.dart       # 共享辅助方法
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
所有需要启停功能的软件管理器实现此接口：
- `start(Software server)` - 启动软件
- `stop(Software server)` - 停止软件（显示通知）
- `stopSilently(Software server)` - 停止软件（静默模式）
- `restart(Software server)` - 重启软件

### InitializableSoftwareManager（支持初始化）
继承自 `SoftwareManager`，额外提供：
- `initialize(String softwareDir, {onProgress})` - 初始化软件（安装后调用）

## 已实现的管理器

### 1. NginxManager
- **功能**：Nginx 服务器的启停和重启
- **特点**：启动前检查配置，使用 detached 模式启动进程

### 2. PhpManager
- **功能**：PHP 进程的启停和重启
- **特点**：
  - 使用 php-cgi-spawner.exe 启动 PHP
  - 自动管理端口分配
  - 与 nginx 配置集成
  - 跟踪进程 PID

### 3. MysqlManager
- **功能**：MySQL 服务的启停、重启和初始化
- **特点**：
  - 使用 Windows 服务管理（sc start/stop）
  - 自动安装服务（如果未安装）
  - 初始化数据库（--initialize-insecure）

### 4. PgsqlManager
- **功能**：PostgreSQL 服务的启停、重启和初始化
- **特点**：
  - 使用 Windows 服务管理（net start/stop）
  - 检查服务状态避免重复操作
  - 初始化数据库并注册服务

### 5. MongodbManager
- **功能**：MongoDB 服务的启停、重启和初始化
- **特点**：
  - 使用 Windows 服务管理（net start/stop）
  - 检查服务状态避免重复操作
  - 注册服务并配置启动方式

### 6. RedisManager
- **功能**：Redis 进程的启停和重启
- **特点**：
  - 使用进程管理（Process.start）
  - 监听输出判断启动成功/失败
  - 跟踪进程 PID
  - 支持通过进程名查找 PID

### 7. RudisManager
- **功能**：Rudis 进程的启停和重启
- **特点**：
  - 使用进程管理（Process.start）
  - 监听 stdout 和 stderr 判断启动成功/失败
  - 跟踪进程 PID
  - 支持通过进程名查找 PID

### 8. PhpmyadminManager
- **功能**：phpMyAdmin 的初始化（创建 Nginx 项目）
- **特点**：
  - 仅提供初始化功能，不提供启停功能
  - 检查 PHP 和 nginx 依赖
  - 自动创建 Nginx 项目配置

## 使用方法

### 在 console_page.dart 中使用

```dart
import '../services/software_managers/software_manager_factory.dart';

// 启动服务器
final manager = SoftwareManagerFactory.getManager(server);
if (manager != null) {
  final result = await manager.start(server);
  if (result.$1) {
    setState(() {
      _setServerRunningStatus(server.id, true);
    });
  }
}

// 停止服务器
final result = await manager.stop(server);
if (result.$1) {
  setState(() {
    _setServerRunningStatus(server.id, false);
  });
}
```

### 在 install_service.dart 中使用

```dart
import '../services/software_managers/software_manager_factory.dart';

// 初始化软件
if (software.cate4?.toLowerCase() == 'mysql') {
  final manager = SoftwareManagerFactory.getManager(software);
  if (manager is InitializableSoftwareManager) {
    final result = await manager.initialize(
      softwareDir.path,
      onProgress: onProgress,
    );
  }
}

// phpMyAdmin 特殊处理
if (software.cate4?.toLowerCase() == 'phpmyadmin') {
  final manager = SoftwareManagerFactory.getPhpmyadminManager();
  final result = await manager.initialize(
    softwareDir.path,
    onProgress: onProgress,
  );
}
```

## 注意事项

1. **状态管理**：管理器不直接操作 UI 状态，而是返回操作结果，由调用者（console_page）负责更新 UI
2. **PID 跟踪**：Redis、Rudis、PHP 管理器需要跟踪进程 PID，这些 PID 由管理器内部管理，但调用者可以通过 `setProcessId` 和 `getProcessId` 方法访问
3. **错误处理**：所有方法都返回 `(bool success, String? error)` 元组，调用者需要根据返回值处理成功/失败情况
4. **通知显示**：`stop` 方法会显示通知，`stopSilently` 方法不会显示通知（用于应用关闭时）

## 下一步工作

1. 更新 `console_page.dart` 使用新的管理器
2. 更新 `install_service.dart` 使用新的管理器
3. 测试验证所有功能正常

