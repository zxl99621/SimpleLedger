# SimpleLedger 项目说明

- 稳定版本：1.1.5（versionCode 8）
- 平台：Android 11+（API 30）
- 应用 ID：`com.simpleledger.app`
- 技术栈：Flutter 3.47.7 + Riverpod + Drift（SQLite）
- 数据策略：本地优先，无账号、无云同步
- 显示语言：简体中文
- 对外发布：GitHub Releases / Gitee 发行版

## 1. 产品范围

SimpleLedger 是面向个人使用的极简记账应用。当前版本只保留记账、统计、AI、备份与基础安全能力，其余上游功能已主动移除。

### 1.1 已实现功能

#### 记账

- 收入 / 支出两种类型
- 金额、分类、日期
- 备注、图片附件、多标签
- 一句话 AI 解析，自动填写金额、分类、日期、备注
- 图片 OCR（云端视觉模型，识别后回填金额/日期/备注）
- 相机 / 相册快捷记账：先打开编辑器并附带图片，由用户确认后保存

#### 统计

- 本周 / 本月 / 自定义时间段
- 本期收入、支出，环比上期、同比去年
- 支出 Top5 饼图、近 6 个月收支柱状图、分类排行、本期最近 20 条明细
- 「AI 解读」入口，基于确定性统计数据生成自然语言总结

#### AI

- 云端：OpenAI 兼容接口（DeepSeek、通义、智谱、Moonshot、OpenAI 等）
- 本地：Qwen3 GGUF，支持 ModelScope / Hugging Face / 自定义 URL 下载
- 本地推理当前使用 CPU；Vulkan GPU 后端为实验能力，默认关闭（部分 Mali 驱动在加载模型时会原生崩溃，稳定构建不包含该后端）
- 月度总结、消费洞察、账单问答；回答逐字流式上屏
- AI 页支持一句话记账意图分流，解析结果需用户确认后才写入账本
- 请求可停止；云端停止时会关闭 HTTP 连接，本地停止会等待原生生成循环退出
- API Key 使用 Android Keystore 加密存储
- 图片 OCR 始终使用云端视觉模型，与文字推理模式无关

#### 数据与安全

- 完整备份：数据库 + 图片附件 + 缩略图 + 自定义图标
- 仅数据库备份：账单、分类、标签、账户、设置
- 可选密码加密备份（`.slbk`）
- 恢复前校验 zip 结构、SQLite 完整性和 schema 版本
- 恢复采用暂存 + 原子替换 + 失败回滚
- 仅数据库备份恢复时保留现有图片目录
- 预计超过 512 MB 的备份在打包前拦截
- CSV 导入 / 导出
- 一键清空全部账单（保留仍被分类引用的自定义图标）
- 应用锁：PIN + 生物识别 + 自动锁定超时

#### 界面与桌面

- 5 个底部 Tab：首页 · 统计 · 记账（居中）· AI · 设置
- 浅色 / 深色 / 跟随系统
- 字体大小调节、首页总资产显示开关
- 4×2 横版「本月支出」小组件
- 小组件启动预热；首次添加时在图片未生成前显示组件预览图

### 1.2 已移除功能

以下能力由蓝皮书明确排除，代码与依赖已移除：

- 账号、云同步、多设备协作、共享账本
- 账户管理 / 预算 / 周期记账 / 日历 / 搜索页面
- 记账提醒、信用卡提醒、通知
- 截图自动识别、图片分享自动记账
- 应用内更新、打赏、年度报告、分享海报
- 多币种选择与汇率换算界面（数据库字段保留）
- 旧版 Agent / AI 对话 / 工具调用栈

## 2. 架构

### 2.1 分层

```text
lib/
├── ai/simple/     AI 引擎抽象、云端/本地实现、模型清单与下载、业务提示词
├── data/          Drift 数据库、Repository、备份服务、变更追踪
├── models/        领域模型
├── pages/         页面（首页/统计/AI/设置/记账）
├── providers/     Riverpod providers
├── services/      备份、附件、安全、系统服务
├── widget/        桌面小组件数据与渲染
├── styles/        Design Token
└── app.dart       MaterialApp 与主壳
```

### 2.2 数据层

- 数据库：SQLite，Drift，schema v33
- 主库文件：`beecount.sqlite`（文件名保持历史兼容）
- 数据库 schema、备份格式、applicationId 不做破坏性变更
- 备份内容白名单：`beecount.sqlite`、`attachments/`、`attachment_thumbs/`、`custom_icons/`

### 2.3 备份格式

完整备份：

```text
simpleledger_backup_<yyyyMMdd_HHmmss>.zip
├── beecount.sqlite
├── attachments/
├── attachment_thumbs/
└── custom_icons/
```

仅数据库备份只包含 `beecount.sqlite`。

加密备份扩展名为 `.slbk`，格式：

```text
SLBK1 | salt(16) | nonce(12) | AES-256-GCM ciphertext + tag(16)
```

- KDF：PBKDF2-HMAC-SHA256，100,000 次，32 字节密钥
- 头部同时作为 AAD 参与认证
- 密码错误或密文被篡改时拒绝恢复

## 3. 构建

### 3.1 已验证环境

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
cd F:\SimpleLedger
flutter pub get

# 调试
flutter build apk --debug --flavor dev --target-platform android-arm64
# 产物：build/app/outputs/flutter-apk/app-dev-debug.apk

