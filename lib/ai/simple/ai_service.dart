import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart' show Category, Transaction;
import 'ai_engine.dart';
import 'ai_settings.dart';
import 'ai_providers.dart';
import 'ai_text_utils.dart';
import 'cloud_ai_engine.dart';
import 'local_ai_engine.dart';

/// 一句话记账的解析结果。
class BillDraft {
  const BillDraft({
    required this.amount,
    required this.type,
    required this.categoryName,
    required this.date,
    required this.note,
  });

  final double amount;
  final String type; // expense / income
  final String categoryName;
  final DateTime date;
  final String note;
}

/// 提供给 AI 的账本快照（只包含当前功能必需的统计数据）。
class AiLedgerSnapshot {
  const AiLedgerSnapshot({
    required this.rangeLabel,
    required this.income,
    required this.expense,
    required this.previousIncome,
    required this.previousExpense,
    required this.lastYearIncome,
    required this.lastYearExpense,
    required this.categories,
    required this.transactions,
  });

  final String rangeLabel;
  final double income;
  final double expense;
  final double previousIncome;
  final double previousExpense;
  final double lastYearIncome;
  final double lastYearExpense;
  final List<({String name, double total})> categories;
  final List<({DateTime date, String type, String category, double amount, String note})>
      transactions;

  String toPromptText() {
    final buffer = StringBuffer()
      ..writeln('统计范围：$rangeLabel')
      ..writeln('收入：${_money(income)}，支出：${_money(expense)}')
      ..writeln(
          '上期收入：${_money(previousIncome)}，上期支出：${_money(previousExpense)}')
      ..writeln(
          '去年同期收入：${_money(lastYearIncome)}，去年同期支出：${_money(lastYearExpense)}')
      ..writeln('支出分类排行：');
    if (categories.isEmpty) {
      buffer.writeln('（无支出）');
    } else {
      for (final category in categories.take(8)) {
        buffer.writeln('- ${category.name}: ${_money(category.total)}');
      }
    }
    buffer.writeln('最近交易（最多 20 条）：');
    if (transactions.isEmpty) {
      buffer.writeln('（无交易）');
    } else {
      final dateFormat = DateFormat('MM-dd');
      for (final tx in transactions.take(20)) {
        final typeLabel = tx.type == 'income' ? '收入' : '支出';
        final note = tx.note.isEmpty ? '' : '，备注：${tx.note}';
        buffer.writeln(
            '- ${dateFormat.format(tx.date)} $typeLabel ${tx.category} ${_money(tx.amount)}$note');
      }
    }
    return buffer.toString();
  }

  static String _money(double value) => NumberFormat('#,##0.00').format(value);
}

class AiService {
  AiService(this.engine);

  final AiEngine engine;

  static const _system =
      '你是「极简记账」的记账助手。回答使用简体中文，简洁准确。'
      '只依据用户提供的数据回答，不编造数据；数据不足时明确说明。';

