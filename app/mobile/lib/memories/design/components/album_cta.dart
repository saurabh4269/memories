import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/components/basics.dart';
import 'package:immich_mobile/memories/design/components/photo.dart';
import 'package:immich_mobile/memories/design/theme.dart';
import 'package:immich_mobile/memories/design/tokens.dart';
import 'package:immich_mobile/memories/design/typography.dart';

/// Premium "Make my Memories reel" hero for the top of an album page.
class MemoriesAlbumCta extends StatelessWidget {
  final String? coverAssetId;
  final int assetCount;
  final VoidCallback onMake;
  final VoidCallback? onCamera;
  final VoidCallback? onInvite;

  const MemoriesAlbumCta({
    super.key,
    required this.coverAssetId,
    required this.assetCount,
    required this.onMake,
    this.onCamera,
    this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return MemoriesTheme(
      child: Builder(
        builder: (context) {
          final p = MemoriesPalette.of(context);
          final type = MemoriesType.of(p);
          return Padding(
            padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.xs, MSpace.md, MSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  label: 'Make my Memories reel',
                  child: DecoratedBox(
                    decoration: BoxDecoration(borderRadius: MRadius.lgAll, boxShadow: MElevation.e2(p)),
                    child: ClipRRect(
                      borderRadius: MRadius.lgAll,
                      child: Material(
                        color: const Color(0xFF1D1A38),
                        child: InkWell(
                          onTap: onMake,
                          child: SizedBox(
                            height: 168,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(
                                  left: 120,
                                  child: MPhoto(
                                    source: coverAssetId == null
                                        ? MStockPhotos.diwali
                                        : MPhotoSource.immich(coverAssetId!, large: true),
                                    fallback: MStockPhotos.diwali,
                                  ),
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      stops: [0.0, 0.42, 1.0],
                                      colors: [Color(0xFF1D1A38), Color(0xE61D1A38), Color(0x261D1A38)],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(MSpace.lg),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const DirectorSpark(size: 14, color: Color(0xFFF7B23B)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'YOUR DIRECTOR',
                                            style: type.overline.copyWith(color: const Color(0xFFFFD58A)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Make my\nMemories reel',
                                        style: type.title.copyWith(color: Colors.white, fontSize: 25, height: 1.1),
                                      ),
                                      const Spacer(),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              assetCount > 0
                                                  ? 'Speak it. Two reels from $assetCount moments.'
                                                  : 'Speak it. Get two post-ready reels.',
                                              maxLines: 2,
                                              style: type.label.copyWith(
                                                color: Colors.white.withValues(alpha: 0.85),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: MSpace.sm),
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: p.marigold,
                                              shape: BoxShape.circle,
                                              boxShadow: MElevation.glow(p),
                                            ),
                                            child: Icon(Icons.mic_rounded, color: p.onMarigold, size: 24),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (onCamera != null || onInvite != null) ...[
                  const SizedBox(height: MSpace.sm),
                  Row(
                    children: [
                      if (onCamera != null)
                        Expanded(
                          child: PillButton.secondary(
                            label: 'Camera',
                            icon: Icons.photo_camera_rounded,
                            onPressed: onCamera,
                            height: 52,
                          ),
                        ),
                      if (onCamera != null && onInvite != null) const SizedBox(width: MSpace.sm),
                      if (onInvite != null)
                        Expanded(
                          child: PillButton.secondary(
                            label: 'Invite family',
                            icon: Icons.qr_code_2_rounded,
                            onPressed: onInvite,
                            height: 52,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
