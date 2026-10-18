/// AI 文本清洗与记账意图判定。
///
/// 这些函数不依赖 Flutter/Riverpod，便于直接单测，也同时服务于本地与云端
/// 两种推理模式。
library;

/// 移除模型输出中的 `<think>` / `<thinking>` 块。
///
/// Qwen3 等模型即使收到 `/no_think` 仍可能输出空标签或思考内容；这些内容
/// 不应展示给用户，也不应进入 JSON 解析。未闭合的标签只移除标签本身，
/// 保留其后的正文（避免误吞整段回答）。
String sanitizeAiText(String raw) {
  var text = raw;
  text = text.replaceAll(
    RegExp(r'<think(?:ing)?>[\s\S]*?</think(?:ing)?>',
        caseSensitive: false),
    '',
  );
  text = text.replaceAll(
    RegExp(r'</?think(?:ing)?>', caseSensitive: false),
    '',
  );
  return text.trim();
}

/// 流式输出专用的清洗：额外隐藏尚未闭合的 think 块和标签前缀。
///
/// 流式 token 可能把 `<think>` 拆成 `<thi` + `nk>`，逐段展示时不能把半截
/// 标签或思考内容露给用户；已闭合的完整块与正常正文照常保留。
String sanitizeAiStreamText(String raw) {
  var text = raw.replaceAll(
    RegExp(r'<think(?:ing)?>[\s\S]*?</think(?:ing)?>',
        caseSensitive: false),
    '',
  );

  // 未闭合的开标签：从标签起全部视为仍在思考。
  final open =
      RegExp(r'<think(?:ing)?>', caseSensitive: false).firstMatch(text);
  if (open != null) text = text.substring(0, open.start);

  // 游离的闭标签直接丢弃。
  text = text.replaceAll(
    RegExp(r'</think(?:ing)?>', caseSensitive: false),
    '',
  );

  // chunk 末尾可能是 `<t` / `<thi` / `<think` 等半截标签。
  text = text.replaceFirst(
    RegExp(r'<t(?:h(?:i(?:n(?:k(?:i(?:n(?:g)?)?)?)?)?)?)?$',
        caseSensitive: false),
    '',
  );
  return text.trimRight();
}

/// 判断用户输入是否更像“记一笔账”而不是账本问答。
///
/// 规则优先于小模型分类，保证 0.6B 模型下也稳定：
/// - 有金额 + 消费/收入动词 → 记账；
/// - 有明确指令（“记一笔”“帮我记”）且不是疑问句 → 记账；
/// - “你能帮我记账吗”“本月支出多少”等提问 → 问答。
bool looksLikeBillIntent(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;

  final isQuestion = RegExp(r'(吗|呢|怎么|如何|能否|能不能|可以吗|多少|几[个笔次]|[？?])')
      .hasMatch(text);

  // 能力询问：“你能帮我记账吗”不是记账指令。
  if (isQuestion &&
      RegExp(r'(能|可以|会|可否)').hasMatch(text) &&
      RegExp(r'记(账|一笔|个账)').hasMatch(text)) {
    return false;
  }

  final hasAmount = RegExp(
    r'[¥￥$]?\s*\d+(?:\.\d+)?\s*(?:元|块|块钱|角|毛|万|千|百|rmb|人民币)?',
    caseSensitive: false,
  ).hasMatch(text);

  final billVerb = RegExp(
    r'记(?:一|个|下)?(?:笔|账)|记账|帮我记|买了|买|花了|花费|付了|付款|支出|收入|收到|消费|报销|打车|吃|喝|购物',
  ).hasMatch(text);

  if (hasAmount && billVerb) return true;

  // 没有金额但指令明确时也进入记账流程，由解析层提示补充金额。
  final imperative = RegExp(r'记(?:一|个|下)?(?:笔|账)|帮我记').hasMatch(text);
  return imperative && !isQuestion;
}
