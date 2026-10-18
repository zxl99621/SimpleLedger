import 'package:flutter/widgets.dart';

/// 把外层 Scaffold 的键盘/底部导航布局状态显式传给子树。
///
/// 外层 `Scaffold(resizeToAvoidBottomInset: true)` 会消费键盘 inset，页面内部
/// 再读 `MediaQuery.viewInsets.bottom` 可能恒为 0；因此这里由外壳统一下发，
/// 避免页面自己猜键盘是否弹起。
class KeyboardLayoutScope extends InheritedWidget {
  const KeyboardLayoutScope({
    super.key,
    required this.keyboardOpen,
    required this.bottomNavHeight,
    required super.child,
  });

  /// 键盘是否弹起（由外层 Scaffold 的 MediaQuery 计算）。
  final bool keyboardOpen;

  /// 键盘收起时需要为悬浮底部导航预留的高度；键盘弹起时应为 0。
  final double bottomNavHeight;

  static KeyboardLayoutScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<KeyboardLayoutScope>();
  }

  @override
  bool updateShouldNotify(KeyboardLayoutScope oldWidget) {
    return oldWidget.keyboardOpen != keyboardOpen ||
        oldWidget.bottomNavHeight != bottomNavHeight;
  }
}
