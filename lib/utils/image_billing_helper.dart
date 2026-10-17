import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../pages/transaction/transaction_editor_page.dart';
import '../providers.dart';
import '../services/image/billing_image_service.dart';

/// 拍照/相册快捷记账：只负责选图，然后打开记账编辑器。
///
/// 图片会挂为待上传附件，金额面板再用简单 OCR 自动回填；不再走旧版
/// Agent 自动入库，避免“没确认就生成账单”。
class ImageBillingHelper {
  static Future<void> pickImageForBilling(
    BuildContext context,
    WidgetRef ref,
  ) =>
      _openEditorWithImage(context, ref, ImageSource.gallery);

  static Future<void> openCameraForBilling(
    BuildContext context,
    WidgetRef ref,
  ) =>
      _openEditorWithImage(context, ref, ImageSource.camera);

  static Future<void> _openEditorWithImage(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final keepOriginal = await ref.read(attachmentKeepOriginalProvider.future);
    final imageService = BillingImageService();
    final file = await imageService.pickImage(source, keepOriginal: keepOriginal);
    if (file == null || !context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: 'expense',
          quickAdd: true,
          initialImageFile: file,
        ),
      ),
    );
  }
}
