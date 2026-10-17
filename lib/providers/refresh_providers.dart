import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 极简版保留的刷新信号。
///
/// 这些 StateProvider 原先定义在云同步栈里，被本地页面当作“数据变了，
/// 重新取一次”的 tick 使用。移除云同步后仍然需要它们，所以单独放在这里，
/// 不再依赖任何 cloud 代码。

final syncGenerationProvider = StateProvider<int>((ref) => 0);

final syncStatusRefreshProvider = StateProvider<int>((ref) => 0);

final syncStatusRefreshByLedgerProvider =
    StateProvider.family<int, int>((ref, _) => 0);

final lastSyncErrorProvider = StateProvider<String?>((ref) => null);

final ledgerListRefreshProvider = StateProvider<int>((ref) => 0);

final sharedResourceRefreshProvider = StateProvider<int>((ref) => 0);
