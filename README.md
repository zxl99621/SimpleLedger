# SimpleLedger 极简记账

[中文](#中文文档) · [English](#english)

一个本地优先、隐私优先的个人 Android 记账 App，基于 [蜜蜂记账 BeeCount](https://github.com/TNT-Likely/BeeCount) 二次开发，内置本地 / 云端双模式 AI。

A local-first, privacy-first personal finance app for Android, built on top of [BeeCount](https://github.com/TNT-Likely/BeeCount), with on-device and cloud AI.

- GitHub: <https://github.com/zxl99621/SimpleLedger>
- Gitee: <https://gitee.com/zxl996/simple-ledger>

---

## 中文文档

### 项目简介

SimpleLedger 是一个个人自用的极简记账工具。所有账单、标签、图片和配置都保存在手机本地，不需要账号，也不做云端同步。AI 文字能力支持两种模式：完全离线的本地 GGUF 模型，或用户自备的 OpenAI 兼容云端接口。

- 平台：Android 11+（API 30）
- 包名：`com.simpleledger.app`
- 当前版本：1.0.0

### 功能

| 模块 | 内容 |
|------|------|
| 记账 | 收入/支出、金额、分类、日期；备注、图片、多标签（折叠在「更多」）；一句话 AI 解析；图片 OCR 回填 |
| 统计 | 本周/本月/自定义；本期收支、环比上期、同比去年；支出饼图、近 6 月柱状图、分类排行、本期明细 |
| AI | 本地 GGUF / 云端 API 双模式；月度总结、消费洞察、账单问答；首次使用引导 |
| 数据 | 数据库+图片 zip 完整备份/恢复；CSV 导入导出；一键清空账单 |
| 桌面 | 4×2 横版「本月支出」小组件，点击直接进入支出记账；长按图标拍照/相册快捷记账 |
| 界面 | 5 Tab（首页·统计·记账·AI·设置）、青绿色主题、浅色/深色/跟随系统、字体大小、总资产显示开关 |

### 技术栈

- Flutter 3.x + Dart 3
- Riverpod（状态管理）
- Drift + SQLite（本地持久化）
- fl_chart（图表）
- llama.cpp（`llama_flutter_android` 插件）+ GGUF（本地推理）
- OpenAI 兼容 HTTP API（云端推理）
- `flutter_secure_storage`（Android Keystore 加密存储 API Key）

### 目录结构

```text
SimpleLedger/
├── android/                 # Android 工程与 4×2 小组件
├── assets/                  # 图片、图标等资源
├── docs/                    # 蓝皮书与项目详细说明
├── lib/
│   ├── ai/simple/           # 双模式 AI：引擎、配置、模型下载、业务提示词
│   ├── pages/               # 首页、统计、记账、AI、设置、首次启动
│   ├── data/                # Drift 数据库与 Repository
│   ├── providers/           # Riverpod providers
│   ├── services/            # 备份、附件、系统服务
│   ├── widget/              # 桌面小组件数据与渲染
│   ├── styles/ theme.dart   # 主题与 Design Token
│   └── main.dart
├── packages/                # 本地 path 依赖
├── test/                    # 单元测试
├── pubspec.yaml
└── README.md
```

> 内部 Dart 包名与 Android namespace 仍保留 `beecount`，这是二次开发的历史兼容命名；对外品牌与包名为 SimpleLedger / `com.simpleledger.app`。

### 构建

已验证环境：

| 项 | 版本 |
|----|------|
| Flutter | 3.47.7 stable |
| Dart | 3.13.5 |
| JDK | 17（Zulu） |
| Gradle | 8.14.3 |
| Kotlin | 2.2.20 |
| NDK | 28.2.13676358 |
| Android SDK | 36 |

```bash
flutter pub get
flutter build apk --release --flavor prod --target-platform android-arm64
```

产物：`build/app/outputs/flutter-apk/app-prod-release.apk`（约 23 MB）。

开发调试：

```bash
flutter run --debug --flavor dev
```

如果使用 JDK 17 但 Flutter 自动选中了 Android Studio 自带的高版本 JDK：

```bash
flutter config --jdk-dir="C:\Program Files\Zulu\zulu-17"
```

国内网络可配置：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### AI 配置

**云端模式**（设置 → AI 设置 → 云端 API）：

- 接口地址：需包含版本路径，例如 `https://api.deepseek.com/v1`
- 模型名：例如 `deepseek-chat`
- API Key：通过 Android Keystore 加密后存入本地

兼容 DeepSeek、通义千问、智谱 GLM、Moonshot、OpenAI 等提供 OpenAI 兼容接口的服务商。

**本地模式**（设置 → AI 设置 → 本地模型）：

| 模型 | 量化 | 体积 | 推荐用途 |
|------|------|------|----------|
| Qwen3 0.6B | Q8_0 | 约 610 MB | 快速记账解析，低性能设备 |
| Qwen3 1.7B | Q8_0 | 约 1.75 GB | 均衡，总结与问答 |
| Qwen3 4B | Q4_K_M | 约 2.38 GB | 高质量洞察与复杂问答 |

- 下载源：ModelScope（国内推荐）/ Hugging Face / 自定义 URL
- 模型保存在 App 私有目录，卸载 App 时自动删除
- 模型不打包进 APK，需要用户主动下载

**图片 OCR**：始终走云端视觉模型，独立开关，与文字推理模式无关；需要一个支持视觉输入的模型。

> 注：蓝皮书原写 Qwen3 1.5B/3B，但 Qwen3 官方实际尺寸为 0.6B / 1.7B / 4B，本项目采用实际可用尺寸。

### 数据与隐私

- 账单、标签、图片、配置全部保存在 App 私有目录
- 云端模式仅在用户主动触发 AI / OCR 时发送当前功能必需的文本或图片
- 本地模式不联网，账单数据不出设备
- 完整备份为 zip（SQLite 数据库 + 图片目录），保存在用户选择的位置
- CSV 仅用于文本迁移，不含图片

### 许可证与上游

本项目基于 [蜜蜂记账 BeeCount](https://github.com/TNT-Likely/BeeCount) 二次开发：

- 上游许可证为 **BeeCount 软件许可协议**（非标准 BSL）：个人学习与非营利使用免费；商业使用需获得上游作者书面授权
- 本项目作为衍生作品，沿用相同的非商业限制，仅用于个人学习与自用
- 请保留原始版权声明与上游许可协议：见 [`LICENSE`](LICENSE)、[`LICENSE_EN`](LICENSE_EN)、[`COMMERCIAL_LICENSE.md`](COMMERCIAL_LICENSE.md)、[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)

本项目采用 **源码公开（source-available）** 策略，并非 OSI 定义的开源软件。

### 文档

- [项目蓝皮书](docs/极简记账App项目蓝皮书.md)：需求、架构、技术选型与开发路线
- [项目详细说明](docs/PROJECT-DETAILS.md)：功能、构建环境、模型清单与实现备注

### 已知限制

- 仅支持 Android，不支持 iOS
- 本地推理速度取决于设备性能与模型大小；首次加载需要等待
- 本地模型能力有限，复杂问答建议使用云端模式
- OCR 需要云端视觉模型；部分服务商的主模型不支持图片输入
- 已按蓝皮书裁剪：账号与云同步、多账本、预算、周期记账、多币种、日历视图、分享等

---

## English

### Overview

SimpleLedger is a minimalist personal finance app for Android. All transactions, tags, images and settings stay on the device. There is no account system and no cloud sync. Text AI can run either fully offline with a local GGUF model or through a user-supplied OpenAI-compatible API.

- Platform: Android 11+ (API 30)
- Application ID: `com.simpleledger.app`
- Version: 1.0.0

### Features

| Area | Details |
|------|---------|
| Records | Income/expense, amount, category, date; note, images and multiple tags in a collapsible "More" panel; one-line AI parsing; OCR autofill |
| Statistics | Week/month/custom range; income & expense, month-over-month and year-over-year deltas; expense pie chart, 6-month bar chart, category ranking, period details |
| AI | Local GGUF / cloud API dual mode; monthly summary, spending insights, Q&A; first-run guide |
| Data | Full zip backup/restore (database + images); CSV import/export; clear all records |
| Home screen | 4×2 "monthly spending" widget that opens expense entry on tap; long-press launcher shortcuts for camera/gallery |
| UI | Five tabs (Home · Stats · Record · AI · Settings), teal theme, light/dark/system, font size, total-asset visibility toggle |

### Tech Stack

- Flutter 3.x + Dart 3
- Riverpod
- Drift + SQLite
- fl_chart
- llama.cpp via `llama_flutter_android` + GGUF
- OpenAI-compatible HTTP API
- `flutter_secure_storage` (Android Keystore) for the API key

### Build

```bash
flutter pub get
flutter build apk --release --flavor prod --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-prod-release.apk` (about 23 MB).

Verified toolchain: Flutter 3.47.7, Dart 3.13.5, JDK 17, Gradle 8.14.3, Kotlin 2.2.20, NDK 28.2.13676358, Android SDK 36.

### AI Setup

Cloud mode needs an OpenAI-compatible base URL (including the version path, e.g. `https://api.deepseek.com/v1`), a model name and an API key. The key is encrypted with Android Keystore.

Local mode downloads Qwen3 GGUF models (0.6B / 1.7B / 4B) from ModelScope, Hugging Face or a custom URL into the app's private storage. Models are never bundled in the APK.

OCR always uses a cloud vision model and has its own toggle. It is independent of the text inference mode.

### Privacy

Transactions, tags, images and settings are stored in the app's private directory. Cloud requests are only made when the user explicitly triggers AI or OCR, and only send the data required for that action. Local mode works offline.

### License & Upstream

Based on [BeeCount](https://github.com/TNT-Likely/BeeCount). The upstream license (BeeCount Software License) allows free personal and non-profit use; commercial use requires separate written authorization. This derivative keeps the same non-commercial restriction.

This project is **source-available**, not OSI open source. See [`LICENSE`](LICENSE), [`LICENSE_EN`](LICENSE_EN) and [`COMMERCIAL_LICENSE.md`](COMMERCIAL_LICENSE.md).

### Documentation

- [Project blueprint (Chinese)](docs/极简记账App项目蓝皮书.md)
- [Detailed project notes (Chinese)](docs/PROJECT-DETAILS.md)
