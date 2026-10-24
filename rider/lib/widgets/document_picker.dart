import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single "pick a document photo" row — the signup screen's profile
/// photo/driving-license/ID-proof pickers, and the Account Setting
/// screen's re-upload pickers, share this exact widget so both look and
/// behave identically.
class DocumentPicker extends StatelessWidget {
  const DocumentPicker({
    super.key,
    required this.label,
    required this.file,
    required this.onPick,
    required this.onRemove,
    this.existingImageUrl,
  });

  final String label;

  /// A freshly picked local file, if the rider has chosen a replacement
  /// this session.
  final File? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  /// The document already on file server-side (e.g. from a previous
  /// upload) — shown as the thumbnail until [file] replaces it. Signup
  /// has nothing to show here yet, so it's optional.
  final String? existingImageUrl;

  @override
  Widget build(BuildContext context) {
    final hasSelection = file != null;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _Thumbnail(file: file, existingImageUrl: existingImageUrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ),
            if (hasSelection)
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                tooltip: 'upload.remove'.tr(),
                onPressed: onRemove,
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.file, this.existingImageUrl});

  final File? file;
  final String? existingImageUrl;

  @override
  Widget build(BuildContext context) {
    if (file != null) {
      return Image.file(file!, height: 44, width: 44, fit: BoxFit.cover);
    }

    if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      return Image.network(
        existingImageUrl!,
        height: 44,
        width: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const _PlaceholderThumbnail(),
      );
    }

    return const _PlaceholderThumbnail();
  }
}

class _PlaceholderThumbnail extends StatelessWidget {
  const _PlaceholderThumbnail();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: 44,
      color: AppColors.background,
      child: const Icon(Icons.upload_file_outlined, color: AppColors.textSecondary, size: 20),
    );
  }
}
