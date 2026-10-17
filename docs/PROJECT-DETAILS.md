# SimpleLedger 极简记账

个人自用的 Android 记账 App，基于蜜蜂记账（BeeCount）二次开发，走「本地优先、隐私优先、内置 AI」的路线。

- 平台：Android 11+（API 30）
- 技术栈：Flutter 3.x + Riverpod + Drift（SQLite）
- 推理：本地 llama.cpp（GGUF）/ 云端 OpenAI 兼容接口
- 显示语言：简体中文

## 已实现功能

### 记账
- 收入 / 支出两种类型，金额、分类、日期
- 备注、图片附件、多标签（折叠在「更多」面板）
- 记账弹窗内的一句话 AI 解析（自动填金额、分类、日期、备注）
- 图片 OCR（云端视觉模型，独立开关；识别后自动回填金额/日期/备注）
- 桌面长按图标：拍照 / 相册快捷记账

### 统计
- 本周 / 本月 / 自定义时间段
- 本期收入、支出，环比上期、同比去年
- 支出分类饼图、近 6 个月收支柱状图、分类排行、本期明细
- 「AI 解读」入口：基于确定性统计数据生成自然语言总结

### 数据
- 完整备份：SQLite 数据库 + 图片目录打包为 zip，保存到系统「下载」目录
- 完整恢复：校验 zip 结构与 SQLite 文件头后覆盖恢复，完成后提示重启
- CSV 导入 / 导出（复用上游实现）
- 一键清空全部账单、标签与图片

### AI
- 首次进入 AI 页时引导选择「本地模型 / 云端 API」，之后不再打扰
- 文字类能力统一走同一调度层：
  - 一句话记账解析
  - 月度消费总结
  - 消费洞察
  - 账单问答
- 云端：接口地址 + API Key + 模型名，兼容 DeepSeek、通义、智谱、Moonshot、OpenAI 等
- API Key 通过 Android Keystore 加密存储（flutter_secure_storage）
- 本地模型：Qwen3 GGUF，支持 ModelScope / Hugging Face / 自定义 URL 下载，可切换、删除
- OCR 始终走云端视觉模型，与文字推理模式无关

### 界面
- 5 个底部 Tab：首页 · 统计 · 记账（居中）· AI · 设置
- 浅色 / 深色 / 跟随系统
- 青绿色主题（Ink & Teal），数字使用等宽字形

## 本地模型清单

| 模型 | 量化 | 体积 | 推荐用途 |
|------|------|------|----------|
| Qwen3 0.6B | Q8_0 | 约 610 MB | 快速记账解析，低性能设备 |
| Qwen3 1.7B | Q8_0 | 约 1.75 GB | 均衡，总结与问答 |
| Qwen3 4B | Q4_K_M | 约 2.38 GB | 高质量洞察与复杂问答 |

> 注：蓝皮书原写 Qwen3 1.5B/3B，但 Qwen3 官方并无这两个尺寸，实际采用 0.6B / 1.7B / 4B。

模型下载到 App 私有目录，其他应用不可访问，卸载 App 时一并删除。

## 构建

环境（本项目已验证）：

| 项 | 版本 / 路径 |
|----|-------------|
| Flutter | 3.47.7 stable |
| Dart | 3.13.5 |
| JDK | Zulu 17（`flutter config --jdk-dir=...`） |
| Gradle | 8.14.3 |
| Kotlin | 2.2.20 |
| NDK | 28.2.13676358 |
| Android SDK | API 36 |

```bash
cd F:\SimpleLedger\BeeCount
flutter pub get
flutter build apk --debug --flavor dev --target-platform android-arm64
# 产物：build\app\outputs\flutter-apk\app-dev-debug.apk
```

Release：

```bash
flutter build apk --release --flavor prod --target-platform android-arm64
```

> 本地 Pub / Gradle 缓存位于 D 盘（`D:\AndroidDevCache`），项目与 Android SDK/NDK 位于 F 盘。
> Kotlin 增量编译已关闭（`kotlin.incremental=false`），因为缓存跨盘符会导致增量缓存报错。

> `sqlite3` 3.7 的 native assets 默认从 GitHub Releases 下载预编译库；`pubspec.yaml` 的
> `hooks.user_defines.sqlite3.url_pattern` 已指向 `ghproxy.net` 镜像。若该镜像不可用，
> 可改为 `https://gh-proxy.com/https://github.com/...` 或配置网络代理后删除该配置。

## 数据与隐私

- 所有账单、标签、图片、配置均保存在 App 私有目录
- 云端模式仅在用户主动触发 AI/OCR 时发送当前功能必需的账单文本或图片
- 本地模式不联网，账单数据不出设备
- 备份文件保存在用户选择的位置（默认「下载」目录），由用户自行保管

## 许可证与来源

- 基底项目：[蜜蜂记账 BeeCount](https://github.com/TNT-Likely/BeeCount)
- 上游许可证：BeeCount 软件许可协议（个人 / 非营利使用免费；商业使用需单独授权）
- 本项目作为衍生作品，沿用相同的非商业限制，仅用于个人学习与自用
- 二次开发请保留原始版权声明与上游许可协议
