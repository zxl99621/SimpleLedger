import 'dart:async' show Completer;
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../data/repositories/base_repository.dart';
import '../l10n/app_localizations.dart';
import '../services/system/logger_service.dart';
import '../utils/currencies.dart' show getCurrencySymbol;
import '../widgets/biz/format_money.dart' show formatMoneyCompact;
import 'views/glance_view.dart';
import 'widget_data_service.dart';
import 'widget_spec.dart';

const _tag = 'WidgetManager';

/// 把 home_widget 平台 `getInstalledWidgets()` 的原始结果([HomeWidgetInfo]
/// 列表)映射为本地 [WidgetSpec] 目录中的条目;匹配不到目录的条目被丢弃。
///
/// 纯函数,不触碰平台通道,便于单测。
List<WidgetSpec> matchInstalledSpecs(List<HomeWidgetInfo> infos) {
  final result = <WidgetSpec>[];
  for (final info in infos) {
    result.addAll(WidgetSpec.matchInstalledAll(info));
  }
  return result;
}

/// 挑选本次需要渲染的 spec 列表(D5:只渲已安装的,避免盲渲)。
///
/// - [installed] 为 `null` 表示"拿不到已安装组件列表"(home_widget 版本
///   过低 / 平台调用异常),退化为默认集([WidgetSpec.defaultSet],至少保留
///   glance-medium),避免存量用户的组件因本次升级而断更。
/// - [installed] 为空列表表示"确实一个组件都没装",按 D5 原则不渲染任何
///   内容。
/// - 其余情况原样返回(按 (type,size) 去重)。
///
/// 纯函数,不依赖平台通道,便于单测。
List<WidgetSpec> selectSpecsToRender(
  List<WidgetSpec>? installed, {
  bool warmUpAll = false,
}) {
  // 预热模式:无视"已安装"列表,渲染整个目录(D5「只渲已安装」的显式例外,
  // 动机见 updateAllWidgets 的 warmUpAllSpecs 参数文档)。
  if (warmUpAll) {
    return WidgetSpec.catalog;
  }
  if (installed == null) {
    return WidgetSpec.defaultSet;
  }
  if (installed.isEmpty) {
    return const [];
  }
  final seen = <WidgetSpec>{};
  final result = <WidgetSpec>[];
  for (final spec in installed) {
    if (seen.add(spec)) {
      result.add(spec);
    }
  }
  return result;
}

/// 预热批次的渲染顺序:整个 [WidgetSpec.catalog],但把 [installedFirst]
/// (用户桌面上已放置的组件)排到最前——预热要渲全目录,已安装的先出图,
/// 缩短"打开 App 后桌面组件才刷新"的感知等待。
///
/// 纯函数,便于单测。
List<WidgetSpec> orderCatalogForWarmUp(List<WidgetSpec> installedFirst) {
  return [
    ...installedFirst,
    ...WidgetSpec.catalog.where((s) => !installedFirst.contains(s)),
  ];
}

/// 供没有 [BuildContext] 的调用点(`main.dart` 的 `_WidgetUpdateObserver`、
/// `providers/theme_providers.dart` 的主题色/收支配色监听)解析当前 App
/// 语言,拿到与真正 `AppLocalizations.of(context)` 尽量一致的文案实例。
///
/// [explicitLocale] 应传入 `languageProvider` 的当前状态:非 null 表示用户
/// 手动选择过语言,直接采用;为 null 表示"跟随系统",退化为只看
/// `PlatformDispatcher.instance.locale` 一层匹配。
///
/// 匹配不到任何已支持语言时兜底
/// [AppLocalizations.supportedLocales] 的第一项,与 Flutter 默认解析算法一致。
AppLocalizations resolveWidgetLocalizations(Locale? explicitLocale) {
  final candidate = explicitLocale ?? PlatformDispatcher.instance.locale;

  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == candidate.languageCode &&
        supported.countryCode == candidate.countryCode) {
      return lookupAppLocalizations(supported);
    }
  }
  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == candidate.languageCode) {
      return lookupAppLocalizations(supported);
    }
  }
  return lookupAppLocalizations(AppLocalizations.supportedLocales.first);
}

