import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'window_button.dart';

/// 应用标题栏
class TitleBar extends StatelessWidget {
  final String title;
  final Widget? toolsList; // 可选的工具列表

  const TitleBar({super.key, required this.title, this.toolsList});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.transparent, // 背景透明
      ),
      child: Row(
        children: [
          // 左侧标题 - 固定宽度160，与左侧tab一致，可拖动区域
          SizedBox(
            width: 160,
            child: Listener(
              onPointerDown: (event) {
                // 直接调用系统级别的拖动
                windowManager.startDragging();
              },
              behavior: HitTestBehavior.translucent,
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 工具列表（如果有）- 显示在title之后
          if (toolsList != null)
            Expanded(child: toolsList!)
          else
            const Spacer(), // 如果没有工具列表，使用 Spacer 占据中间空间
          // 右侧窗口控制按钮
          Row(
            children: [
              // 最小化按钮
              WindowButton(
                icon: Icons.remove,
                onPressed: () => windowManager.minimize(),
              ),
              // 最大化/还原按钮
              WindowButton(
                icon: Icons.crop_square,
                onPressed: () async {
                  bool isMaximized = await windowManager.isMaximized();
                  if (isMaximized) {
                    windowManager.restore();
                  } else {
                    windowManager.maximize();
                  }
                },
              ),
              // 关闭按钮
              WindowButton(
                icon: Icons.close,
                onPressed: () => windowManager.close(),
                isCloseButton: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
