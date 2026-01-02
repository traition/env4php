import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/home_page.dart';
import 'pages/console_page.dart';
import 'services/notification_service.dart';
import 'services/storage_monitor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await NotificationService.initialize();

  // 启动存储目录监控
  await StorageMonitorService().startMonitoring();

  // 阻止默认关闭行为，以便显示确认对话框
  await windowManager.setPreventClose(true);

  const defaultSize = Size(1280, 720);
  final windowSize = Size(defaultSize.width * 0.7, defaultSize.height * 0.8);

  WindowOptions windowOptions = WindowOptions(
    size: windowSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<bool> onWindowClose() async {
    // 获取 context
    final navigatorKey = NotificationService.navigatorKey;
    if (navigatorKey.currentContext == null) {
      // 如果 context 不可用，直接关闭
      await windowManager.destroy();
      return true;
    }

    // 显示确认对话框
    final shouldClose = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('确认关闭'),
        content: const Text('关闭应用将停止所有正在运行的服务，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认关闭'),
          ),
        ],
      ),
    );

    if (shouldClose == true) {
      // 用户确认关闭，停止所有服务
      final consoleState = ConsolePage.globalKey.currentState;
      if (consoleState != null) {
        await consoleState.stopAllServersOnClose();
      }
      // 手动关闭窗口
      await windowManager.destroy();
      return true;
    } else {
      // 用户取消，返回 false 阻止关闭窗口
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // title: 'env4php',
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: kDebugMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F2F3), // 浅色背景
        fontFamily: 'Microsoft Yahei UI', // 默认字体
        fontFamilyFallback: const ['Microsoft YaHei', '微软雅黑'], // 字体回退列表
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A), // 深色背景
        fontFamily: 'Microsoft Yahei UI', // 默认字体
        fontFamilyFallback: const ['Microsoft YaHei', '微软雅黑'], // 字体回退列表
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(title: 'env4php'),
    );
  }
}
