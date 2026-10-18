import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../ai/simple/ai_engine.dart';
import '../../ai/simple/ai_providers.dart';
import '../../ai/simple/ai_service.dart';
import '../../ai/simple/ai_settings.dart';
import '../../ai/simple/ai_text_utils.dart';
import '../../ai/simple/local_ai_engine.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../theme.dart';
import '../../widgets/ui/keyboard_layout_scope.dart';
import '../main/simple_stats_page.dart';
import 'ai_message_list.dart';
import 'bill_confirm_bar.dart';
import 'simple_ai_settings_page.dart';

class SimpleAiPage extends ConsumerStatefulWidget {
  const SimpleAiPage({super.key});

  @override
  ConsumerState<SimpleAiPage> createState() => _SimpleAiPageState();
}

class _SimpleAiPageState extends ConsumerState<SimpleAiPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<AiChatItem> _messages = [];
  bool _busy = false;
  bool _guideShown = false;

  /// 每次请求的序号；用户点“停止”或发起新请求后，旧请求的结果不再写回界面。
  int _requestSerial = 0;

  /// AI 解析出的待确认账单；非 null 时在输入框上方显示确认条。
  PendingBill? _pendingBill;

  int? _lastLoadPercent;

  bool _tabVisible = false;

  void _handlePendingFeature() {
    final pending = ref.read(aiPendingFeatureProvider);
    if (pending == null) return;
    ref.read(aiPendingFeatureProvider.notifier).state = null;
    if (!ref.read(aiReadyProvider)) {
      _openSettings();
      return;
    }
    _runFeature(pending);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 页面常驻 IndexedStack；只在“从不可见变为可见”时触发首次引导/待处理功能，
    // 避免每次 build 都注册 post-frame 回调。
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_tabVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _maybeShowGuide();
        if (mounted) _handlePendingFeature();
      });
    }
    _tabVisible = visible;
  }

  @override
  void initState() {
    super.initState();
    LocalAiManager.instance.status.addListener(_onLocalStatus);
  }

  @override
  void dispose() {
    LocalAiManager.instance.status.removeListener(_onLocalStatus);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 本地模型首次加载时把百分比写进当前助手气泡，避免“正在思考…”长时间无反馈。
  void _onLocalStatus() {
    if (!mounted || ref.read(aiModeProvider) != AiMode.local) return;
    final status = LocalAiManager.instance.status.value;
    if (!status.isLoading || _messages.isEmpty) return;
    final percent = (status.progress * 100).round();
    if (percent == _lastLoadPercent) return;
    _lastLoadPercent = percent;
    final last = _messages.last;
    if (last.fromUser) return;
    setState(() => last.text = '首次加载模型 $percent%…');
  }

  Future<void> _maybeShowGuide() async {
    if (!mounted || _guideShown) return;
    if (ref.read(aiFirstUseDoneProvider)) return;
    _guideShown = true;

    final selected = await showModalBottomSheet<AiMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => const _FirstUseGuide(),
    );
    if (selected == null || !mounted) return;

    ref.read(aiModeProvider.notifier).state = selected;
    ref.read(aiFirstUseDoneProvider.notifier).state = true;
    if (!ref.read(aiReadyProvider)) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SimpleAiSettingsPage()),
      );
      if (mounted) setState(() {});
    }
  }

  Future<AiLedgerSnapshot> _buildSnapshot({bool wideRange = false}) async {
    final now = DateTime.now();
    final start = wideRange
        ? now.subtract(const Duration(days: 90))
        : DateTime(now.year, now.month, 1);
    final range = (start: start, end: now.add(const Duration(days: 1)));
    final stats = await ref.read(simpleStatsProvider(range).future);
    final label = wideRange
        ? '最近 90 天'
        : '${now.year}年${now.month}月';
    return buildSnapshot(
      rangeLabel: label,
      income: stats.current.$1,
      expense: stats.current.$2,
      previousIncome: stats.previous.$1,
      previousExpense: stats.previous.$2,
      lastYearIncome: stats.lastYear.$1,
      lastYearExpense: stats.lastYear.$2,
      categories: [
        for (final item in stats.categories) (name: item.name, total: item.total),
      ],
      transactions: stats.transactions,
      allCategories: stats.allCategories,
    );
  }

  /// 消费流式输出，逐段更新同一条助手气泡。
  Future<void> _runStreaming(
    Future<Stream<String>> Function(bool Function() isActive) open,
  ) async {
    if (_busy) return;
    final serial = ++_requestSerial;
    _lastLoadPercent = null;
    final item = AiChatItem(fromUser: false, text: '正在思考…');
    setState(() {
      _busy = true;
      _messages.add(item);
    });
    _scrollToBottom();

    final buffer = StringBuffer();
    var lastUpdate = DateTime.now();
    try {
      final stream = await open(() => mounted && serial == _requestSerial);
      await for (final chunk in stream) {
        if (!mounted || serial != _requestSerial) break;
        buffer.write(chunk);
        // 每 60ms 最多刷新一次，避免每个 token 重建整页。
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 60) {
          lastUpdate = now;
          setState(() => item.text = sanitizeAiStreamText(buffer.toString()));
          _scrollToBottom();
        }
      }
      if (!mounted || serial != _requestSerial) return;
      final text = sanitizeAiStreamText(buffer.toString());
      setState(() => item.text = text.isEmpty ? '（AI 没有返回内容）' : text);
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      final partial = sanitizeAiStreamText(buffer.toString());
      setState(() {
        if (partial.isEmpty) {
          item.text = error is AiCancelled
              ? '已停止'
              : error is AiException
                  ? error.message
                  : '出错了：$error';
        } else {
          item.text =
              '$partial\n\n${error is AiCancelled ? '（已停止）' : '（生成中断）'}';
        }
      });
    } finally {
      if (mounted && serial == _requestSerial) {
        setState(() => _busy = false);
      }
      _scrollToBottom();
    }
  }

  Future<void> _sendQuestion() async {
    final question = _inputController.text.trim();
    if (question.isEmpty || _busy) return;
    if (!ref.read(aiReadyProvider)) {
      _openSettings();
      return;
    }
    _inputController.clear();
    if (looksLikeBillIntent(question)) {
      await _parseBillCommand(question);
      return;
    }
    _pendingBill = null;
    setState(() =>
        _messages.add(AiChatItem(fromUser: true, text: question)));

    await _runStreaming((isActive) async {
      final snapshot = await _buildSnapshot(wideRange: true);
      if (!isActive()) throw const AiCancelled();
      return ref.read(aiServiceProvider).answerStream(question, snapshot);
    });
  }

  Future<void> _runFeature(String kind) async {
    if (_busy) return;
    if (!ref.read(aiReadyProvider)) {
      _openSettings();
      return;
    }
    switch (kind) {
      case 'summary':
        setState(() => _messages
            .add(AiChatItem(fromUser: true, text: '帮我总结本月消费')));
        await _runStreaming((isActive) async {
          final snapshot = await _buildSnapshot();
          if (!isActive()) throw const AiCancelled();
          return ref.read(aiServiceProvider).monthlySummaryStream(snapshot);
        });
        break;
      case 'insight':
        setState(() => _messages
            .add(AiChatItem(fromUser: true, text: '看看我的消费习惯')));
        await _runStreaming((isActive) async {
          final snapshot = await _buildSnapshot();
          if (!isActive()) throw const AiCancelled();
          return ref.read(aiServiceProvider).spendingInsightStream(snapshot);
        });
        break;
    }
  }

  /// 把一句话记账输入交给 parseBill，解析成功后显示确认条。
  Future<void> _parseBillCommand(String text) async {
    final serial = ++_requestSerial;
    _lastLoadPercent = null;
    setState(() {
      _pendingBill = null;
      _messages.add(AiChatItem(fromUser: true, text: text));
      _messages.add(AiChatItem(fromUser: false, text: '正在解析账单…'));
      _busy = true;
    });
    _scrollToBottom();
    final placeholder = _messages.last;

    try {
      final categories = await ref.read(categoriesProvider.future);
      final usable = categories
          .where((c) => c.kind == 'expense' || c.kind == 'income')
          .toList();
      final draft = await ref.read(aiServiceProvider).parseBill(
            text,
            categoryNames: [for (final c in usable) c.name],
          );
      if (!mounted || serial != _requestSerial) return;

      final category = matchBillCategory(usable, draft.type, draft.categoryName);
      if (category == null) {
        throw const AiException('没有可用分类，请先在设置中创建分类');
      }

      setState(() {
        placeholder.text =
            '识别为${draft.type == 'income' ? '收入' : '支出'}：'
            '¥${draft.amount.toStringAsFixed(2)} · ${category.name}'
            '${draft.note.trim().isEmpty ? '' : ' · ${draft.note.trim()}'}';
        _pendingBill = PendingBill(
          amount: draft.amount,
          type: draft.type,
          category: category,
          date: draft.date,
          note: draft.note,
        );
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        placeholder.text =
            error is AiException ? error.message : '解析失败：$error';
      });
    } finally {
      if (mounted && serial == _requestSerial) {
        setState(() => _busy = false);
      }
      _scrollToBottom();
    }
  }

  /// 与记账编辑器一致的默认账户选择：类型匹配、未隐藏、币种一致。
  Future<int?> _defaultAccountId(String kind, int ledgerId) async {
    try {
      final id = kind == 'income'
          ? await ref.read(defaultIncomeAccountIdProvider.future)
          : await ref.read(defaultExpenseAccountIdProvider.future);
      if (id == null) return null;
      final ledger = await ref.read(ledgerByIdProvider(ledgerId).future);
      if (ledger == null) return null;
      final account = await ref.read(accountByIdProvider(id).future);
      if (account == null || account.hidden) return null;
      if (account.currency != ledger.currency) return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePendingBill() async {
    final bill = _pendingBill;
    if (bill == null || _busy) return;

    setState(() => _busy = true);
    try {
      final ledgerId = ref.read(currentLedgerIdProvider);
      final accountId = await _defaultAccountId(bill.type, ledgerId);
      await ref.read(repositoryProvider).addTransaction(
            ledgerId: ledgerId,
            type: bill.type,
            amount: bill.amount,
            categoryId: bill.category.id >= 0 ? bill.category.id : null,
            happenedAt: bill.date,
            note: bill.note.trim().isEmpty ? null : bill.note.trim(),
            accountId: accountId,
          );
      ref.invalidate(countsForLedgerProvider(ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      ref.read(budgetRefreshProvider.notifier).state++;
      if (!mounted) return;
      setState(() {
        _pendingBill = null;
        _messages.add(AiChatItem(
          fromUser: false,
          text: '已记账：${bill.typeLabel} ¥${bill.amount.toStringAsFixed(2)}'
              ' · ${bill.category.name}',
        ));
      });
      _scrollToBottom();
      updateAppWidget(ref, context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(AiChatItem(
          fromUser: false,
          text: error is AiException ? error.message : '保存失败：$error',
        ));
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      // 消息列表 reverse: true，offset 0 即视觉底部。
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SimpleAiSettingsPage()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFECEFEA) : BeeTheme.ink;
    final muted = isDark ? const Color(0xFF8A938C) : const Color(0xFF6B7169);
    final mode = ref.watch(aiModeProvider);
    final ready = ref.watch(aiReadyProvider);
    final localStatus = mode == AiMode.local
        ? ref.watch(localModelStatusProvider).valueOrNull
        : null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Text(
                    'AI 助手',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mode == AiMode.local ? '本地' : '云端',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'AI 设置',
                    onPressed: _openSettings,
                    icon: Icon(Icons.tune_rounded, color: ink, size: 22),
                  ),
                ],
              ),
            ),
            if (!ready)
              _SetupCard(
                onTap: _openSettings,
                muted: muted,
                message: localStatus?.reason,
              )
            else
              Expanded(
                child: _messages.isEmpty
                    ? _Welcome(
                        muted: muted,
                        ink: ink,
                        onSummary: () => _runFeature('summary'),
                        onInsight: () => _runFeature('insight'),
                        onPrompt: (text) {
                          _inputController.text = text;
                          _sendQuestion();
                        },
                      )
                    : AiMessageList(
                        items: _messages,
                        busy: _busy,
                        ink: ink,
                        muted: muted,
                        controller: _scrollController,
                      ),
              ),
            if (_pendingBill != null)
              BillConfirmBar(
                bill: _pendingBill!,
                saving: _busy,
                onSave: _savePendingBill,
                onCancel: () => setState(() => _pendingBill = null),
              ),
            _InputBar(
              controller: _inputController,
              busy: _busy,
              onSend: _sendQuestion,
              onStop: () async {
                _requestSerial++;
                setState(() {
                  if (_messages.isNotEmpty &&
                      (_messages.last.text == '正在思考…' ||
                          _messages.last.text == '正在解析账单…')) {
                    _messages.last.text = '正在停止…';
                  }
                });
                // 等原生生成循环真正退出后再允许下一次发送。
                await ref.read(aiEngineProvider).cancel();
                if (!mounted) return;
                setState(() {
                  _busy = false;
                  if (_messages.isNotEmpty &&
                      _messages.last.text == '正在停止…') {
                    _messages.last.text = '已停止';
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.muted,
    required this.ink,
    required this.onSummary,
    required this.onInsight,
    required this.onPrompt,
  });

  final Color muted;
  final Color ink;
  final VoidCallback onSummary;
  final VoidCallback onInsight;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = DateFormat('yyyy年M月').format(now);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: [
        Text(
          date,
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 10),
        Text(
          '从一笔账，或一个问题开始',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '我会基于当前账本回答，只使用本地已有的数据。',
          style: TextStyle(fontSize: 14, height: 1.6, color: muted),
        ),
        const SizedBox(height: 28),
        _QuickAction(
          icon: Icons.receipt_long_outlined,
          title: '本月消费总结',
          subtitle: '用几句话总结这个月的收支',
          onTap: onSummary,
          ink: ink,
          muted: muted,
        ),
        _QuickAction(
          icon: Icons.insights_outlined,
          title: '消费洞察',
          subtitle: '找出高消费分类和变化趋势',
          onTap: onInsight,
          ink: ink,
          muted: muted,
        ),
        _QuickAction(
          icon: Icons.help_outline_rounded,
          title: '试试问：本月哪项花得最多？',
          subtitle: '可以直接在下方输入问题',
          onTap: () => onPrompt('本月哪项花得最多？'),
          ink: ink,
          muted: muted,
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.ink,
    required this.muted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 外层 Scaffold 会消费键盘 inset，页面内 viewInsets 可能恒为 0；
    // 优先读取外壳下发的键盘/导航布局状态。
    final scope = KeyboardLayoutScope.maybeOf(context);
    final keyboardOpen = scope?.keyboardOpen ??
        (MediaQuery.viewInsetsOf(context).bottom > 0);
    final navHeight = scope?.bottomNavHeight ?? 0;
    final bottomPadding = keyboardOpen
        ? 8.0
        : MediaQuery.paddingOf(context).bottom +
            (navHeight > 0 ? navHeight : 8);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => busy ? null : onSend(),
              decoration: InputDecoration(
                hintText: '例如：买了杯咖啡 35 块',
                hintStyle: TextStyle(fontSize: 14, color: isDark
                    ? const Color(0xFF7C8580)
                    : const Color(0xFF9AA29D)),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF182220)
                    : Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: busy ? onStop : onSend,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: Icon(busy ? Icons.stop_rounded : Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.onTap,
    required this.muted,
    this.message,
  });

  final VoidCallback onTap;
  final Color muted;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined, size: 40, color: muted),
              const SizedBox(height: 16),
              Text(
                'AI 尚未配置',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '选择云端 API 或下载本地模型后即可使用。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: muted),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.5, color: error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onTap,
                child: const Text('去设置'),
              ),
              const SizedBox(height: 12),
              Text(
                '云端模式会把当前功能所需的账单文本发送给模型服务商。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, height: 1.5, color: error.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstUseGuide extends StatelessWidget {
  const _FirstUseGuide();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择 AI 推理方式',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '之后可以随时在 AI 设置中切换。',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 20),
            _modeOption(
              context,
              mode: AiMode.local,
              icon: Icons.phone_android_rounded,
              title: '本地模型',
              subtitle: '完全离线，账单数据不出设备。需要先下载模型（约 0.6–2.4 GB）。',
            ),
            const SizedBox(height: 10),
            _modeOption(
              context,
              mode: AiMode.cloud,
              icon: Icons.cloud_outlined,
              title: '云端 API',
              subtitle: '能力更强，需要联网并填写 API Key。使用时会把账单文本发送给服务商。',
            ),
            const SizedBox(height: 16),
            Text(
              '小提示：本地模式首次使用需要先下载模型；云端模式需要你自备 OpenAI 兼容接口。',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeOption(
    BuildContext context, {
    required AiMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, mode),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