class WidgetManager {
  static final WidgetManager _instance = WidgetManager._internal();
  factory WidgetManager() => _instance;
  WidgetManager._internal();

  /// 渲染批次串行门:任意时刻只允许一个 [updateAllWidgets] 批次在跑。
  ///
  /// [_renderView] 在渲染窗口内全局接管 FlutterError.onError /
  /// ErrorWidget.builder,两个批次并发时交错的 finally 会把**对方批次的
  /// hook** 当"原值"恢复,主应用的错误处理从此永久指向渲染态。串行化后各
  /// 批次的接管窗口天然不重叠;顺带避免多批次同时离屏渲染的内存峰值。
  Future<void> _renderGate = Future.value();

  /// 渲染管线入口:按 [WidgetSpec] 目录逐个处理,只渲染用户"已安装"(已放置
  /// 到桌面)的组件,再统一触发原生刷新。
  ///
  /// 本函数不依赖 BuildContext/Riverpod `ref`,下面文案参数的默认值都只是
  /// 中文兜底——真正跟随 App 语言靠调用方显式传入:
  /// - 有 `BuildContext` 的调用点(`providers/widget_provider.dart`)直接用
  ///   `AppLocalizations.of(context)`。
  /// - 没有的调用点改用 [updateAllWidgetsLocalized],内部靠
  ///   [resolveWidgetLocalizations] 还原 `languageProvider` 对应的文案。
  Future<void> updateAllWidgets(
    BaseRepository repository,
    int ledgerId,
    Color themeColor, {
    bool redForIncome = true,
    String glanceTitleLabel = '收支速览',
    String monthSuffix = '月',
    String todayExpenseLabel = '今日支出',
    String todayIncomeLabel = '今日收入',
    String monthExpenseLabel = '本月支出',
    String monthIncomeLabel = '本月收入',
    // GlanceView.small 专用的"今日"徽章文案,对应 arb key `widgetToday`。
    String todayLabel = '今日',
    // 预热:true 时渲染整个 [WidgetSpec.catalog] 而非仅"已安装"(D5 的显式
    // 例外)。用于 App 启动 / 切账本这类低频时机,把组件图先备好——否则
    // 用户添加一个从未渲染过的组件类型时,共享存储里没有对应图片,原生壳
    // 只能显示占位,要等下一次 App 内触发渲染才有内容。
    bool warmUpAllSpecs = false,
  }) async {
    // GRAY 防御:标签参数缺省值为中文,若调用方未传本地化文案,debug 期告警,
    // 避免未来调用方漏传导致英文环境的小组件露出中文。
    assert(() {
      final isZh = PlatformDispatcher.instance.locale.languageCode.startsWith('zh');
      if (!isZh && glanceTitleLabel == '收支速览') {
        logger.warning(_tag, 'widget 标签使用了中文默认值:调用方未传本地化文案');
      }
      return true;
    }());
    // 排队进串行门(动机见 _renderGate 文档);gate 在 finally 里必然放行,
    // 前一批次即使异常也不会卡死队列。
    final prev = _renderGate;
    final gate = Completer<void>();
    _renderGate = gate.future;
    await prev;
    try {
      List<WidgetSpec> specs;
      if (warmUpAllSpecs) {
        // 预热渲全目录,但已安装的组件排前面先出图。
        specs = orderCatalogForWarmUp(await _resolveSpecsToRender());
      } else {
        specs = await _resolveSpecsToRender();
      }
      if (specs.isEmpty) {
        logger.debug(_tag, '没有已安装的桌面组件,跳过本次渲染');
        return;
      }

      final batch = WidgetGatherBatch(
        repository: repository,
        ledgerId: ledgerId,
      );

      // 图片渲染方案不会随系统明暗切换自动重绘(见 widget_view_style.dart
      // 顶部注释);这里在一次渲染批次开始时取一次当前系统明暗,批次内所有
      // spec 共用同一个值。
      final dark =
          PlatformDispatcher.instance.platformBrightness == Brightness.dark;

      for (final spec in specs) {
        try {
          await _renderGlance(
            spec,
            batch: batch,
            themeColor: themeColor,
            redForIncome: redForIncome,
            dark: dark,
            titleLabel: glanceTitleLabel,
            monthSuffix: monthSuffix,
            todayLabel: todayLabel,
            todayExpenseLabel: todayExpenseLabel,
            todayIncomeLabel: todayIncomeLabel,
            monthExpenseLabel: monthExpenseLabel,
            monthIncomeLabel: monthIncomeLabel,
          );
        } catch (e, st) {
          // 单个 spec 渲染失败不应阻断其余 spec。
          logger.error(_tag, '渲染 ${spec.imageKey} 失败,跳过', e, st);
        }
      }

      // 触发原生壳刷新:按已渲染 spec 去重出全部 iOS kind / Android provider
      // 类名逐个触发。无实例的 kind/provider 触发是无害 no-op。
      if (Platform.isIOS) {
        final kinds = <String>{
          for (final spec in specs)
            if (spec.iosKind != null) spec.iosKind!,
        };
        for (final kind in kinds) {
          await HomeWidget.updateWidget(iOSName: kind);
        }
      } else {
        final names = <String>{
          for (final spec in specs)
            if (spec.androidClassName != null) spec.androidClassName!,
        };
        for (final name in names) {
          await HomeWidget.updateWidget(qualifiedAndroidName: name);
        }
      }
      logger.info(
        _tag,
        '小组件更新完成,已渲染 ${specs.length} 个 spec: '
        '${specs.map((s) => s.imageKey).join(', ')}',
      );
    } catch (e, st) {
      logger.error(_tag, '更新小组件失败', e, st);
    } finally {
      gate.complete();
    }
  }