# 正式发布（构建 + 剥离其它 ABI + zipalign + 重签 + 校验）
scripts/release_android.sh
# 产物：F:\SimpleLedger-dist\SimpleLedger-<版本>-release.apk

# 32 位包
ABI=armeabi-v7a scripts/release_android.sh
```

### 3.2 签名

Release 构建必须存在 `android/key.properties`（已 gitignore）：

```properties
storeFile=D:/AndroidDevCache/simpleledger-keys/simpleledger-release.p12
storePassword=***
keyAlias=simpleledger
keyPassword=***
```

- 缺少 `key.properties` 时构建直接失败，不会生成临时密钥
- 证书 SHA-256：`0D:99:FE:E1:F0:BC:DF:93:E1:56:D0:2C:AD:32:4B:9B:81:CF:B3:D2:4F:09:84:E4:7D:0E:3D:50:D2:74:AC:C2`
- 密钥丢失后已安装用户无法覆盖升级；泄露可能被签出伪冒更新
- 密钥与密码至少备份两份，放在仓库外

### 3.3 ABI 处理

`scripts/release_android.sh` 会：

1. 构建 arm64 或 armeabi-v7a release APK
2. 删除其它 ABI 的 native 资产
3. `zipalign -P 16`
4. 使用正式 key 重新签名
5. `apksigner verify --print-certs` 校验

最终 arm64 APK 约 20 MB（CPU-only，不含 `libggml-vulkan.so`），`aapt` 中 native-code 只包含 `arm64-v8a`。

### 3.4 持续集成与发布

- `.github/workflows/android-ci.yml`：push / PR 执行 analyze + test
- `.github/workflows/android-release.yml`：手动发版，需要 GitHub Secrets：
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- 本地发布：`scripts/publish_release.sh <版本>`
  - GitHub token：`repo` 权限
  - Gitee token：`projects` 权限
  - 默认读取 `D:/AndroidDevCache/github_token.txt`、`D:/AndroidDevCache/gitee_token.txt`

### 3.5 国内构建备注

- `pubspec.yaml` 的 `hooks.user_defines.sqlite3.url_pattern` 指向 `ghproxy.net`，用于 sqlite3 native assets 下载
- 镜像不可用时改为 `https://gh-proxy.com/https://github.com/...` 或配置代理
- 本地 Pub / Gradle 缓存位于 `D:\AndroidDevCache`
- `kotlin.incremental=false`：缓存跨盘符时的兼容设置

## 4. 本地模型

| 模型 | 量化 | 体积 | 推荐用途 |
|------|------|------|----------|
| Qwen3 0.6B | Q8_0 | 约 610 MB | 快速记账解析，低性能设备 |
| Qwen3 1.7B | Q8_0 | 约 1.75 GB | 均衡，总结与问答 |
| Qwen3 4B | Q4_K_M | 约 2.38 GB | 高质量洞察与复杂问答 |

- 模型保存在 App 私有目录，卸载时删除
- 不打包进 APK
- 本地推理仅支持 arm64 设备；armeabi-v7a 包只能使用云端 AI
- 下载不支持断点续传；取消后需要重新下载

## 5. 数据与隐私

- 账单、标签、图片、配置均保存在 App 私有目录
- 无需账号，默认不进行任何云同步
- 云端 AI / OCR 仅在用户主动触发时发送当前功能所需数据
- 本地 AI 模式不联网
- 备份文件由用户选择保存位置并自行保管
- 加密备份的密码无法找回

Android 权限：

| 权限 | 用途 |
|------|------|
| `INTERNET` | 云端 AI / OCR、模型下载 |
| `ACCESS_NETWORK_STATE` | 网络状态 |
| `USE_BIOMETRIC` / `USE_FINGERPRINT` | 应用锁生物识别 |

## 6. 测试与质量

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings lib   # 0 errors
flutter test --no-pub                                      # 389 passed / 1 skipped
```

当前 CI 状态：GitHub Actions 绿色。

测试重点：

- 备份加密往返、错误密码、密文篡改
- 备份内容（完整 / 仅数据库）、预估大小、仅数据库恢复保留图片
- 月份归属、饼图 Top5、AI 取消、区间查询 limit
- 本地数据库、导入导出、记账编辑器、小组件规格

## 7. 兼容性

- Android 11+（API 30），不支持 iOS
- arm64：完整功能，包括本地 GGUF
- armeabi-v7a：少数 32 位 Android 11+ 设备，云端 AI 可用
- Android 10 及以下暂不支持
- 界面为简体中文

## 8. 已知限制

- 备份/恢复仍为整文件读入内存，单文件上限 512 MB；大附件库请使用「仅数据库」
- 本地模型首次加载慢，推理速度取决于设备性能
- OCR 依赖云端视觉模型
- 应用锁 PIN、备份密码遗忘后无法恢复
- 无云同步、多设备、共享账本、预算、周期记账、多币种界面，属有意边界

## 9. 许可证与来源

- 基底项目：[蜜蜂记账 BeeCount](https://github.com/TNT-Likely/BeeCount)
- 上游许可证：BeeCount 软件许可协议（个人 / 非营利免费；商业使用需单独授权）
- 本项目沿用相同非商业限制，仅供个人学习与自用
- 二次开发请保留原始版权声明与上游许可协议
- 本项目为 source-available，并非 OSI 开源