  Future<BillDraft> parseBill(
    String input, {
    required List<String> categoryNames,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final categoryText =
        categoryNames.isEmpty ? '（无可用分类）' : categoryNames.join('、');
    final prompt = '''
把用户的一句话解析成一条记账记录，只输出 JSON，不要 markdown 代码块，不要解释。
JSON 字段：
- amount: 数字，必须大于 0
- type: "expense" 或 "income"
- category: 必须从以下分类中选择最匹配的一个：$categoryText
- date: YYYY-MM-DD，未提到日期时用今天
- note: 简短备注，可为空字符串
今天日期：${DateFormat('yyyy-MM-dd').format(today)}
用户输入：$input
/no_think
''';
    final response = await engine.complete(
      [
        const AiMessage(role: 'system', content: _system),
        AiMessage(role: 'user', content: prompt),
      ],
      temperature: 0.1,
      maxTokens: 256,
    );
    return _parseBillDraft(response, categoryNames, today);
  }

  List<AiMessage> _summaryMessages(AiLedgerSnapshot snapshot) => [
        const AiMessage(role: 'system', content: _system),
        AiMessage(
          role: 'user',
          content: '根据下面的账本数据，用 3-5 句中文写本月消费总结：'
              '先说收入和支出总体情况，再说支出最多的 2-3 个分类，最后给一句中性结论。'
              '不要列清单，不要编造数据。\n\n${snapshot.toPromptText()}\n/no_think',
        ),
      ];

  List<AiMessage> _insightMessages(AiLedgerSnapshot snapshot) => [
        const AiMessage(role: 'system', content: _system),
        AiMessage(
          role: 'user',
          content: '根据下面的账本数据，给出 2-3 条消费洞察和 1 条可执行建议。'
              '重点看高消费分类、环比/同比变化。用中文短句，不要编造数据。\n\n'
              '${snapshot.toPromptText()}\n/no_think',
        ),
      ];

  List<AiMessage> _answerMessages(String question, AiLedgerSnapshot snapshot) => [
        const AiMessage(role: 'system', content: _system),
        AiMessage(
          role: 'user',
          content: '下面是用户的账本数据。请直接回答问题，回答尽量简短；'
              '如果数据不足以回答，请说明。\n\n${snapshot.toPromptText()}\n\n用户问题：$question\n/no_think',
        ),
      ];

  Future<String> monthlySummary(AiLedgerSnapshot snapshot) {
    return engine.complete(_summaryMessages(snapshot),
        temperature: 0.5, maxTokens: 420);
  }

  /// 流式版月度总结，供 UI 逐字上屏。
  Stream<String> monthlySummaryStream(AiLedgerSnapshot snapshot) {
    return engine.streamChat(_summaryMessages(snapshot),
        temperature: 0.5, maxTokens: 420);
  }

  Future<String> spendingInsight(AiLedgerSnapshot snapshot) {
    return engine.complete(_insightMessages(snapshot),
        temperature: 0.5, maxTokens: 420);
  }

  /// 流式版消费洞察。
  Stream<String> spendingInsightStream(AiLedgerSnapshot snapshot) {
    return engine.streamChat(_insightMessages(snapshot),
        temperature: 0.5, maxTokens: 420);
  }

  Future<String> answer(String question, AiLedgerSnapshot snapshot) {
    return engine.complete(_answerMessages(question, snapshot),
        temperature: 0.4, maxTokens: 480);
  }

  /// 流式版账本问答。
  Stream<String> answerStream(String question, AiLedgerSnapshot snapshot) {
    return engine.streamChat(_answerMessages(question, snapshot),
        temperature: 0.4, maxTokens: 480);
  }

  static BillDraft _parseBillDraft(
    String raw,
    List<String> categoryNames,
    DateTime today,
  ) {
    // Qwen3 等模型可能先输出 <think> 块；块内也可能出现花括号，必须先剔除。
    var text = sanitizeAiText(raw);
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const AiException('AI 没有返回可解析的记账结果，请换一种说法再试');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      throw const AiException('AI 返回的记账结果格式不正确，请重试');
    }
    if (decoded is! Map) {
      throw const AiException('AI 返回的记账结果格式不正确，请重试');
    }

    final amountRaw = decoded['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse('$amountRaw') ?? 0;
    if (amount <= 0) {
      throw const AiException('没有识别到有效金额，请补充金额后重试');
    }

    final typeRaw = '${decoded['type'] ?? ''}';
    final type = typeRaw.contains('income') || typeRaw.contains('收入')
        ? 'income'
        : 'expense';

    var category = '${decoded['category'] ?? ''}'.trim();
    if (category.isEmpty || !categoryNames.contains(category)) {
      category = _matchCategory(category, categoryNames) ??
          (categoryNames.isEmpty ? '未分类' : categoryNames.first);
    }

    DateTime date = today;
    final dateRaw = '${decoded['date'] ?? ''}'.trim();
    if (dateRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(dateRaw);
      if (parsed != null) date = parsed;
    }

    return BillDraft(
      amount: amount,
      type: type,
      categoryName: category,
      date: date,
      note: '${decoded['note'] ?? ''}'.trim(),
    );
  }

  static String? _matchCategory(String raw, List<String> categories) {
    if (raw.isEmpty) return null;
    for (final category in categories) {
      if (category.contains(raw) || raw.contains(category)) return category;
    }
    return null;
  }
}

/// 按当前模式创建文字推理引擎。
final aiEngineProvider = Provider<AiEngine>((ref) {
  final mode = ref.watch(aiModeProvider);
  if (mode == AiMode.local) {
    // 直接使用已校验完成的模型状态，避免 aiLocalModelFileProvider 尚未
    // 就绪时拿到空路径（真机首问出现过该竞态）。
    final info = ref.watch(localModelStatusProvider).valueOrNull;
    final path = info?.status == LocalModelStatus.ready
        ? (info?.path ?? '')
        : '';
    return LocalAiEngine(
      modelPath: path,
      useGpu: ref.watch(aiGpuEnabledProvider),
    );
  }
  return CloudAiEngine(
    baseUrl: ref.watch(aiBaseUrlProvider),
    apiKey: ref.watch(aiApiKeyProvider) ?? '',
    model: ref.watch(aiModelNameProvider),
  );
});

final aiServiceProvider = Provider<AiService>((ref) {
  return AiService(ref.watch(aiEngineProvider));
});

/// OCR 始终走云端视觉模型（蓝图：本地不支持图片 OCR）。
class AiOcrService {
  AiOcrService(this._engine);

