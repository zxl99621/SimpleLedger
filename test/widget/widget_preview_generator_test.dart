/// 桌面小组件「选择器预览图」生成器(不是回归测试)。
///
/// 用真实的 headless [GlanceView] + 示例数据渲染出静态 PNG,**中英双语两套**:
/// - 简体中文(默认) → `android/app/src/main/res/drawable-nodpi/`
/// - 英文            → `android/app/src/main/res/drawable-en-nodpi/`
///
/// `beecount_widget_info.xml` 的 `android:previewImage` 引用同名资源,Android
/// 按**系统语言**自动选取(与 values/values-en 的 strings 同一套资源限定符
/// 机制;其它语言回退默认简中)。
///
/// SimpleLedger 只发布 4×2 中号收支速览；小号预览仍一并生成,便于后续扩展。
///
/// **只在本机手动运行**,CI 上自动跳过(依赖 macOS 系统中文字体与本地
/// Flutter SDK 的 MaterialIcons 字体,且产物是二进制资源不是断言):
///
/// ```bash
/// GEN_WIDGET_PREVIEWS=1 noproxy flutter test \
///     test/widget/widget_preview_generator_test.dart
/// ```
///
/// 字体说明:flutter_test 默认字体是 Ahem(所有字形都是实心方块),直接渲染
/// 出的 PNG 没法看。这里把 macOS 的冬青黑体(Hiragino Sans GB,CJK+Latin
/// 全覆盖)以 family 名 `Roboto` 载入,并用 [DefaultTextStyle] 把该 family
/// 注入 View。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/widget/views/glance_view.dart';

const _honey = Color(0xFFF5A623);

final bool _enabled = Platform.environment['GEN_WIDGET_PREVIEWS'] == '1';

// ---------------------------------------------------------------------------
// 语言包:每种语言一套文案 + 输出目录
// ---------------------------------------------------------------------------

class _Pack {
  final String name; // 日志用
  final String outDir; // Android 资源目录(语言限定符)
  final String sym; // glance 预格式化金额用的符号
  final String glanceTitleLabel;
  final String monthSuffix;
  final String todayLabel;
  final String todayExpenseLabel, todayIncomeLabel;
  final String monthExpenseLabel, monthIncomeLabel;

  const _Pack({
    required this.name,
    required this.outDir,
    required this.sym,
    required this.glanceTitleLabel,
    required this.monthSuffix,
    required this.todayLabel,
    required this.todayExpenseLabel,
    required this.todayIncomeLabel,
    required this.monthExpenseLabel,
    required this.monthIncomeLabel,
  });
}

/// 简体中文(默认资源,文案镜像 app_zh.arb)。
const _zh = _Pack(
  name: 'zh',
  outDir: 'android/app/src/main/res/drawable-nodpi',
  sym: '¥',
  glanceTitleLabel: '收支速览', // widgetGalleryGlanceTitle
  monthSuffix: '月',
  todayLabel: '今日',
  todayExpenseLabel: '今日支出',
  todayIncomeLabel: '今日收入',
  monthExpenseLabel: '本月支出',
  monthIncomeLabel: '本月收入',
);

/// 英文(drawable-en,文案逐条镜像 app_en.arb 对应 key)。
const _en = _Pack(
  name: 'en',
  outDir: 'android/app/src/main/res/drawable-en-nodpi',
  sym: '\$',
  glanceTitleLabel: 'Overview', // widgetGalleryGlanceTitle
  monthSuffix: '', // widgetMonthSuffix(en 为空,徽章只显示月份数字)
  todayLabel: 'Today', // widgetToday
  todayExpenseLabel: "Today's Expense", // widgetTodayExpense
  todayIncomeLabel: "Today's Income", // widgetTodayIncome
  monthExpenseLabel: "Month's Expense", // widgetMonthExpense
  monthIncomeLabel: "Month's Income", // widgetMonthIncome
);

// ---------------------------------------------------------------------------
// 字体
// ---------------------------------------------------------------------------

