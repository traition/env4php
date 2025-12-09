import 'package:flutter/material.dart';

/// 窗口控制按钮组件
class WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isCloseButton;

  const WindowButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.isCloseButton = false,
  });

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color backgroundColor = Colors.transparent;
    Color iconColor = Theme.of(context).colorScheme.onSurface;

    if (widget.isCloseButton) {
      if (_isHovered) {
        backgroundColor = Colors.red;
        iconColor = Colors.white;
      }
    } else {
      if (_isHovered) {
        backgroundColor = Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.1);
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 40,
          color: backgroundColor,
          child: Icon(widget.icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