  final CloudAiEngine _engine;

  Future<String> recognize(File image) async {
    final bytes = await image.readAsBytes();
    final extension = image.path.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    return _engine.ocrImage(
      base64Image: base64Encode(bytes),
      mimeType: mime,
    );
  }
}

final aiOcrServiceProvider = Provider<AiOcrService>((ref) {
  final ocrModel = ref.watch(aiOcrModelNameProvider).trim();
  final model = ocrModel.isEmpty
      ? ref.watch(aiModelNameProvider).trim()
      : ocrModel;
  return AiOcrService(
    CloudAiEngine(
      baseUrl: ref.watch(aiBaseUrlProvider),
      apiKey: ref.watch(aiApiKeyProvider) ?? '',
      model: model,
    ),
  );
});

/// 把 AI 返回的分类名匹配到本地分类：优先名称完全一致且收支类型一致，
/// 否则回退到同类型的第一个可用分类；没有同类型分类时返回 null。
Category? matchBillCategory(
  List<Category> categories,
  String kind,
  String categoryName,
) {
  Category? fallback;
  for (final category in categories) {
    if (category.kind != kind) continue;
    fallback ??= category;
    if (category.name == categoryName) return category;
  }
  return fallback;
}

/// 由当前分类与交易构造给 AI 的紧凑快照。
AiLedgerSnapshot buildSnapshot({
  required String rangeLabel,
  required double income,
  required double expense,
  required double previousIncome,
  required double previousExpense,
  required double lastYearIncome,
  required double lastYearExpense,
  required List<({String name, double total})> categories,
  required List<Transaction> transactions,
  required List<Category> allCategories,
}) {
  final categoryMap = {for (final category in allCategories) category.id: category};
  return AiLedgerSnapshot(
    rangeLabel: rangeLabel,
    income: income,
    expense: expense,
    previousIncome: previousIncome,
    previousExpense: previousExpense,
    lastYearIncome: lastYearIncome,
    lastYearExpense: lastYearExpense,
    categories: categories,
    transactions: [
      for (final tx in transactions)
        (
          date: tx.happenedAt,
          type: tx.type,
          category: categoryMap[tx.categoryId]?.name ??
              (tx.type == 'transfer' ? '转账' : '未分类'),
          amount: tx.amount,
          note: tx.note?.trim() ?? '',
        ),
    ],
  );
}