/// 把系统 CJK 字体注册成默认 family `Roboto`;返回是否成功(失败则预览里的
/// 中文会渲染成方块,应中止检查环境而不是提交烂图)。
Future<bool> _loadCjkAsDefault() async {
  const candidates = [
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/PingFang.ttc',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (!f.existsSync()) continue;
    try {
      final bytes = f.readAsBytesSync();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return true;
    } catch (_) {
      // ttc 解析失败换下一个候选。
    }
  }
  return false;
}

Future<void> _loadMaterialIcons() async {
  var root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    // flutter_tester 位于 $FLUTTER_ROOT/bin/cache/artifacts/engine/<os>/,
    // 从可执行路径向上推导。
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 4; i++) {
      dir = dir.parent;
    }
    root = dir.path;
  }
  final otf = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!otf.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(otf.readAsBytesSync().buffer)));
  await loader.load();
}

// ---------------------------------------------------------------------------
// 截图
// ---------------------------------------------------------------------------

Future<void> _capture(
  WidgetTester tester,
  Widget view,
  Size logical,
  String outDir,
  String outName,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        // View 内部 TextStyle 未指定 fontFamily,merge 后继承这里的
        // Roboto(已被替换为 CJK 字体,见 _loadCjkAsDefault)。
        style: const TextStyle(fontFamily: 'Roboto', color: Colors.black),
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: view,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull, reason: '$outName 渲染抛异常');

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // @3x:主流手机物理密度是 3x(xxhdpi / iPhone Retina 3x),2x 源图在
    // 选择器里被放大显示会糊(2026-07 用户实机反馈)。
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('$outDir/$outName.png');
    out.createSync(recursive: true);
    out.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    // 供人工核对尺寸。
    // ignore: avoid_print
    print('生成 $outDir/$outName.png (${image.width}x${image.height})');
  });
}

Future<void> _generatePack(WidgetTester tester, _Pack p) async {
  // 收支速览·小号(Android 独立 provider 的选择器预览;iOS 走 placeholder
  // 不用它,但同名资源两语都备齐)
  await _capture(
    tester,
    GlanceView.small(
      todayExpense: '${p.sym}128.5',
      // 155dp 小卡底部双栏放不下千位金额(会 ellipsis),预览样本刻意取短。
      monthExpense: '${p.sym}842.3',
      monthIncome: '${p.sym}1,850',
      themeColor: _honey,
      redForIncome: false,
      dark: false,
      todayLabel: p.todayLabel,
      todayExpenseLabel: p.todayExpenseLabel,
      monthExpenseLabel: p.monthExpenseLabel,
      monthIncomeLabel: p.monthIncomeLabel,
      width: 155,
      height: 155,
    ),
    const Size(155, 155),
    p.outDir,
    'widget_preview_glance_small',
  );

  // 收支速览(中号,Android 2:1)
  await _capture(
    tester,
    GlanceView.medium(
      todayExpense: '${p.sym}128.5',
      todayIncome: '${p.sym}0',
      monthExpense: '${p.sym}6,842.3',
      monthIncome: '${p.sym}18,500',
      themeColor: _honey,
      redForIncome: false,
      dark: false,
      titleLabel: p.glanceTitleLabel,
      monthSuffix: p.monthSuffix,
      todayLabel: p.todayLabel,
      todayExpenseLabel: p.todayExpenseLabel,
      todayIncomeLabel: p.todayIncomeLabel,
      monthExpenseLabel: p.monthExpenseLabel,
      monthIncomeLabel: p.monthIncomeLabel,
      width: 364,
      height: 182,
    ),
    const Size(364, 182),
    p.outDir,
    'widget_preview_glance',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    final cjkOk = await _loadCjkAsDefault();
    expect(cjkOk, isTrue,
        reason: '未能加载系统 CJK 字体(Hiragino/PingFang),中文会渲染成方块;'
            '请在 macOS 上运行本生成器');
    await _loadMaterialIcons();
  });

  testWidgets(
    '生成中英双语收支速览选择器预览图',
    (tester) async {
      await _generatePack(tester, _zh);
      await _generatePack(tester, _en);
    },
    // 预览图生成器:GEN_WIDGET_PREVIEWS=1 手动运行,CI 上自动跳过。
    skip: !_enabled,
  );
}
