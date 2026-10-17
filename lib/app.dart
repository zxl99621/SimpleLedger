import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/main/simple_home_page.dart';
import 'pages/main/simple_stats_page.dart';
import 'pages/transaction/transaction_editor_page.dart';
import 'providers.dart';
import 'theme.dart';
import 'l10n/app_localizations.dart';
import 'widget/widget_manager.dart';
import 'widgets/ui/ui.dart';
import 'widgets/ui/speed_dial_fab.dart';
import 'utils/image_billing_helper.dart';
import 'pages/ai/simple_ai_page.dart';
import 'pages/settings/simple_settings_page.dart';
import 'services/platform/app_link_service.dart';
import 'services/platform/quick_actions_service.dart';
import 'services/system/logger_service.dart';
import 'services/security/app_lock_service.dart';
import 'providers/security_providers.dart';
import 'styles/tokens.dart';
import 'styles/header_skins.dart';

class BeeApp extends ConsumerStatefulWidget {
  const BeeApp({super.key});

  @override
  ConsumerState<BeeApp> createState() => _BeeAppState();
}

class _BeeAppState extends ConsumerState<BeeApp>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _pages = const [
    SimpleHomePage(),
    SimpleStatsPage(),
    SimpleAiPage(),
    SimpleSettingsPage(),
  ];

  // 双击检测：记录最后一次点击的时间和索引
  DateTime? _lastTapTime;
  int? _lastTappedIndex;

  // 双击返回退出：记录最后一次返回键按下时间
  DateTime? _lastBackPressTime;

  // AppLink 监听订阅
  ProviderSubscription<AppLinkAction?>? _appLinkSubscription;

  // 快捷操作服务
  final QuickActionsService _quickActionsService = QuickActionsService();

  // 防止 AppLink 动作重复执行（使用静态变量，跨实例共享）
  static bool _isHandlingAppLink = false;
  static DateTime? _lastAppLinkHandleTime;

  // 记账按钮相关状态
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  int? _hoveredIndex;
  OverlayEntry? _overlayEntry;
  final GlobalKey _centerButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 初始化记账按钮动画控制器
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut,
    );

    // 延迟监听 AppLink，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAppLinkListener();
      _setupQuickActions();
      // 首帧后主动预热小组件：首次启动时 currentLedgerIdProvider 可能没有发生
      // “变化”，ProviderObserver 不会触发，导致用户添加组件时还没有渲染图、
      // 只能先显示占位图，等下一次前台恢复才刷新。
      _updateWidget(warmUpAll: true);
    });
  }

  /// 设置快捷操作
  void _setupQuickActions() {
    logger.info('QuickActions', 'BeeApp: 设置快捷操作服务...');
    _quickActionsService.onNavigate = (action) {
      if (mounted) {
        logger.info('QuickActions', 'BeeApp: 执行快捷操作 $action');
        _handleAppLinkAction(action);
      }
    };
    _quickActionsService.initialize();
    // 处理可能在初始化前就触发的快捷操作
    _quickActionsService.processPendingAction();
    logger.info('QuickActions', 'BeeApp: 快捷操作服务已设置');
  }

  /// 设置 AppLink 监听
  void _setupAppLinkListener() {
    logger.info('AppLink', 'BeeApp: 设置 AppLink 监听...');
    _appLinkSubscription = ref.listenManual<AppLinkAction?>(
      pendingAppLinkActionProvider,
      (previous, next) {
        logger.info('AppLink',
            'BeeApp: 监听触发 previous=$previous, next=$next, mounted=$mounted');
        if (next != null && mounted) {
          // 不在此处直接 push：冷启动 / 厂商主题变更(themeChanged)会重建页面树,
          // 此刻多半处于 inactive/hidden,push 的路由会被丢弃(deep-link「没打开」根因)。
          // 改为持久化待处理深链,等 ready + 前台 resumed 后在最终页面树上认领打开。
          _persistPendingDeepLink(
            next,
            ref.read(pendingNewTransactionTypeProvider),
            categoryId: ref.read(pendingNewTransactionCategoryIdProvider),
            page: ref.read(pendingOpenPageProvider),
          );
          ref.read(pendingAppLinkActionProvider.notifier).state = null;
          _drainPendingDeepLink(trigger: 'listener');
        }
      },
      fireImmediately: true,
    );
    logger.info('AppLink', 'BeeApp: AppLink 监听已设置');
  }

  /// 处理「桌面长按图标快捷项」的动作:立即执行,带 1s 防抖去重。
  /// (URL deep-link / 桌面小组件走 _persistPendingDeepLink → _drainPendingDeepLink
  ///  的「重建可恢复」路径;两条路径最终都汇到 [_openDeepLink] 统一派发。)
  void _handleAppLinkAction(AppLinkAction action) {
    // 防止重复执行（使用时间戳和标志双重检查）
    final now = DateTime.now();
    if (_isHandlingAppLink ||
        (_lastAppLinkHandleTime != null &&
            now.difference(_lastAppLinkHandleTime!) <
                const Duration(seconds: 1))) {
      logger.info('AppLink', 'BeeApp: 忽略重复的动作 $action');
      return;
    }
    _isHandlingAppLink = true;
    _lastAppLinkHandleTime = now;

    // 延迟重置标志，允许下一次动作
    Future.delayed(const Duration(seconds: 1), () {
      _isHandlingAppLink = false;
    });

    String? type;
    int? categoryId;
    String? page;
    if (action == AppLinkAction.newTransaction) {
      type = ref.read(pendingNewTransactionTypeProvider) ?? 'expense';
      categoryId = ref.read(pendingNewTransactionCategoryIdProvider);
      ref.read(pendingNewTransactionTypeProvider.notifier).state = null;
      ref.read(pendingNewTransactionCategoryIdProvider.notifier).state = null;
    } else if (action == AppLinkAction.open) {
      page = ref.read(pendingOpenPageProvider);
      ref.read(pendingOpenPageProvider.notifier).state = null;
    }
    _openDeepLink(action, type, categoryId: categoryId, page: page);
  }

  // ——— 深链「重建可恢复」打开 ———
  // 背景:部分厂商(如 ColorOS)在浏览器→App 拉起 deep-link 时会触发主题变更
  // (onConfigurationChanged: themeChanged),导致页面树/Activity 重建;若在重建前就
  // push,路由会被丢弃,用户看到「没打开」。做法:把待打开的深链持久化(跨重建/重置
  // 存活),等 appInitState==ready 且生命周期 resumed(前台稳定)后,在最终页面树上认领
  // 打开,认领即清除并去重,确保只打开一次。
  static const String _kPendingDeepLink = 'pending_deeplink_action';
  int? _lastDrainedDeepLinkTs;
  Timer? _drainTimer;

  void _persistPendingDeepLink(
    AppLinkAction action,
    String? type, {
    int? categoryId,
    String? page,
  }) {
    SharedPreferences.getInstance().then((p) {
      p.setString(_kPendingDeepLink, jsonEncode({
        'action': action.name,
        'type': type,
        if (categoryId != null) 'categoryId': categoryId,
        if (page != null) 'page': page,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
    }).catchError((_) {});
  }

  void _drainPendingDeepLink({String trigger = ''}) {
    if (!mounted) return;
    if (ref.read(appInitStateProvider) != AppInitState.ready) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    // 重建有时在 resumed 之后还会再发生一次:延迟一拍再认领,只在「存活过这段缓冲期」的
    // 最终页面树上打开。若本页在缓冲期内被销毁(重建),timer 随 dispose 取消,新页面会
    // 重新排程,自然落到稳定的页面树上。
    _drainTimer?.cancel();
    _drainTimer =
        Timer(const Duration(milliseconds: 700), () => _executeDrain(trigger));
  }

  Future<void> _executeDrain(String trigger) async {
    if (!mounted) return;
    // 必须就绪 + 前台稳定:冷启动/主题变更的重建窗口(inactive/hidden)里打开会被丢弃
    if (ref.read(appInitStateProvider) != AppInitState.ready) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final raw = prefs.getString(_kPendingDeepLink);
    if (raw == null) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await prefs.remove(_kPendingDeepLink);
      return;
    }
    final ts = (data['ts'] as num?)?.toInt() ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
    // 过期(>20s)或时间异常 → 丢弃,避免历史深链在普通启动时误触发
    if (ageMs < 0 || ageMs > 20000) {
      await prefs.remove(_kPendingDeepLink);
      return;
    }
    // 同一条只认领一次(listener / resumed 多次触发去重)
    if (_lastDrainedDeepLinkTs == ts) return;

    AppLinkAction? action;
    final actionName = data['action'] as String?;
    for (final a in AppLinkAction.values) {
      if (a.name == actionName) {
        action = a;
        break;
      }
    }
    if (action == null) {
      await prefs.remove(_kPendingDeepLink);
      return;
    }

    // 认领成功:打标 + 清持久化,再打开(用根 Navigator,落在最终稳定的页面树上)
    _lastDrainedDeepLinkTs = ts;
    await prefs.remove(_kPendingDeepLink);
    if (!mounted) return;
    final type = data['type'] as String?;
    final categoryId = (data['categoryId'] as num?)?.toInt();
    final page = data['page'] as String?;
    logger.info('AppLink',
        'BeeApp: drain($trigger) 打开深链 $action type=$type categoryId=$categoryId page=$page');
    _openDeepLink(action, type, categoryId: categoryId, page: page);
  }

  /// AppLink 动作的唯一派发出口:快捷项([_handleAppLinkAction])与
  /// URL deep-link / 小组件([_executeDrain])两条路径共用,避免分叉。
  ///
  /// [categoryId] 仅 [AppLinkAction.newTransaction] 使用(小组件「快速记账」
  /// 预填分类);[page] 仅 [AppLinkAction.open] 使用(小组件「净资产/预算/
  /// 最近交易」卡片点击落地页,见 [_openPageForDeepLink])。
  void _openDeepLink(
    AppLinkAction action,
    String? type, {
    int? categoryId,
    String? page,
  }) {
    final nav = Navigator.of(context, rootNavigator: true);
    switch (action) {
      case AppLinkAction.voice:
        // 语音记账已在 SimpleLedger 中移除，忽略历史深链。
        break;
      case AppLinkAction.image:
        ImageBillingHelper.pickImageForBilling(context, ref);
        break;
      case AppLinkAction.camera:
        ImageBillingHelper.openCameraForBilling(context, ref);
        break;
      case AppLinkAction.aiChat:
        nav.push(MaterialPageRoute(builder: (_) => const SimpleAiPage()));
        break;
      case AppLinkAction.newTransaction:
        // 小组件「快速记账」点分类格携带 categoryId 时,预填该分类(见
        // TransactionEditorPage.initialCategoryId);普通「记一笔」categoryId 为 null。
        nav.push(MaterialPageRoute(
          builder: (_) => TransactionEditorPage(
            initialKind: type ?? 'expense',
            quickAdd: true,
            initialCategoryId: categoryId,
          ),
        ));
        break;
      case AppLinkAction.open:
        _openPageForDeepLink(nav, page);
        break;
      default:
        break;
    }
  }

  /// 小组件「净资产 / 预算 / 最近交易」卡片点击 → `beecount://open?page=` 的
  /// 落地页路由。detail(最近交易)先落统计页,后续可按需换成专门的明细列表页。
  void _openPageForDeepLink(NavigatorState nav, String? page) {
    switch (page) {
      case 'detail':
        // 最近交易 / 仪表盘主体 → 首页明细列表:App 没有独立的明细页,首页
        // 就是完整账单流,切回主壳首页 tab 而不是 push 页面。(此前误映射到
        // 洞察/统计页,真机反馈"点小组件进了洞察页"。)
        nav.popUntil((route) => route.isFirst);
        ref.read(bottomTabIndexProvider.notifier).state = 0;
        break;
      default:
        logger.warning('AppLink', 'open 未知 page: $page');
        break;
    }
  }

  @override
  void dispose() {
    _drainTimer?.cancel();
    _appLinkSubscription?.close();
    _removeOverlay();
    _expandController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _expandController.forward();
    _showOverlay();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _updateHoveredIndex(details.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final centerActions = [
      SpeedDialAction(
        icon: Icons.camera_alt_rounded,
        label: AppLocalizations.of(context).fabActionCamera,
        onTap: () => ImageBillingHelper.openCameraForBilling(context, ref),
      ),
      SpeedDialAction(
        icon: Icons.photo_library_rounded,
        label: AppLocalizations.of(context).fabActionGallery,
        onTap: () => ImageBillingHelper.pickImageForBilling(context, ref),
      ),
    ];

    if (_hoveredIndex != null && _hoveredIndex! < centerActions.length) {
      final action = centerActions[_hoveredIndex!];
      if (action.enabled && action.onTap != null) {
        action.onTap!();
      }
    }

    _dismissOverlay();
  }

  void _dismissOverlay() {
    _hoveredIndex = null;
    _expandController.reverse();
    _removeOverlay();
  }

  void _showOverlay() {
    final RenderBox? renderBox =
        _centerButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _SpeedDialOverlay(
        buttonPosition: position,
        buttonSize: size,
        actions: [
          SpeedDialAction(
            icon: Icons.camera_alt_rounded,
            label: AppLocalizations.of(context).fabActionCamera,
            onTap: () => ImageBillingHelper.openCameraForBilling(context, ref),
          ),
          SpeedDialAction(
            icon: Icons.photo_library_rounded,
            label: AppLocalizations.of(context).fabActionGallery,
            onTap: () => ImageBillingHelper.pickImageForBilling(context, ref),
          ),
        ],
        animation: _expandAnimation,
        hoveredIndex: _hoveredIndex,
        backgroundColor: ref.read(primaryColorProvider),
        onDismiss: _dismissOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateHoveredIndex(Offset globalPosition) {
    final RenderBox? renderBox =
        _centerButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;
    final buttonCenter = Offset(
      buttonPosition.dx + buttonSize.width / 2,
      buttonPosition.dy + buttonSize.height / 2,
    );

    final angles = [225.0, 315.0];
    const distance = 85.0;
    const buttonRadius = 26.0;

    int? newHoveredIndex;
    for (int i = 0; i < angles.length; i++) {
      final angle = angles[i];
      final radians = angle * math.pi / 180;
      final offsetX = distance * math.cos(radians);
      final offsetY = distance * math.sin(radians);

      final actionCenter = Offset(
        buttonCenter.dx + offsetX,
        buttonCenter.dy + offsetY,
      );

      final distanceToButton = (globalPosition - actionCenter).distance;

      if (distanceToButton <= buttonRadius) {
        newHoveredIndex = i;
        break;
      }
    }

    if (newHoveredIndex != _hoveredIndex) {
      setState(() {
        _hoveredIndex = newHoveredIndex;
      });
      _overlayEntry?.markNeedsBuild();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive) {
      // 多任务切换时显示隐私模糊屏（仅在应用锁启用时）
      if (ref.read(appLockEnabledProvider)) {
        ref.read(showPrivacyScreenProvider.notifier).state = true;
      }
    } else if (state == AppLifecycleState.paused) {
      // 系统拖拽/侧边栏弹出时，强制关闭扇形菜单
      _dismissOverlay();
      // 记录进入后台时间
      AppLockService.recordBackgroundTime();
    } else if (state == AppLifecycleState.resumed) {
      // 移除隐私模糊屏
      ref.read(showPrivacyScreenProvider.notifier).state = false;
      // 检查是否需要锁定
      _checkAppLockOnResume();
      // 当app从后台恢复到前台时，更新小组件数据
      _updateWidget();
      // 前台稳定后认领待处理深链(冷启动/主题变更重建后,在最终页面树上打开)
      _drainPendingDeepLink(trigger: 'resumed');
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // 系统明暗切换时重渲小组件:图片渲染方案不会随系统主题自动重绘(原生壳
    // 只是展示一张静态 PNG),渲染时机全靠 App 侧触发。小组件明暗跟随**系统**
    // 而非 App 内主题设置(行业惯例,桌面是系统的地盘;widget_manager 渲染
    // 批次内取 PlatformDispatcher.platformBrightness),这里监听的正是系统
    // 明暗变化——App 在前台/存活时系统切换明暗,桌面组件立刻换肤,而不是
    // 等下一次记账/前台恢复才刷新。
    _updateWidget();
  }

  Future<void> _checkAppLockOnResume() async {
    final shouldLock = await AppLockService.shouldLockOnResume();
    if (shouldLock && mounted) {
      ref.read(isAppLockedProvider.notifier).state = true;
    }
  }

  Future<void> _updateWidget({bool warmUpAll = false}) async {
    try {
      final repository = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final primaryColor = ref.read(primaryColorProvider);
      final redForIncome = ref.read(incomeExpenseColorSchemeProvider);
      final baseCurrency = ref.read(baseCurrencyProvider);

      final widgetManager = WidgetManager();
      // 前台恢复路径也走本地化封装,让小组件文案跟随 App 语言(与
      // main.dart / theme_providers 等无 context 调用点一致,靠 languageProvider
      // 还原 locale,不依赖 async 后可能失效的 BuildContext)。
      await widgetManager.updateAllWidgetsLocalized(
        repository,
        ledgerId,
        primaryColor,
        explicitLocale: ref.read(languageProvider),
        redForIncome: redForIncome,
        baseCurrency: baseCurrency,
        warmUpAllSpecs: warmUpAll,
      );
      logger.info(
        'App',
        warmUpAll ? '启动时小组件目录已预热' : 'App恢复前台，小组件数据已更新',
      );
    } catch (e) {
      logger.warning('App', '更新小组件失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(bottomTabIndexProvider);
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // 头部皮肤可附带悬浮 tab 装饰层(如一周年皮肤),随皮肤选择联动。
    final headerSkin = headerSkinById(ref.watch(headerSkinProvider));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;

        final now = DateTime.now();

        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          showToast(context, l10n.commonPressAgainToExit);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            extendBody: true, // 让页面内容延伸到底部栏后面
            // IndexedStack 靠 Offstage 藏起非当前页,而 **Offstage 不会停
            // Ticker** —— 五个页面的 header 皮肤会同时满帧跑,在 ProMotion
            // 机型上就是 5×120fps 的持续重绘,机器明显发烫。
            //
            // TickerMode 关掉后,非当前页的 AnimationController 被 mute(仍
            // isAnimating,只是不再 tick),切回来自动恢复。动态皮肤是最先
            // 暴露这个问题的,但收益覆盖所有页内动画。
            body: IndexedStack(
              index: idx,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  TickerMode(enabled: i == idx, child: _pages[i]),
              ],
            ),
            bottomNavigationBar: _BeeBottomBar(
              currentIndex: idx,
              primaryColor: primaryColor,
              isDark: isDark,
              bottomPadding: bottomPadding,
              l10n: l10n,
              skin: headerSkin,
              centerButtonKey: _centerButtonKey,
              onTabTap: (index) {
                final now = DateTime.now();
                if (_lastTappedIndex == index &&
                    _lastTapTime != null &&
                    now.difference(_lastTapTime!) <
                        const Duration(milliseconds: 300)) {
                  if (index == 0) {
                    ref.read(homeScrollToTopProvider.notifier).state++;
                  }
                  _lastTapTime = null;
                  _lastTappedIndex = null;
                } else {
                  _lastTapTime = now;
                  _lastTappedIndex = index;
                  ref.read(bottomTabIndexProvider.notifier).state = index;
                }
              },
              onCenterTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TransactionEditorPage(
                      initialKind: 'expense',
                      quickAdd: true,
                    ),
                  ),
                );
              },
              onCenterLongPressStart: _onLongPressStart,
              onCenterLongPressMoveUpdate: _onLongPressMoveUpdate,
              onCenterLongPressEnd: _onLongPressEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram 风格悬浮胶囊底部导航栏
class _BeeBottomBar extends StatelessWidget {
  final int currentIndex;
  final Color primaryColor;
  final bool isDark;
  final double bottomPadding;
  final AppLocalizations l10n;
  final HeaderSkin? skin;
  final GlobalKey centerButtonKey;
  final ValueChanged<int> onTabTap;
  final VoidCallback onCenterTap;
  final GestureLongPressStartCallback onCenterLongPressStart;
  final GestureLongPressMoveUpdateCallback onCenterLongPressMoveUpdate;
  final GestureLongPressEndCallback onCenterLongPressEnd;

  const _BeeBottomBar({
    required this.currentIndex,
    required this.primaryColor,
    required this.isDark,
    required this.bottomPadding,
    required this.l10n,
    this.skin,
    required this.centerButtonKey,
    required this.onTabTap,
    required this.onCenterTap,
    required this.onCenterLongPressStart,
    required this.onCenterLongPressMoveUpdate,
    required this.onCenterLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = BeeTokens.tabBarBackground(context);
    final inactiveColor = isDark ? Colors.white70 : Colors.black54;

    const barHeight = 56.0;

    return SizedBox(
      height: barHeight + bottomPadding + 12, // 12dp 浮动间距
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomPadding + 12,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: BeeTokens.tabBarShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                // 皮肤的悬浮 tab 装饰层(垫在图标之下,不影响点按)
                if (skin?.tabBarBuilder != null)
                  Positioned.fill(
                      child: IgnorePointer(
                          child: SkinAnimationScope(
                              child: skin!.tabBarBuilder!(
                                  primaryColor, isDark)))),
                Row(
                  children: [
                    _buildTabItem(0, Icons.receipt_long_outlined,
                        Icons.receipt_long, '首页', inactiveColor),
                    _buildTabItem(1, Icons.pie_chart_outline_rounded,
                        Icons.pie_chart_rounded, '统计', inactiveColor),
                    // 中间记账按钮（作为 Tab 样式）
                    _buildCenterTabItem(inactiveColor),
                    _buildTabItem(2, Icons.auto_awesome_outlined,
                        Icons.auto_awesome, 'AI', inactiveColor),
                    _buildTabItem(3, Icons.settings_outlined, Icons.settings,
                        '设置', inactiveColor),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color get _activeTabColor => isDark ? BeeTheme.tealDark : primaryColor;

  Widget _buildTabItem(
      int index, IconData icon, IconData activeIcon, String label, Color inactiveColor,
      {String? dotAnchor}) {
    final isActive = index == currentIndex;
    final activeColor = _activeTabColor;
    final iconColor = isActive ? activeColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTabTap(index),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: isDark ? 0.18 : 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 新功能红点挂在图标上(不是整个 tab),这样位置跟着图标走、
                // 不会因为 label 长短漂移
                dotAnchor == null
                    ? Icon(isActive ? activeIcon : icon,
                        color: iconColor, size: 22)
                    : FeatureDot(
                        anchor: dotAnchor,
                        offset: const Offset(-2, 0),
                        child: Icon(isActive ? activeIcon : icon,
                            color: iconColor, size: 22),
                      ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? activeColor : inactiveColor,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterTabItem(Color inactiveColor) {
    return Expanded(
      child: GestureDetector(
        key: centerButtonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onCenterTap,
        onLongPressStart: onCenterLongPressStart,
        onLongPressMoveUpdate: onCenterLongPressMoveUpdate,
        onLongPressEnd: onCenterLongPressEnd,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, color: inactiveColor, size: 22),
              const SizedBox(height: 1),
              Text(
                l10n.tabRecord,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 10,
                  color: inactiveColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// 扇形菜单覆盖层
class _SpeedDialOverlay extends StatelessWidget {
  final Offset buttonPosition;
  final Size buttonSize;
  final List<SpeedDialAction> actions;
  final Animation<double> animation;
  final int? hoveredIndex;
  final Color backgroundColor;
  final VoidCallback? onDismiss;

  const _SpeedDialOverlay({
    required this.buttonPosition,
    required this.buttonSize,
    required this.actions,
    required this.animation,
    required this.hoveredIndex,
    required this.backgroundColor,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final buttonCenter = Offset(
      buttonPosition.dx + buttonSize.width / 2,
      buttonPosition.dy + buttonSize.height / 2,
    );

    final angles = [225.0, 315.0];
    const distance = 85.0;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (animation.value == 0) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onDismiss,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3 * animation.value),
                ),
              ),
            ),
            for (int i = 0; i < actions.length && i < angles.length; i++)
              Builder(builder: (context) {
                final angle = angles[i];
                final radians = angle * math.pi / 180;
                final progress = animation.value;
                final offsetX = progress * distance * math.cos(radians);
                final offsetY = progress * distance * math.sin(radians);

                const btnSize = 48.0;
                final left = buttonCenter.dx + offsetX - btnSize / 2;
                final top = buttonCenter.dy + offsetY - btnSize / 2;

                final isEnabled = actions[i].enabled;
                final bgColor =
                    isEnabled ? backgroundColor : Colors.grey.shade400;
                final isHovered = i == hoveredIndex;

                return Positioned(
                  left: left,
                  top: top,
                  child: Transform.scale(
                    scale: progress,
                    child: Opacity(
                      opacity: progress,
                      child: AnimatedScale(
                        scale: isHovered ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Material(
                          color: bgColor,
                          shape: const CircleBorder(),
                          elevation: isHovered ? 8 : 4,
                          child: Container(
                            width: btnSize,
                            height: btnSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: isHovered
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                            ),
                            child: Icon(
                              actions[i].icon,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

