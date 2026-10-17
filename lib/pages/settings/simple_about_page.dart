import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../styles/tokens.dart';

class SimpleAboutPage extends StatefulWidget {
  const SimpleAboutPage({super.key});

  @override
  State<SimpleAboutPage> createState() => _SimpleAboutPageState();
}

class _SimpleAboutPageState extends State<SimpleAboutPage> {
  String _version = '1.0.0';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    });
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
          _InfoRow(title: '备份', value: 'zip（数据库 + 图片）'),
          _InfoRow(title: '本地 AI', value: 'llama.cpp + GGUF'),
          _InfoRow(title: '云端 AI', value: 'OpenAI 兼容接口'),
          const SizedBox(height: 24),
          Text(
            '开源与许可',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BeeTokens.textTertiary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '本项目基于蜜蜂记账（BeeCount）二次开发，作为衍生作品沿用上游的非商业许可：'
            '个人学习与非营利使用免费，商业使用需获得上游作者授权。请保留原始版权声明与许可协议。',
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            'https://github.com/TNT-Likely/BeeCount',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
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
