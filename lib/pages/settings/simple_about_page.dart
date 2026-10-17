import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../styles/tokens.dart';

class SimpleAboutPage extends StatefulWidget {
  const SimpleAboutPage({super.key});

  @override
  State<SimpleAboutPage> createState() => _SimpleAboutPageState();
}

class _SimpleAboutPageState extends State<SimpleAboutPage> {
  static const _githubRepo = 'https://github.com/zxl99621/SimpleLedger';
  static const _giteeRepo = 'https://gitee.com/zxl996/simple-ledger';
  static const _githubReleases =
      'https://github.com/zxl99621/SimpleLedger/releases';
  static const _giteeReleases = 'https://gitee.com/zxl996/simple-ledger/releases';
  static const _upstream = 'https://github.com/TNT-Likely/BeeCount';

  String _version = '—';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    });
  }

  Future<void> _open(String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接，请检查是否安装了浏览器')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      appBar: AppBar(title: const Text('关于极简记账')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            '极简记账',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: BeeTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '版本 $_version',
            style: TextStyle(
              fontSize: 12,
              color: BeeTokens.textTertiary(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '本地优先的个人记账工具。账单、标签、图片与配置全部保存在这台手机上，'
            '不需要账号，不做云同步。',
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 24),
          _InfoRow(title: '数据存储', value: 'App 私有目录'),
          _InfoRow(title: '备份', value: 'zip / 可选加密'),
          _InfoRow(title: '本地 AI', value: 'llama.cpp + GGUF（arm64）'),
          _InfoRow(title: '云端 AI', value: 'OpenAI 兼容接口'),
          const SizedBox(height: 24),
          _SectionLabel('项目主页'),
          _LinkTile(
            icon: Icons.code_rounded,
            title: 'GitHub 仓库',
            subtitle: 'github.com/zxl99621/SimpleLedger',
            onTap: () => _open(_githubRepo),
          ),
          _LinkTile(
            icon: Icons.code_rounded,
            title: 'Gitee 仓库',
            subtitle: 'gitee.com/zxl996/simple-ledger',
            onTap: () => _open(_giteeRepo),
          ),
          _LinkTile(
            icon: Icons.download_rounded,
            title: 'GitHub Releases',
            subtitle: '下载 APK 与源码',
            onTap: () => _open(_githubReleases),
          ),
          _LinkTile(
            icon: Icons.download_rounded,
            title: 'Gitee 发行版',
            subtitle: '下载 APK 与源码',
            onTap: () => _open(_giteeReleases),
          ),
          const SizedBox(height: 24),
          _SectionLabel('源码与许可'),
          Text(
            '本项目基于蜜蜂记账（BeeCount）二次开发，为源码公开（source-available）项目，'
            '沿用上游的非商业许可：个人学习与非营利使用免费，商业使用需获得上游作者授权。'
            '请保留原始版权声明与许可协议。',
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          _LinkTile(
            icon: Icons.link_rounded,
            title: '上游项目：BeeCount',
            subtitle: 'github.com/TNT-Likely/BeeCount',
            onTap: () => _open(_upstream),
          ),
          const SizedBox(height: 20),
          Text(
            '© 2026 SimpleLedger',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: BeeTokens.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: BeeTokens.textTertiary(context),
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, size: 20, color: BeeTokens.iconSecondary(context)),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: BeeTokens.textPrimary(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: BeeTokens.textTertiary(context),
        ),
      ),
      trailing: Icon(Icons.open_in_new,
          size: 16, color: BeeTokens.iconTertiary(context)),
      onTap: onTap,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