  /// [updateAllWidgets] 的语言感知封装,供没有 [BuildContext] 的调用点使用
  /// (`main.dart` 的 `_WidgetUpdateObserver`、`providers/theme_providers.dart`
  /// 的主题色/收支配色监听、`app.dart` 的前台恢复)——内部靠
  /// [resolveWidgetLocalizations] 把 [explicitLocale] 还原成
  /// [AppLocalizations],再填入对应的 glance 文案参数。
  Future<void> updateAllWidgetsLocalized(
    BaseRepository repository,
    int ledgerId,
    Color themeColor, {
    required Locale? explicitLocale,
    bool redForIncome = true,
    bool warmUpAllSpecs = false,
  }) {
    final l10n = resolveWidgetLocalizations(explicitLocale);
    return updateAllWidgets(
      repository,
      ledgerId,
      themeColor,
      redForIncome: redForIncome,
      warmUpAllSpecs: warmUpAllSpecs,
      glanceTitleLabel: l10n.widgetGalleryGlanceTitle,
      monthSuffix: l10n.widgetMonthSuffix,
      todayLabel: l10n.widgetToday,
      todayExpenseLabel: l10n.widgetTodayExpense,
      todayIncomeLabel: l10n.widgetTodayIncome,
      monthExpenseLabel: l10n.widgetMonthExpense,
      monthIncomeLabel: l10n.widgetMonthIncome,
    );
  }

  /// 获取平台"已安装组件"列表并映射为 spec;调用失败时返回按 `null` 触发
  /// 默认集的 [selectSpecsToRender] 结果。
  Future<List<WidgetSpec>> _resolveSpecsToRender() async {
    List<HomeWidgetInfo> infos;
    try {
      infos = await HomeWidget.getInstalledWidgets();
    } catch (e) {
      logger.warning(
        _tag,
        '获取已安装组件列表失败,退化为默认集(至少 glance-medium): $e',
      );
      return selectSpecsToRender(null);
    }
    return selectSpecsToRender(matchInstalledSpecs(infos));
  }

