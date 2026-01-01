import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/home_page.dart';
import 'services/notification_service.dart';
import 'services/storage_monitor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await NotificationService.initialize();

  // 启动存储目录监控
  await StorageMonitorService().startMonitoring();

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
