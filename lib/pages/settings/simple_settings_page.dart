import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/simple_settings_providers.dart';
import '../../providers/theme_providers.dart';
import '../../styles/tokens.dart';
import '../data/import_page.dart';
import '../data/export_page.dart';
import 'app_lock_settings_page.dart';
import 'font_settings_page.dart';
import 'simple_about_page.dart';
import 'simple_data_page.dart';
import 'widget_management_page.dart';

/// 极简记账 - 设置页
///
/// 按蓝皮书要求精简为四组：
/// 外观 / 数据管理 / 桌面小组件 / 关于
class SimpleSettingsPage extends ConsumerWidget {
  const SimpleSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 20),
              child: Text(
                '设置',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ),
            _SectionLabel('外观'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.brightness_6_outlined,
                  title: '主题模式',
                  trailingText: _themeModeLabel(themeMode),
                  onTap: () => _pickThemeMode(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.format_size,
                  title: '字体大小',
                  onTap: () => _push(context, const FontSettingsPage()),
                ),
                const _TotalAssetSwitchTile(),
              ],
            ),
            _SectionLabel('安全'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: '应用锁',
                  subtitle: 'PIN / 生物识别',
                  onTap: () => _push(context, const AppLockSettingsPage()),
                ),
              ],
            ),
            _SectionLabel('数据管理'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.backup_outlined,
                  title: '备份与恢复',
                  subtitle: '数据库与图片完整打包',
                  onTap: () => _push(context, const SimpleDataPage()),
                ),
                _SettingsTile(
                  icon: Icons.file_download_outlined,
                  title: 'CSV 导入',
                  onTap: () => _push(context, const ImportPage()),
                ),
                _SettingsTile(
                  icon: Icons.file_upload_outlined,
                  title: 'CSV 导出',
                  onTap: () => _push(context, const ExportPage()),
                ),
              ],
            ),
            _SectionLabel('桌面'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.widgets_outlined,
                  title: '桌面小组件',
                  subtitle: '4×2 横版，显示本月支出',
                  onTap: () => _push(context, const WidgetManagementPage()),
                ),
              ],
            ),
            _SectionLabel('关于'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.info_outline,
                  title: '关于极简记账',
                  onTap: () => _push(context, const SimpleAboutPage()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  static void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  static Future<void> _pickThemeMode(
      BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final current = ref.read(themeModeProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '主题模式',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
              ),
              for (final mode in const [
                ThemeMode.system,
                ThemeMode.light,
                ThemeMode.dark,
              ])
                ListTile(
                  title: Text(_themeModeLabel(mode)),
                  trailing: current == mode
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(context, mode),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      ref.read(themeModeProvider.notifier).state = selected;
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: BeeTokens.textTertiary(context),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BeeTokens.border(context), width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 52,
                  color: BeeTokens.divider(context),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: BeeTokens.iconSecondary(context)),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: BeeTokens.textPrimary(context),
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: BeeTokens.textTertiary(context),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(
              trailingText!,
              style: TextStyle(
                fontSize: 13,
                color: BeeTokens.textTertiary(context),
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right,
              size: 20, color: BeeTokens.iconTertiary(context)),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 14,
    );
  }
}

class _TotalAssetSwitchTile extends ConsumerWidget {
  const _TotalAssetSwitchTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(showTotalAssetProvider);

    return SwitchListTile(
      value: enabled,
      onChanged: (value) =>
          ref.read(showTotalAssetProvider.notifier).state = value,
      secondary: Icon(Icons.account_balance_wallet_outlined,
          size: 22, color: BeeTokens.iconSecondary(context)),
      title: Text(
        '首页显示总资产',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: BeeTokens.textPrimary(context),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}
