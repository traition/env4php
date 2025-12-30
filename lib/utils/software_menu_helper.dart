import 'package:flutter/material.dart';
import '../models/software_model.dart';

/// 软件管理菜单项类型
enum SoftwareMenuAction {
  manage,
  install,
  uninstall,
  viewLog,
  editNginxConfig,
  editRedisConfig,
  editRudisConfig,
  editMysqlIni,
  editMongodbConfig,
  editPgsqlConf,
  editPgsqlHba,
  editPgsqlIdent,
  setPhpCliVersion,
  editPhpIni,
  installPhpExtension,
  openDirectory,
}

/// 软件管理菜单项数据
class SoftwareMenuItem {
  final SoftwareMenuAction action;
  final String label;
  final IconData icon;
  final Color? iconColor;
  final Color? textColor;
  final bool isDivider;

  const SoftwareMenuItem({
    required this.action,
    required this.label,
    required this.icon,
    this.iconColor,
    this.textColor,
    this.isDivider = false,
  });

  const SoftwareMenuItem.divider()
      : action = SoftwareMenuAction.manage,
        label = '',
        icon = Icons.help_outline,
        iconColor = null,
        textColor = null,
        isDivider = true;
}

/// 软件管理菜单辅助类
class SoftwareMenuHelper {
  /// 根据软件信息构建右键菜单项列表
  /// 直接显示管理对话框中的所有菜单项，而不是先显示"管理"选项
  static Future<List<SoftwareMenuItem>> buildContextMenuItems(
    Software software, {
    required bool isInstalled,
    SoftwareSource? softwareSource,
  }) async {
    final items = <SoftwareMenuItem>[];

    // 如果未安装，显示安装菜单项
    if (!isInstalled) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.install,
        label: '安装',
        icon: Icons.download,
      ));
      return items;
    }

    // 如果已安装，直接显示管理对话框中的所有菜单项
    final isNginx = software.cate4?.toLowerCase() == 'nginx';
    final isRedis = software.cate4?.toLowerCase() == 'redis';
    final isRudis = software.cate4?.toLowerCase() == 'rudis';
    final isMysql = software.cate4?.toLowerCase() == 'mysql';
    final isPgsql = software.cate4?.toLowerCase() == 'pgsql';
    final isMongodb = software.cate4?.toLowerCase() == 'mongodb';
    final isPhp = softwareSource != null &&
        softwareSource.php.any((s) => s.id == software.id);

    // Nginx 专用选项
    if (isNginx) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editNginxConfig,
        label: '编辑 nginx.conf',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.viewLog,
        label: '查看 error.log',
        icon: Icons.description,
      ));
      items.add(SoftwareMenuItem.divider());
    }

    // Redis 专用选项
    if (isRedis) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editRedisConfig,
        label: '编辑conf',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem.divider());
    }

    // Rudis 专用选项
    if (isRudis) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editRudisConfig,
        label: '编辑配置',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem.divider());
    }

    // MySQL 专用选项
    if (isMysql) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editMysqlIni,
        label: '编辑ini',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem.divider());
    }

    // PostgreSQL 专用选项
    if (isPgsql) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editPgsqlConf,
        label: '编辑 postgresql.conf',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editPgsqlHba,
        label: '编辑 pg_hba.conf',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editPgsqlIdent,
        label: '编辑 pg_ident.conf',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem.divider());
    }

    // MongoDB 专用选项
    if (isMongodb) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editMongodbConfig,
        label: '编辑配置',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem.divider());
    }

    // PHP 专用选项
    if (isPhp) {
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.setPhpCliVersion,
        label: '设为php-cli版本',
        icon: Icons.settings,
      ));
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.editPhpIni,
        label: '编辑 php.ini',
        icon: Icons.edit,
      ));
      items.add(SoftwareMenuItem(
        action: SoftwareMenuAction.installPhpExtension,
        label: '安装扩展',
        icon: Icons.extension,
      ));
      items.add(SoftwareMenuItem.divider());
    }

    // 通用选项
    items.add(SoftwareMenuItem(
      action: SoftwareMenuAction.openDirectory,
      label: '打开目录',
      icon: Icons.folder,
    ));
    items.add(SoftwareMenuItem(
      action: SoftwareMenuAction.uninstall,
      label: '卸载',
      icon: Icons.delete,
      iconColor: Colors.red,
      textColor: Colors.red,
    ));

    return items;
  }

  /// 根据软件信息构建管理对话框的菜单项列表（用于 ListTile）
  static Future<List<Widget>> buildManageDialogItems(
    Software software, {
    required SoftwareSource? softwareSource,
    required Function(SoftwareMenuAction) onAction,
    required BuildContext context,
  }) async {
    final items = <Widget>[];

    final isNginx = software.cate4?.toLowerCase() == 'nginx';
    final isRedis = software.cate4?.toLowerCase() == 'redis';
    final isRudis = software.cate4?.toLowerCase() == 'rudis';
    final isMysql = software.cate4?.toLowerCase() == 'mysql';
    final isPgsql = software.cate4?.toLowerCase() == 'pgsql';
    final isMongodb = software.cate4?.toLowerCase() == 'mongodb';
    final isPhp = softwareSource != null &&
        softwareSource.php.any((s) => s.id == software.id);

    // Nginx 专用选项
    if (isNginx) {
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑 nginx.conf'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editNginxConfig);
          },
        ),
      );
      items.add(
        ListTile(
          leading: const Icon(Icons.description),
          title: const Text('查看 error.log'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.viewLog);
          },
        ),
      );
      items.add(const Divider());
    }

    // Redis 专用选项
    if (isRedis) {
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑conf'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editRedisConfig);
          },
        ),
      );
      items.add(const Divider());
    }

    // Rudis 专用选项
    if (isRudis) {
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑配置'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editRudisConfig);
          },
        ),
      );
      items.add(const Divider());
    }

    // MySQL 专用选项
    if (isMysql) {
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑ini'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editMysqlIni);
          },
        ),
      );
      items.add(const Divider());
    }

    // PostgreSQL 专用选项
    if (isPgsql) {
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑 postgresql.conf'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editPgsqlConf);
          },
        ),
      );
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑 pg_hba.conf'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editPgsqlHba);
          },
        ),
      );
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑 pg_ident.conf'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editPgsqlIdent);
          },
        ),
      );
      items.add(const Divider());
    }

    // MongoDB 专用选项
    if (isMongodb) {
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑配置'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editMongodbConfig);
          },
        ),
      );
      items.add(const Divider());
    }

    // PHP 专用选项
    if (isPhp) {
      items.add(
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('设为php-cli版本'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.setPhpCliVersion);
          },
        ),
      );
      items.add(
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('编辑 php.ini'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.editPhpIni);
          },
        ),
      );
      items.add(
        ListTile(
          leading: const Icon(Icons.extension),
          title: const Text('安装扩展'),
          onTap: () {
            Navigator.of(context).pop();
            onAction(SoftwareMenuAction.installPhpExtension);
          },
        ),
      );
      items.add(const Divider());
    }

    // 通用选项
    items.add(
      ListTile(
        leading: const Icon(Icons.folder),
        title: const Text('打开目录'),
        onTap: () {
          Navigator.of(context).pop();
          onAction(SoftwareMenuAction.openDirectory);
        },
      ),
    );
    items.add(
      ListTile(
        leading: const Icon(Icons.delete),
        title: const Text('卸载'),
        onTap: () {
          Navigator.of(context).pop();
          onAction(SoftwareMenuAction.uninstall);
        },
      ),
    );

    return items;
  }
}

