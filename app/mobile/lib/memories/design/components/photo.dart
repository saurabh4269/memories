import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/components/shimmer.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:openapi/api.dart';

/// Where a Memories photo comes from. Real pictures only: an Immich asset,
/// a network URL (director reel covers) or a bundled festive photo.
sealed class MPhotoSource {
  const MPhotoSource();

  /// Immich asset thumbnail (small, for grids) or preview (large, for heroes).
  const factory MPhotoSource.immich(String assetId, {bool large, String? thumbhash}) = ImmichPhotoSource;
  const factory MPhotoSource.network(String url) = NetworkPhotoSource;
  const factory MPhotoSource.asset(String path) = AssetPhotoSource;

  ImageProvider? provider();
}

class ImmichPhotoSource extends MPhotoSource {
  final String assetId;
  final bool large;
  final String? thumbhash;
  const ImmichPhotoSource(this.assetId, {this.large = false, this.thumbhash});

  @override
  ImageProvider? provider() {
    if (assetId.isEmpty) return null;
    try {
      if (large) {
        return RemoteImageProvider(url: getThumbnailUrlForRemoteId(assetId, type: AssetMediaSize.preview));
      }
      return RemoteImageProvider.thumbnail(assetId: assetId, thumbhash: thumbhash ?? '');
    } catch (_) {
      return null;
    }
  }
}

class NetworkPhotoSource extends MPhotoSource {
  final String url;
  const NetworkPhotoSource(this.url);
  @override
  ImageProvider? provider() => url.isEmpty ? null : NetworkImage(url);
}

class AssetPhotoSource extends MPhotoSource {
  final String path;
  const AssetPhotoSource(this.path);
  @override
  ImageProvider? provider() => AssetImage(path);
}

/// Bundled festive photos for onboarding and empty states (see assets/memories/CREDITS.md).
abstract final class MStockPhotos {
  static const diwali = MPhotoSource.asset('assets/memories/diwali_diyas.jpg');
  static const holi = MPhotoSource.asset('assets/memories/holi_colours.jpg');
  static const marigold = MPhotoSource.asset('assets/memories/marigold.jpg');
}

/// Renders an [MPhotoSource] with a shimmer while loading and a warm fallback on error.
class MPhoto extends StatelessWidget {
  final MPhotoSource? source;
  final BoxFit fit;
  final Alignment alignment;
  final MPhotoSource? fallback;

  const MPhoto({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final provider = source?.provider() ?? fallback?.provider();
    if (provider == null) {
      return const ShimmerPlaceholder(borderRadius: BorderRadius.zero, animate: false);
    }
    return Image(
      image: provider,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: frame == null
              ? const ShimmerPlaceholder(key: ValueKey('loading'), borderRadius: BorderRadius.zero)
              : KeyedSubtree(key: const ValueKey('img'), child: child),
        );
      },
      errorBuilder: (context, error, stack) {
        final fb = fallback?.provider();
        if (fb != null && fb != provider) {
          return Image(image: fb, fit: fit, alignment: alignment);
        }
        return const ShimmerPlaceholder(borderRadius: BorderRadius.zero, animate: false);
      },
    );
  }
}
