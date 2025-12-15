import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 系统通知服务
class NotificationService {
  static OverlayEntry? _currentOverlay;
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// 初始化通知服务
  static Future<void> initialize() async {
    // 不需要初始化，直接使用
  }

  /// 显示消息条通知（右下角，10秒后自动消失）
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    Color? backgroundColor,
    Color? textColor,
    IconData? icon,
  }) async {
    // 移除之前的消息条
    _removeCurrentOverlay();

    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState == null) {
      debugPrint('无法获取 Overlay，无法显示通知');
      return;
    }

    // 创建新的消息条
    _currentOverlay = OverlayEntry(
      builder: (context) => _NotificationMessage(
        title: title,
        body: body,
        backgroundColor:
            backgroundColor ?? Theme.of(context).colorScheme.surface,
        textColor: textColor ?? Theme.of(context).colorScheme.onSurface,
        icon: icon,
        onDismiss: () => _removeCurrentOverlay(),
      ),
    );

    overlayState.insert(_currentOverlay!);

    // 10秒后自动消失
    Future.delayed(const Duration(seconds: 10), () {
      _removeCurrentOverlay();
    });
  }

  /// 移除当前的消息条
  static void _removeCurrentOverlay() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }

  /// 显示错误通知
  static Future<void> showError({
    required String title,
    required String message,
  }) async {
    await showNotification(
      title: title,
      body: message,
      backgroundColor: Colors.red.shade700,
      textColor: Colors.white,
      icon: Icons.error_outline,
    );
  }

  /// 显示成功通知
  static Future<void> showSuccess({
    required String title,
    required String message,
  }) async {
    await showNotification(
      title: title,
      body: message,
      backgroundColor: Colors.green.shade700,
      textColor: Colors.white,
      icon: Icons.check_circle_outline,
    );
  }

  /// 显示信息通知
  static Future<void> showInfo({
    required String title,
    required String message,
  }) async {
    await showNotification(
      title: title,
      body: message,
      backgroundColor: Colors.blue.shade700,
      textColor: Colors.white,
      icon: Icons.info_outline,
    );
  }
}

/// 消息条组件
class _NotificationMessage extends StatefulWidget {
  final String title;
  final String body;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;
  final VoidCallback onDismiss;

  const _NotificationMessage({
    required this.title,
    required this.body,
    required this.backgroundColor,
    required this.textColor,
    this.icon,
    required this.onDismiss,
  });

  @override
  State<_NotificationMessage> createState() => _NotificationMessageState();
}

class _NotificationMessageState extends State<_NotificationMessage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: widget.backgroundColor,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400, minWidth: 300),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: widget.textColor, size: 24),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.body,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 14,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close, color: widget.textColor, size: 20),
                    onPressed: _dismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
