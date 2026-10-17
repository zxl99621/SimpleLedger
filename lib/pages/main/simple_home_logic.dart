import '../../utils/month_range.dart';

/// 首页月度统计所需的 provider 参数。
///
/// 月份归属必须跟账本的每月起始日一致，不能简单用自然月。
({int ledgerId, DateTime month}) homeMonthlyTotalsParams({
  required int ledgerId,
  required DateTime now,
  required int startDay,
}) {
  return (ledgerId: ledgerId, month: labelForDate(now, startDay));
}
