import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart' show HomeWidgetInfo;

/// 桌面小组件内容类型。
///
/// SimpleLedger 只保留「收支速览」(glance)；上游的净资产、快速记账、预算、
/// 最近交易、仪表盘、消费节奏、蜂迹等类型已随功能裁剪一并移除。
enum HWType { glance }

/// 桌面小组件尺寸档位,对应 iOS `systemSmall/Medium/Large`、Android 对应
/// 网格尺寸。
enum HWSize { small, medium, large }

/// 单个"内容类型 + 尺寸"的渲染规格。
///
/// 渲染管线(`WidgetManager.updateAllWidgets`)按 [catalog] 匹配用户"已安装"
/// 的组件(`HomeWidget.getInstalledWidgets()`),只对命中的 spec 取数、渲染成
/// 图片,写入 [imageKey] 对应的共享存储位置,原生壳按 key 读取展示。
@immutable
class WidgetSpec {
  final HWType type;
  final HWSize size;

  /// 渲染时使用的逻辑尺寸(pt/dp,对应 `HomeWidget.renderFlutterWidget` 的
  /// `logicalSize`)。
  ///
  /// 例外是 [glanceMedium]——其渲染尺寸按平台(iOS 364×169 / Android
  /// 364×182)分叉、不直接取用这里的值(见 `WidgetManager._renderGlance`)。
  final Size logicalSize;

  /// iOS Widget `kind` 标识(对应 [HomeWidgetInfo.iOSKind])。只有已在原生壳
  /// 注册的类型才有值。
  final String? iosKind;

  /// iOS Widget family 字符串(如 `systemMedium`),仅已注册类型有值。
  final String? iosFamily;

  /// Android `AppWidgetProvider` 主类名(对应
  /// [HomeWidgetInfo.androidClassName]),仅已注册类型有值。
  final String? androidClassName;

  const WidgetSpec._({
    required this.type,
    required this.size,
    required this.logicalSize,
    this.iosKind,
    this.iosFamily,
    this.androidClassName,
  });

  /// 渲染输出图片的存储 key,原生壳按此 key 读取图片文件路径。
  ///
  /// **例外(D2 back-compat)**:中号收支速览([glanceMedium])沿用旧 key
  /// `widgetImage`,**不**改成 `widget_glance_medium`——这样现有 iOS
  /// `BeeCountWidget.swift` / Android `BeeCountWidgetProvider.kt` 原生壳
  /// 完全不用改,存量用户桌面已放置的组件继续工作。
  String get imageKey {
    if (this == glanceMedium) {
      return 'widgetImage';
    }
    return 'widget_${type.name}_${size.name}';
  }

  /// 收支速览(glance)小号规格。
  ///
  /// SimpleLedger 的 [catalog] 只发布中号;小号保留为同一视图的合法尺寸定义,
  /// 便于原生壳后续扩展时复用。
  static const glanceSmall = WidgetSpec._(
    type: HWType.glance,
    size: HWSize.small,
    logicalSize: Size(155, 155),
    iosKind: 'BeeCountWidget',
    iosFamily: 'systemSmall',
    androidClassName:
        'com.tntlikely.beecount.BeeCountGlanceSmallWidgetProvider',
  );

  /// 唯一发布的组件:中号收支速览。
  ///
  /// 原生标识与升级前完全一致(iOS kind `BeeCountWidget` / Android provider
  /// 类名 `BeeCountWidgetProvider`),存量桌面放置靠这两个标识存活,不可更改。
  static const glanceMedium = WidgetSpec._(
    type: HWType.glance,
    size: HWSize.medium,
    logicalSize: Size(364, 169),
    iosKind: 'BeeCountWidget',
    iosFamily: 'systemMedium',
    androidClassName: 'com.tntlikely.beecount.BeeCountWidgetProvider',
  );

  /// 全部合法 (type, size) 组合的目录。
  ///
  /// SimpleLedger 只保留 4×2 横版「本月支出」小组件（glanceMedium）。
  static const List<WidgetSpec> catalog = [
    glanceMedium,
  ];

  /// 渲染管线拿不到"已安装组件"列表时(home_widget 版本过低 / 平台调用
  /// 异常)的退化默认集。至少保留 [glanceMedium],避免存量用户的组件因升级
  /// 而断更(D5)。
  static const List<WidgetSpec> defaultSet = [glanceMedium];

  /// Android 已安装类名比对,兼容 home_widget 透传的**短类名**形式。
  ///
  /// home_widget(0.9.x `HomeWidgetPlugin.kt` getInstalledWidgets)返回的是
  /// `ComponentName.shortClassName`:当 applicationId 与类所在包名相同时
  /// (**prod 商店包** `com.tntlikely.beecount` 正是如此),它是带前导点的
  /// 短名 `.BeeCountWidgetProvider` 而**不是**全限定名;dev/debug 因
  /// applicationIdSuffix(`.dev`/`.debug`)与类包名不同才返回全名。此前只按
  /// 全限定名精确比对,商店包上所有条目都匹配不到 → 被当成"一个组件都没装"
  /// → 全部不渲染(dev 真机永远复现不了的发布级缺陷,2026-07 review 发现)。
  ///
  /// 短名以 `.` 开头,`candidate.endsWith(installed)` 自带点号边界,不会把
  /// `XxxBeeCountWidgetProvider` 误匹配成 `BeeCountWidgetProvider`。
  static bool _androidClassMatches(String? installed, String? candidate) {
    if (installed == null || installed.isEmpty || candidate == null) {
      return false;
    }
    if (installed == candidate) return true;
    return installed.startsWith('.') && candidate.endsWith(installed);
  }

  /// 把平台 `HomeWidget.getInstalledWidgets()` 返回的单条 [HomeWidgetInfo]
  /// 匹配到 [catalog] 中的 spec;匹配不到返回 null。
  static WidgetSpec? matchInstalled(HomeWidgetInfo info) {
    for (final spec in catalog) {
      if (spec.iosKind != null && spec.iosKind == info.iOSKind) {
        if (spec.iosFamily == null || spec.iosFamily == info.iOSFamily) {
          return spec;
        }
      }
      if (_androidClassMatches(info.androidClassName, spec.androidClassName)) {
        return spec;
      }
    }
    return null;
  }

  /// 把平台已安装信息映射到 catalog 里所有应为它渲染的 spec。
  ///
  /// - **iOS**:kind + family 精确匹配(通常一条)。
  /// - **Android**:AppWidget 可被用户自由缩放,`getInstalledWidgets` 不带当前
  ///   尺寸信息;当前目录只有中号一项,因此命中类名即返回该项。
  static List<WidgetSpec> matchInstalledAll(HomeWidgetInfo info) {
    final matched = <WidgetSpec>[];
    for (final spec in catalog) {
      final iosHit = spec.iosKind != null &&
          spec.iosKind == info.iOSKind &&
          (spec.iosFamily == null || spec.iosFamily == info.iOSFamily);
      final androidHit =
          _androidClassMatches(info.androidClassName, spec.androidClassName);
      if (iosHit || androidHit) {
        matched.add(spec);
      }
    }
    return matched;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WidgetSpec && other.type == type && other.size == size);

  @override
  int get hashCode => Object.hash(type, size);

  @override
  String toString() => 'WidgetSpec(${type.name}, ${size.name}, '
      'imageKey: $imageKey)';
}