  /// 渲染收支速览(glance):小/中两档,均已接 [GlanceView] 真实视图。
  Future<void> _renderGlance(
    WidgetSpec spec, {
    required WidgetGatherBatch batch,
    required Color themeColor,
    required bool redForIncome,
    required bool dark,
    required String titleLabel,
    required String monthSuffix,
    required String todayLabel,
    required String todayExpenseLabel,
    required String todayIncomeLabel,
    required String monthExpenseLabel,
    required String monthIncomeLabel,
  }) async {
    final data = await batch.glance();

    // 金额符号跟随账本自身币种(v30 多币种后账本各有币种)。
    final currency = await batch.ledgerCurrency();
    String fmt(double v) =>
        '${getCurrencySymbol(currency)}${formatMoneyCompact(v)}';
    final todayExpense = fmt(data.todayExpenseTotal);
    final todayIncome = fmt(data.todayIncomeTotal);
    final monthExpense = fmt(data.monthExpenseTotal);
    final monthIncome = fmt(data.monthIncomeTotal);

    late final Widget view;
    late final Size renderSize;

    if (spec.size == HWSize.small) {
      // 小号两平台同一个方形尺寸,不需要 iOS/Android 分叉。
      renderSize = spec.logicalSize;
      view = GlanceView.small(
        todayExpense: todayExpense,
        monthExpense: monthExpense,
        monthIncome: monthIncome,
        themeColor: themeColor,
        redForIncome: redForIncome,
        dark: dark,
        todayLabel: todayLabel,
        todayExpenseLabel: todayExpenseLabel,
        monthExpenseLabel: monthExpenseLabel,
        monthIncomeLabel: monthIncomeLabel,
        width: renderSize.width,
        height: renderSize.height,
      );
    } else {
      // iOS systemMedium 与 Android 2:1 网格的宽高比不同,渲染尺寸沿用
      // 升级前的平台分叉逻辑,不直接使用 spec.logicalSize——避免改变现有
      // 原生壳对图片像素尺寸的假设,属 D2 back-compat 的一部分。
      renderSize = Platform.isIOS
          ? const Size(364, 169) // iOS systemMedium
          : const Size(364, 182); // Android 2:1 比例(364/2=182)
      view = GlanceView.medium(
        todayExpense: todayExpense,
        todayIncome: todayIncome,
        monthExpense: monthExpense,
        monthIncome: monthIncome,
        themeColor: themeColor,
        redForIncome: redForIncome,
        dark: dark,
        titleLabel: titleLabel,
        monthSuffix: monthSuffix,
        todayLabel: todayLabel,
        todayExpenseLabel: todayExpenseLabel,
        todayIncomeLabel: todayIncomeLabel,
        monthExpenseLabel: monthExpenseLabel,
        monthIncomeLabel: monthIncomeLabel,
        width: renderSize.width,
        height: renderSize.height,
      );
    }

    await _renderView(view,
        spec: spec,
        logicalSize: renderSize,
        themeColor: themeColor,
        dark: dark);
  }

