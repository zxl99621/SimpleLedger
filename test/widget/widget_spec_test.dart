/// 桌面小组件类型/尺寸模型([WidgetSpec])的目录与 key 映射断言。
///
/// 覆盖 .docs/home-widget/plan.md §二「逐组件 spec」的全部合法组合,以及
/// D2 back-compat(glance-medium 沿用旧 key `widgetImage`)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';

import 'package:beecount/widget/widget_spec.dart';

void main() {
  group('WidgetSpec.imageKey', () {
    test('glance-medium 沿用旧 key widgetImage(D2 back-compat)', () {
      expect(WidgetSpec.glanceMedium.imageKey, 'widgetImage');
    });

    test('其余 spec 一律 widget_<type>_<size>', () {
      expect(WidgetSpec.glanceSmall.imageKey, 'widget_glance_small');
    });

    test('目录内所有 imageKey 互不相同', () {
      final keys = WidgetSpec.catalog.map((s) => s.imageKey).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('WidgetSpec.catalog', () {
    test('极简版只保留 4×2 月支出组件', () {
      expect(WidgetSpec.catalog, [WidgetSpec.glanceMedium]);
      expect(
        WidgetSpec.catalog.map((s) => (s.type, s.size)).toList(),
        [(HWType.glance, HWSize.medium)],
      );
    });
  });

  group('WidgetSpec.defaultSet', () {
    test('至少保留 glance-medium(D5 退化默认集)', () {
      expect(WidgetSpec.defaultSet, [WidgetSpec.glanceMedium]);
    });
  });

  group('WidgetSpec.matchInstalled', () {
    test('iOS kind+family 精确匹配 glance-medium', () {
      final info = HomeWidgetInfo(
        iOSKind: 'BeeCountWidget',
        iOSFamily: 'systemMedium',
      );
      expect(WidgetSpec.matchInstalled(info), WidgetSpec.glanceMedium);
    });

    test('iOS kind 匹配但 family 不符,不匹配', () {
      // glance kind 只注册了 small/medium 两个 family(small 是补全新增,
      // 见 glanceSmall 文档),large 对该 kind 不存在,应匹配不到任何 spec。
      final info = HomeWidgetInfo(
        iOSKind: 'BeeCountWidget',
        iOSFamily: 'systemLarge',
      );
      expect(WidgetSpec.matchInstalled(info), isNull);
    });

    test('目录裁剪后不再匹配 glanceSmall', () {
      final info = HomeWidgetInfo(
        iOSKind: 'BeeCountWidget',
        iOSFamily: 'systemSmall',
      );
      expect(WidgetSpec.matchInstalled(info), isNull);
    });

    test('Android class name 匹配 glance-medium', () {
      final info = HomeWidgetInfo(
        androidClassName: 'com.tntlikely.beecount.BeeCountWidgetProvider',
        androidWidgetId: 1,
      );
      expect(WidgetSpec.matchInstalled(info), WidgetSpec.glanceMedium);
    });

    test('未知 kind/class 不匹配任何目录条目', () {
      final iosInfo = HomeWidgetInfo(iOSKind: 'SomeFutureWidget');
      final androidInfo = HomeWidgetInfo(
        androidClassName: 'com.tntlikely.beecount.SomeFutureProvider',
      );
      expect(WidgetSpec.matchInstalled(iosInfo), isNull);
      expect(WidgetSpec.matchInstalled(androidInfo), isNull);
    });

    // home_widget 透传 ComponentName.shortClassName:applicationId 与类包名
    // 相同时(prod 商店包)是带前导点的短名而非全限定名——dev/debug 因
    // applicationIdSuffix 不同才返回全名,dev 真机永远复现不了。这组 case
    // 是"商店包上所有组件被判未安装→全部空白"发布级缺陷的回归守卫(2026-07
    // review 发现)。
    group('Android shortClassName(prod 商店包形态)', () {
      test('前导点短名匹配 glance-medium', () {
        final info = HomeWidgetInfo(
          androidClassName: '.BeeCountWidgetProvider',
          androidWidgetId: 1,
        );
        expect(WidgetSpec.matchInstalled(info), WidgetSpec.glanceMedium);
      });

      test('短名后缀比对有点号边界,不误匹配前缀撞名类', () {
        final info = HomeWidgetInfo(
          // 全限定候选都以 .BeeCountWidgetProvider 结尾才算命中,这里的
          // .FakeBeeCountWidgetProvider 不应命中任何 spec。
          androidClassName: '.FakeBeeCountWidgetProvider',
        );
        expect(WidgetSpec.matchInstalled(info), isNull);
        expect(WidgetSpec.matchInstalledAll(info), isEmpty);
      });
    });
  });

  group('WidgetSpec 相等性', () {
    test('按 (type,size) 判等,忽略其它字段', () {
      // 与 glanceMedium 同 (type,size) 的手工构造实例应视为相等
      expect(WidgetSpec.glanceSmall == WidgetSpec.glanceMedium, isFalse);
      expect(WidgetSpec.glanceMedium == WidgetSpec.glanceMedium, isTrue);
    });

    test('logicalSize 是有效尺寸(宽高均 > 0)', () {
      for (final spec in WidgetSpec.catalog) {
        expect(spec.logicalSize.width, greaterThan(0));
        expect(spec.logicalSize.height, greaterThan(0));
      }
    });
  });
}
