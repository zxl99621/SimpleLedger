# SimpleLedger 极简记账

[![Release](https://img.shields.io/github/v/release/zxl99621/SimpleLedger)](https://github.com/zxl99621/SimpleLedger/releases)
[![Android CI](https://github.com/zxl99621/SimpleLedger/actions/workflows/android-ci.yml/badge.svg)](https://github.com/zxl99621/SimpleLedger/actions/workflows/android-ci.yml)

[中文](#中文) · [English](#english)

SimpleLedger 是一个本地优先、隐私优先的个人 Android 记账应用，基于 [蜜蜂记账 BeeCount](https://github.com/TNT-Likely/BeeCount) 二次开发，围绕「极简记账 + 本地数据 + 可选 AI」重新裁剪实现。

A local-first, privacy-first personal finance app for Android, derived from [BeeCount](https://github.com/TNT-Likely/BeeCount) and rebuilt around a minimal ledger, local data ownership and optional AI.

- GitHub：<https://github.com/zxl99621/SimpleLedger>
- Gitee：<https://gitee.com/zxl996/simple-ledger>
- 当前稳定版：**1.1.5**（Android 11+ / API 30）

---

## 中文

### 下载与安装

| 平台 | 地址 |
|------|------|
| GitHub Releases | <https://github.com/zxl99621/SimpleLedger/releases> |
| Gitee 发行版 | <https://gitee.com/zxl996/simple-ledger/releases> |

每个 Release 提供：

| 文件 | 适用设备 | 说明 |
|------|----------|------|
| `SimpleLedger-<版本>-release.apk` | arm64-v8a，Android 11+ | 推荐；约 20 MB，支持本地 GGUF AI（CPU） |
| `SimpleLedger-<版本>-armeabi-v7a.apk` | 32 位，Android 11+ | 约 17 MB；云端 AI 可用，本地 GGUF 不可用 |
| `SimpleLedger-<版本>-source.zip` | — | 完整源码，可从零构建 |

安装方式：下载 APK 后直接打开，或：

```bash
adb install -r SimpleLedger-1.1.5-release.apk
```

应用升级必须使用同一签名密钥；正式包证书 SHA-256 为
`0D:99:FE:E1:F0:BC:DF:93:E1:56:D0:2C:AD:32:4B:9B:81:CF:B3:D2:4F:09:84:E4:7D:0E:3D:50:D2:74:AC:C2`。

### 功能

| 模块 | 能力 |
|------|------|
| 记账 | 收入 / 支出；金额、分类、日期；备注、图片附件、多标签；一句话 AI 解析；图片 OCR 回填 |
| 统计 | 本周 / 本月 / 自定义区间；本期收支、环比、同比；支出 Top5 饼图、近 6 个月柱状图、分类排行、本期明细 |
| AI | 云端 OpenAI 兼容接口 / 本地 Qwen3 GGUF 双模式；本地推理为 CPU（Vulkan 实验后端默认关闭）；月度总结、消费洞察、账单问答；流式回答；一句话记账需确认后写入；请求可停止 |
| 数据 | 完整备份（数据库 + 图片）或仅数据库备份；可选密码加密；原子恢复与完整性校验；CSV 导入导出；清空账单 |
| 安全 | 应用锁：PIN + 生物识别 + 自动锁定超时 |
| 桌面 | 4×2「本月支出」小组件；长按图标拍照 / 相册快捷记账 |
| 界面 | 5 个 Tab（首页 · 统计 · 记账 · AI · 设置）；浅色 / 深色 / 跟随系统；字体大小；总资产显示开关 |

### 设计取舍

本项目按蓝皮书主动移除了以下能力，以保持极简和可控：

- 账号、云同步、多设备协作、共享账本
- 账户管理、预算、周期记账、日历视图、搜索页
- 记账提醒、信用卡提醒、截图自动识别、图片分享自动记账
- 应用内更新、打赏、年度报告、分享海报
- 多币种选择 / 汇率换算界面（数据库字段保留，历史账单仍按原币种显示）
- 旧版 Agent / AI 对话 / 工具调用栈

### 技术架构

- Flutter 3.47.7 / Dart 3.13.5
- Riverpod 状态管理
- Drift + SQLite 本地持久化（schema v33）
- fl_chart 图表
- `llama_flutter_android` + Qwen3 GGUF 本地推理（仅 arm64）
- OpenAI 兼容 HTTP API 云端推理
- `flutter_secure_storage`（Android Keystore）保存 API Key
- PBKDF2-HMAC-SHA256 + AES-256-GCM 备份加密

### 目录结构

```text
SimpleLedger/
├── android/              # Android 工程、原生小组件
├── assets/               # 图标与图片资源
├── docs/                 # 蓝皮书、项目说明、发布说明
├── lib/
│   ├── ai/simple/        # AI 引擎、配置、模型下载、业务提示词
│   ├── data/             # Drift 数据库、Repository、备份服务
│   ├── l10n/             # 简体中文本地化
│   ├── models/           # 领域模型
│   ├── pages/            # 首页、统计、AI、设置、记账编辑器
│   ├── providers/        # Riverpod providers
│   ├── services/         # 备份、附件、安全、系统服务
│   ├── widget/           # 桌面小组件数据与渲染
│   ├── styles/           # Design Token
│   ├── app.dart / main.dart
├── scripts/              # 构建、发布、发布说明脚本
├── test/                 # 单元 / 组件测试
└── pubspec.yaml
```

> 内部 Dart 包名与 Android namespace 仍为 `beecount`，属于上游历史兼容命名；对外品牌与 applicationId 为 SimpleLedger / `com.simpleledger.app`。

### 构建

已验证环境：

| 项 | 版本 |
|----|------|
| Flutter | 3.47.7 stable |
| Dart | 3.13.5 |
| JDK | Zulu 17 |
| Gradle | 8.14.3 |
| Kotlin | 2.2.20 |
| NDK | 28.2.13676358 |
| Android SDK | API 36 |

```bash
flutter pub get

# 调试
flutter build apk --debug --flavor dev --target-platform android-arm64
# 产物：build/app/outputs/flutter-apk/app-dev-debug.apk

# 正式发布（自动剥离其它 ABI、zipalign、重签、校验）
scripts/release_android.sh
# 产物：F:\SimpleLedger-dist\SimpleLedger-<版本>-release.apk

# 32 位发布包
ABI=armeabi-v7a scripts/release_android.sh
```

Release 构建必须提供 `android/key.properties`（已 gitignore）：

```properties
storeFile=D:/AndroidDevCache/simpleledger-keys/simpleledger-release.p12
storePassword=***
keyAlias=simpleledger
keyPassword=***
```

缺少 `key.properties` 时 release 构建直接失败，不会自动生成临时密钥。密钥与密码必须放在仓库外并至少备份两份。

国内网络可在 `pubspec.yaml` 的 `hooks.user_defines.sqlite3.url_pattern` 指定镜像；Flutter 包源可通过 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` 配置。

### 测试与持续集成

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings lib   # 0 errors
flutter test --no-pub                                      # 389 passed / 1 skipped
```

GitHub Actions：

- `.github/workflows/android-ci.yml`：push / PR 自动执行 analyze + test
- `.github/workflows/android-release.yml`：手动发版（需配置 keystore 相关 secrets）

本地发布脚本：

```bash
scripts/publish_release.sh 1.1.5
```

需要 GitHub token（`repo` 权限）与 Gitee token（`projects` 权限），默认从
`D:/AndroidDevCache/github_token.txt`、`D:/AndroidDevCache/gitee_token.txt` 读取。

### AI 配置

**云端模式**：AI 页 → 设置 → 选择「云端 API」，填写接口地址（含 `/v1` 等版本路径）、模型名和 API Key。兼容 DeepSeek、通义千问、智谱 GLM、Moonshot、OpenAI 等 OpenAI 兼容服务。

**本地模式**：AI 页 → 设置 → 选择「本地模型」，下载 Qwen3 GGUF：

| 模型 | 量化 | 体积 | 推荐用途 |
|------|------|------|----------|
| Qwen3 0.6B | Q8_0 | 约 610 MB | 快速记账解析 |
| Qwen3 1.7B | Q8_0 | 约 1.75 GB | 总结与问答 |
| Qwen3 4B | Q4_K_M | 约 2.38 GB | 高质量洞察 |

模型下载源支持 ModelScope / Hugging Face / 自定义 URL，保存在 App 私有目录，不打包进 APK。本地推理仅支持 arm64 设备，当前稳定构建使用 CPU；Vulkan GPU 后端作为实验能力默认关闭（部分 Mali 驱动会在加载模型时崩溃，稳定包不包含该后端）。

**图片 OCR**：始终使用云端视觉模型，与文字推理模式无关；需要支持图片输入的模型。

### 数据、备份与隐私

- 所有账单、标签、图片、配置保存在 App 私有目录，无需账号，默认不联网同步。
- 云端 AI / OCR 仅在用户主动触发时发送当前功能所需文本或图片。
- 备份支持两种模式：
  - **完整备份**：SQLite 数据库 + 图片附件 + 缩略图 + 自定义图标
  - **仅数据库**：账单、分类、标签、账户、设置，文件通常只有几 MB
- 备份可选密码加密：PBKDF2-HMAC-SHA256（10 万次）+ AES-256-GCM，扩展名 `.slbk`。
- 恢复前校验 SQLite 完整性和 schema 版本；恢复采用暂存 + 原子替换 + 失败回滚。
- 仅数据库备份恢复时保留现有图片目录。
- 预计超过 512 MB 的备份会在打包前被拦截，需改用「仅数据库」或先清理附件。
- CSV 仅迁移文本数据，不包含图片。

Android 权限仅保留：`INTERNET`、`ACCESS_NETWORK_STATE`、`USE_BIOMETRIC`、`USE_FINGERPRINT`。

### 兼容性

- Android 11+（API 30），不支持 iOS。
- arm64 包支持完整功能，包括本地 GGUF 模型。
- armeabi-v7a 包覆盖少数 32 位 Android 11+ 设备；本地 GGUF 不可用，云端 AI 正常。
- Android 10 及以下暂不支持。

### 已知限制

- 备份/恢复仍会把整个 zip 读入内存，单文件上限 512 MB；超大附件库请使用「仅数据库」。
- 本地模型首次加载较慢，推理速度取决于设备性能。
- OCR 依赖云端视觉模型，部分服务商主模型不支持图片输入。
- 应用锁 PIN 与备份密码一旦遗忘无法恢复。
- 无云同步、多设备、共享账本、预算、周期记账、多币种界面，这是有意的产品边界。

### 许可证与上游

基于 [蜜蜂记账 BeeCount](https://github.com/TNT-Likely/BeeCount) 二次开发。上游采用 BeeCount 软件许可协议：个人与非营利使用免费，商业使用需获得上游作者书面授权。本项目沿用相同的非商业限制。

本项目为 **源码公开（source-available）**，并非 OSI 定义的开源软件。请保留 [`LICENSE`](LICENSE)、[`LICENSE_EN`](LICENSE_EN)、[`COMMERCIAL_LICENSE.md`](COMMERCIAL_LICENSE.md) 与 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

### 文档

- [项目蓝皮书](docs/极简记账App项目蓝皮书.md)：需求与冻结决策
- [项目详细说明](docs/PROJECT-DETAILS.md)：实现、构建、发布与数据说明
- [更新记录](CHANGELOG.md)

---

## English

### Download

- GitHub Releases: <https://github.com/zxl99621/SimpleLedger/releases>
- Gitee Releases: <https://gitee.com/zxl996/simple-ledger/releases>

Each release ships:

- `SimpleLedger-<version>-release.apk` — arm64-v8a, Android 11+, ~20 MB, full features including local GGUF AI (CPU)
- `SimpleLedger-<version>-armeabi-v7a.apk` — 32-bit, Android 11+, ~17 MB, cloud AI only
- `SimpleLedger-<version>-source.zip` — complete source tree

Install with `adb install -r <apk>` or by opening the APK on the device. Upgrades require the same signing key.

### Features

- Records: income/expense, amount, category, date, note, image attachments, tags, one-line AI parsing, OCR autofill
- Statistics: week/month/custom range; income and expense; MoM/YoY deltas; expense Top-5 pie, 6-month bars, category ranking, period details
- AI: OpenAI-compatible cloud API or local Qwen3 GGUF; monthly summary, spending insights, ledger Q&A; cancellable requests
- Data: full or database-only backup, optional password encryption, atomic restore with integrity checks, CSV import/export, clear-all
- Security: app lock with PIN, biometrics and timeout
- Home screen: 4×2 monthly-spending widget; camera/gallery quick entry
- UI: five tabs, light/dark/system themes, font scaling, total-asset visibility

### Architecture

Flutter 3.47.7, Riverpod, Drift/SQLite, fl_chart, llama.cpp via `llama_flutter_android`, OpenAI-compatible HTTP APIs, Android Keystore for API keys, PBKDF2 + AES-256-GCM for encrypted backups. The database schema (v33), backup format and application ID are kept stable for upgrade compatibility.

### Build

```bash
flutter pub get
scripts/release_android.sh          # arm64; strip other ABIs, zipalign, sign
ABI=armeabi-v7a scripts/release_android.sh
```

Release builds require `android/key.properties`; without it the build fails instead of falling back to a temporary key.

### Verification

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings lib   # 0 errors
flutter test --no-pub                                      # 389 passed / 1 skipped
```

CI runs on every push/PR via `.github/workflows/android-ci.yml`.

### Privacy

Data stays in the app's private directory. There is no account system and no cloud sync. Cloud AI/OCR requests are only sent when explicitly triggered and contain only the data required for that request. Android permissions are limited to network access and biometric authentication.

### Compatibility and limits

Android 11+ only; arm64 is recommended and is required for local GGUF inference. The 512 MB backup limit remains; use database-only backups for very large attachment libraries. The UI is Simplified Chinese only.

### License

Based on [BeeCount](https://github.com/TNT-Likely/BeeCount). The upstream BeeCount Software License permits free personal and non-profit use; commercial use requires separate written authorization. This derivative keeps the same non-commercial restriction and is source-available, not OSI open source.
