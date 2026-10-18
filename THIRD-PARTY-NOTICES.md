# 第三方组件声明 / Third-Party Notices

除下方「Vendored components」列出的组件外，本仓库源码**不包含（vendor）任何第三方库的源代码**。其余第三方依赖由 `pubspec.yaml` / `pubspec.lock` 声明，在构建时经 pub 从官方源获取，各自按其原始开源协议授权，与本项目的 [LICENSE](LICENSE)（双许可）相互独立。使用、分发或基于本项目二次开发时，请一并遵守下列组件各自的协议。

`packages/` 目录下的 `flutter_ai_kit*` 与 `flutter_cloud_sync*` 系列为本项目自研组件，属许可软件本体、受项目 LICENSE 约束，**不属于第三方组件**。

## Vendored components

- `packages/llama_flutter_android` — MIT，Copyright (c) 2025 dragneel2074；本项目在其基础上启用了 Vulkan 后端。
  - 其中 `android/src/main/cpp/llama.cpp` — MIT，Copyright (c) 2023-2026 The ggml authors。
  - `third_party/vulkan`（Vulkan-Headers）— Khronos 许可（Apache-2.0 / MIT 混合），见该目录 `LICENSE.md`。
  - `third_party/spirv`（SPIRV-Headers）— Khronos 许可（MIT 为主），见该目录 `LICENSE`。

> 以下清单基于各包发布物中的 LICENSE 文本核验（2026-07 整理，共 51 个第三方直接依赖，**无 GPL / LGPL / AGPL 项**）。传递依赖可用 `flutter pub deps` 查看；如与上游申明不符，以上游为准。
>
> **English**: Except for the components listed under "Vendored components" above, this repository does **not vendor** any third-party source code. All other dependencies are declared in `pubspec.yaml` / `pubspec.lock` and fetched by pub at build time under their own licenses, independent of this project's dual [LICENSE](LICENSE_EN). First-party packages under `packages/` (`flutter_ai_kit*`, `flutter_cloud_sync*`) are covered by the project LICENSE. The list below was verified against each package's published LICENSE text (as of 2026-07, 51 direct third-party dependencies, **no GPL / LGPL / AGPL**); upstream prevails in case of discrepancy.

## 直接依赖 / Direct dependencies

**Flutter SDK / flutter_localizations** — BSD-3-Clause

**MIT（20）**
archive · country_flags · csv · dio · drift · excel · file_picker · fl_chart · flutter_image_compress · flutter_list_view · flutter_riverpod · flutter_svg · gbk_codec · in_app_review · permission_handler · reorderable_grid_view · sqlite3_flutter_libs · supabase_flutter · uuid · yaml

**BSD-3-Clause（26）**
collection · connectivity_plus · crypto · flutter_local_notifications · gal · home_widget · http · image_cropper · in_app_purchase · in_app_purchase_storekit · intl · jovial_svg · local_auth · open_filex · package_info_plus · path · path_provider · qr_flutter · quick_actions · record · share_plus · shared_preferences · url_launcher · visibility_detector · webview_flutter · webview_flutter_wkwebview

**Apache-2.0（4）**
app_links · decimal · image_picker · table_calendar

**BSD-2-Clause（1）**
timezone

---

如发现本清单与上游实际协议不符，欢迎提 Issue 指正。