  /// 统一的"渲染 + 落盘日志"收尾。
  ///
  /// **红屏防护(2026-07 真机问题)**:home_widget 的 `renderFlutterWidget`
  /// 用独立 BuildOwner 离屏渲染,视图 build 阶段抛异常不会向外传播为 Dart
  /// 异常,而是被 Flutter 替换成 `ErrorWidget`——debug 构建下就是「整卡红屏」
  /// 被原样渲进 PNG 显示在桌面上(release 下是灰卡),且真实异常堆栈被吞掉,
  /// 无从排查。这里在渲染窗口内临时接管两个全局 hook:
  ///
  /// 1. [FlutterError.onError]:把真实异常 + 堆栈写进日志中心(持久化 48h,
  ///    设置 → 日志中心可导出),这是定位真机红屏根因的关键线索;
  /// 2. [ErrorWidget.builder]:换成透明占位,防止红屏内容进图;渲染结束后若
  ///    确实捕获到异常,补渲一张干净的兜底卡(主题色刷新图标)覆盖落盘。
  ///
  /// 两个 hook 都是全局的,接管窗口仅限单次离屏渲染(毫秒级)并在 finally
  /// 恢复;主应用树恰好同时报错的概率极低,可接受。
  Future<void> _renderView(
    Widget view, {
    required WidgetSpec spec,
    required Size logicalSize,
    required Color themeColor,
    required bool dark,
  }) async {
    logger.debug(
      _tag,
      '渲染 ${spec.imageKey} - Platform: ${Platform.isIOS ? "iOS" : "Android"}, '
      'Size: ${logicalSize.width}x${logicalSize.height}',
    );

    final prevOnError = FlutterError.onError;
    final prevErrorBuilder = ErrorWidget.builder;
    Object? captured;
    FlutterError.onError = (details) {
      captured ??= details.exception;
      logger.error(_tag, '渲染 ${spec.imageKey} 视图内部异常(将改渲兜底卡)',
          details.exception, details.stack);
    };
    ErrorWidget.builder = (details) => const SizedBox.shrink();
    try {
      await HomeWidget.renderFlutterWidget(
        view,
        // spec.imageKey 对 glance-medium 特判为 'widgetImage'(D2 back-compat,
        // 详见 WidgetSpec.imageKey 注释)。
        key: spec.imageKey,
        logicalSize: logicalSize,
        // 由 4.0 降为 3.0:更省内存。
        pixelRatio: 3.0,
      );
    } finally {
      FlutterError.onError = prevOnError;
      ErrorWidget.builder = prevErrorBuilder;
    }

    if (captured != null) {
      // 首次渲染已把(残缺的)图落盘,这里补渲一张干净的兜底卡覆盖——组件上
      // 显示"主题色刷新图标卡"而非红屏/空白;真实根因见上面的 error 日志。
      await HomeWidget.renderFlutterWidget(
        _WidgetRenderFallbackCard(
          themeColor: themeColor,
          dark: dark,
          width: logicalSize.width,
          height: logicalSize.height,
        ),
        key: spec.imageKey,
        logicalSize: logicalSize,
        pixelRatio: 3.0,
      );
      logger.warning(_tag, '${spec.imageKey} 渲染出错,已用兜底卡覆盖(根因见上条 error 日志)');
      return;
    }

    final savedPath = await HomeWidget.getWidgetData<String>(spec.imageKey);
    logger.debug(_tag, '${spec.imageKey} 渲染完成,保存路径: $savedPath');
  }

  /// Register widget update callback
  static Future<void> registerCallback() async {
    try {
      await HomeWidget.registerInteractivityCallback(
        _backgroundCallback,
      );
    } catch (e) {
      logger.warning(_tag, '注册小组件交互回调失败: $e');
      return;
    }
  }

  /// Background callback for widget interactions
  @pragma('vm:entry-point')
  static Future<void> _backgroundCallback(Uri? uri) async {
    // 图片方案下点击目前靠深链跳转(services/platform/app_link_service.dart),
    // 真正的交互入口是各原生壳拼的 beecount:// 深链,不经过这里。这个回调
    // 只是 `home_widget` 交互式组件 API 的注册要求,当前阶段先落一条日志
    // 占位,预留给未来"组件内即时记账"。
    //
    // 可能在纯后台 isolate 中触发(`@pragma('vm:entry-point')`),`logger`
    // 依赖的插件通道不一定已就绪,这里包一层 try/catch 保证回调本身绝不
    // 因日志失败而抛异常。
    try {
      logger.debug(_tag, '收到小组件交互回调: uri=$uri');
    } catch (_) {
      // 静默忽略,见上方注释。
    }
  }
}

/// 视图渲染出错时的兜底卡(见 [WidgetManager._renderView] 红屏防护注释):
/// 与正常卡片同底色圆角,中央一个主题色刷新图标——语言无关(纯图标,不需要
/// 文案 i18n),点击组件仍走原生壳深链打开 App,打开后下一次渲染自动重试。
class _WidgetRenderFallbackCard extends StatelessWidget {
  final Color themeColor;
  final bool dark;
  final double width;
  final double height;

  const _WidgetRenderFallbackCard({
    required this.themeColor,
    required this.dark,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1712) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(Icons.refresh, size: 28, color: themeColor),
    );
  }
}
