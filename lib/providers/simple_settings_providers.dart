import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SimpleLedger 自有设置项。
///
/// 与原版 BeeCount 的大量配置分开存放，便于裁剪阶段逐步替换。

/// 首页是否显示总资产卡片（蓝皮书 §2.1 · 通用设置）
final showTotalAssetProvider = StateProvider<bool>((ref) => true);

/// 启动时恢复并监听持久化
final showTotalAssetInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('simple_show_total_asset');
  if (saved != null) {
    ref.read(showTotalAssetProvider.notifier).state = saved;
  }
  ref.listen<bool>(showTotalAssetProvider, (previous, next) async {
    await prefs.setBool('simple_show_total_asset', next);
  });
});
