import 'package:flutter/material.dart';

/// 分类图标的圆形点击目标。
///
/// 点击水波纹、选中背景和图标本身共用同一个 [size] 圆形区域，避免
/// `InkWell` 包住整个「图标 + 文字」列时水波纹比图标大一圈。
class CategoryIconButton extends StatelessWidget {
  const CategoryIconButton({
    super.key,
    required this.size,
    required this.selected,
    required this.primaryColor,
    required this.backgroundColor,
    required this.onTap,
    required this.child,
  });

  final double size;
  final bool selected;
  final Color primaryColor;
  final Color backgroundColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? primaryColor.withValues(alpha: 0.25)
          : backgroundColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashColor: primaryColor.withValues(alpha: 0.12),
        highlightColor: primaryColor.withValues(alpha: 0.06),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}
