import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cache manager for receipt images with optimized settings
final _receiptCacheManager = CacheManager(
  Config(
    'receiptImages',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 200,
    repo: JsonCacheInfoRepository(databaseName: 'receipt_images'),
    fileService: HttpFileService(),
  ),
);

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
        ? CachedNetworkImage(
            imageUrl: src,
            height: height,
            width: double.infinity,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 300),
            placeholder: (_, __) => _ShimmerPlaceholder(height: height),
            errorWidget: (_, __, ___) => _placeholder(),
            cacheManager: _receiptCacheManager,
          )
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

/// Shimmer animation placeholder shown while receipt image is loading.
class _ShimmerPlaceholder extends StatefulWidget {
  final double? height;

  const _ShimmerPlaceholder({this.height});

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height ?? 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF1F5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // Shimmer gradient overlay
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFFEFF1F5),
                        const Color(0xFFEFF1F5).withValues(alpha: 0.8),
                        const Color(0xFFEFF1F5),
                      ],
                      stops: [
                        0.0,
                        0.5,
                        1.0,
                      ],
                      transform: SlidingGradientTransform(
                        slidePercent: _animation.value,
                      ),
                    ).createShader(bounds);
                  },
                  child: Container(
                    width: double.infinity,
                    height: widget.height ?? 160,
                    color: Colors.white,
                  ),
                ),
              ),
              // Receipt icon centered
              Center(
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 48,
                  color: const Color(0xFF94A3B8).withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Helper to create a sliding gradient effect for shimmer animation.
class SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}
