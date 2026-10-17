import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/data/seed_service.dart';
import '../../theme.dart';

/// 极简记账首次启动页：纯本地初始化，不涉及账号与云同步。
class SimpleWelcomePage extends ConsumerStatefulWidget {
  const SimpleWelcomePage({super.key});

  @override
  ConsumerState<SimpleWelcomePage> createState() => _SimpleWelcomePageState();
}

class _SimpleWelcomePageState extends ConsumerState<SimpleWelcomePage> {
  bool _starting = false;
  String? _error;

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final existing = await db.select(db.ledgers).get();
      final l10n = lookupAppLocalizations(const Locale('zh'));

      if (existing.isEmpty) {
        await SeedService.seedDatabase(
          db,
          l10n,
          currency: 'CNY',
          useHierarchicalCategories: false,
          createDefaultLedger: true,
        );
      }

      final ledgers = await db.select(db.ledgers).get();
      if (ledgers.isNotEmpty) {
        ref.read(currentLedgerIdProvider.notifier).state = ledgers.first.id;
      }
      ref.read(baseCurrencyProvider.notifier).state = 'CNY';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('welcome_shown', true);
      ref.read(shouldShowWelcomeProvider.notifier).state = false;
    } catch (error) {
      if (mounted) setState(() => _error = '初始化失败：$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFECEFEA) : BeeTheme.ink;
    final muted = isDark ? const Color(0xFF8A938C) : const Color(0xFF6B7169);
    final teal = isDark ? BeeTheme.tealDark : BeeTheme.teal;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: teal,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 24),
              Text(
                '极简记账',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '本地优先，隐私优先。\n账本只保存在这台手机上。',
                style: TextStyle(fontSize: 15, height: 1.7, color: muted),
              ),
              const Spacer(flex: 3),
              _FeatureRow(
                icon: Icons.account_balance_wallet_outlined,
                text: '收支、分类、标签与图片记账',
                ink: ink,
                muted: muted,
                teal: teal,
              ),
              _FeatureRow(
                icon: Icons.insights_outlined,
                text: '环比同比、分类排行与趋势图',
                ink: ink,
                muted: muted,
                teal: teal,
              ),
              _FeatureRow(
                icon: Icons.lock_outline_rounded,
                text: '默认人民币，数据不出设备',
                ink: ink,
                muted: muted,
                teal: teal,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _starting ? null : _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _starting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '开始使用',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '不需要账号，不会上传任何数据',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.text,
    required this.ink,
    required this.muted,
    required this.teal,
  });

  final IconData icon;
  final String text;
  final Color ink;
  final Color muted;
  final Color teal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 20, color: teal),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(fontSize: 14, color: ink)),
        ],
      ),
    );
  }
}
