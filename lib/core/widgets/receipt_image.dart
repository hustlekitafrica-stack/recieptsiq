import 'dart:io';

import 'package:flutter/material.dart';

/// Renders a receipt image whether it's a local file path or a remote URL
/// (e.g. a Supabase Storage signed URL).
class ReceiptImage extends StatelessWidget {
  final String? source;
  final double? height;
  final BoxFit fit;

  const ReceiptImage({
    super.key,
    required this.source,
    this.height,
    this.fit = BoxFit.cover,
  });

  bool get _hasImage => source != null && source!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasImage) return const SizedBox.shrink();
    final src = source!;
    final Widget image = src.startsWith('http')
        ? Image.network(src,
            height: height,
            width: double.infinity,
            fit: fit,
            errorBuilder: (_, _, _) => _placeholder())
        : (File(src).existsSync()
            ? Image.file(File(src),
                height: height, width: double.infinity, fit: fit)
            : _placeholder());

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: image,
    );
  }

  Widget _placeholder() => Container(
        height: height ?? 160,
        width: double.infinity,
        color: const Color(0xFFEFF1F5),
        alignment: Alignment.center,
        child: const Icon(Icons.receipt_long_outlined,
            size: 48, color: Color(0xFF94A3B8)),
      );
}
