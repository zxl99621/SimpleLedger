import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart' show Category;

/// AI 从一句话中解析出的待确认账单。
class PendingBill {
  const PendingBill({
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    required this.note,
  });

  final double amount;
  final String type; // expense / income
  final Category category;
  final DateTime date;
  final String note;

  String get typeLabel => type == 'income' ? '收入' : '支出';
}

/// 记账确认条：AI 解析后不直接落库，先让用户确认金额/分类/日期/备注。
class BillConfirmBar extends StatelessWidget {
  const BillConfirmBar({
    super.key,
    required this.bill,
    required this.onSave,
    required this.onCancel,
    this.saving = false,
  });

  final PendingBill bill;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF8A938C)
        : const Color(0xFF6B7169);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 20, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${bill.typeLabel} ¥${bill.amount.toStringAsFixed(2)} · ${bill.category.name}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF132220),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('M月d日').format(bill.date)}'
                  '${bill.note.trim().isEmpty ? '' : ' · ${bill.note.trim()}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('bill-confirm-cancel'),
            onPressed: saving ? null : onCancel,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('取消'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: const ValueKey('bill-confirm-save'),
            onPressed: saving ? null : onSave,
            style: FilledButton.styleFrom(
              minimumSize: const Size(56, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}
