import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/memories/design/design.dart';
import 'package:immich_mobile/memories/home/recent_reels.dart';
import 'package:immich_mobile/presentation/pages/make_reel.page.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';

/// Opens the Memories home with a plain Navigator push (no route codegen needed).
Future<void> openMemoriesHome(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MemoriesHomePage()));

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class _MonthBucket {
  final int year;
  final int month;
  final List<RemoteAsset> assets;
  _MonthBucket(this.year, this.month, this.assets);
}

class MemoriesHomePage extends ConsumerStatefulWidget {
  const MemoriesHomePage({super.key});

  @override
  ConsumerState<MemoriesHomePage> createState() => _MemoriesHomePageState();
}

class _MemoriesHomePageState extends ConsumerState<MemoriesHomePage> {
  Future<List<_MonthBucket>>? _year;
  String _yearKey = '';
  bool _refreshing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      await ref.read(remoteAlbumProvider.notifier).refresh();
    } catch (_) {
      // offline: show what we have locally
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<RemoteAlbum> _sorted(List<RemoteAlbum> albums) {
    final list = albums.where((a) => a.assetCount > 0).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<List<_MonthBucket>> _loadYear(List<RemoteAlbum> albums) async {
    final notifier = ref.read(remoteAlbumProvider.notifier);
    final seen = <String>{};
    final all = <RemoteAsset>[];
    for (final album in albums.take(6)) {
      try {
        for (final a in await notifier.getAssets(album.id)) {
          if (seen.add(a.id)) all.add(a);
        }
      } catch (_) {}
    }
    if (all.isEmpty) return const [];
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final year = all.first.createdAt.toLocal().year;
    final buckets = <int, _MonthBucket>{};
    for (final a in all) {
      final d = a.createdAt.toLocal();
      if (d.year != year) continue;
      buckets.putIfAbsent(d.month, () => _MonthBucket(d.year, d.month, [])).assets.add(a);
    }
    return buckets.values.toList()..sort((a, b) => b.month.compareTo(a.month));
  }

  void _makeMemory(RemoteAlbum album) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MakeReelPage(albumId: album.id, albumName: album.name),
        ),
      ),
    );
  }

  void _openAlbum(RemoteAlbum album) => unawaited(context.pushRoute(RemoteAlbumRoute(album: album)));

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'just now';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day} ${_months[t.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return MemoriesTheme(child: Builder(builder: _buildBody));
  }

  Widget _buildBody(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final albums = _sorted(ref.watch(remoteAlbumProvider.select((s) => s.albums)));
    final user = ref.watch(currentUserProvider);
    final firstName = (user?.name ?? '').split(' ').first;
    final now = DateTime.now();

    final key = albums.map((a) => '${a.id}:${a.assetCount}').join(',');
    if (key != _yearKey && albums.isNotEmpty) {
      _yearKey = key;
      _year = _loadYear(albums);
    }

    final hero = albums.isEmpty ? null : albums.first;
    final others = albums.length > 1 ? albums.sublist(1) : const <RemoteAlbum>[];

    return Scaffold(
      body: RefreshIndicator(
        color: p.diya,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              toolbarHeight: 64,
              automaticallyImplyLeading: false,
              titleSpacing: MSpace.gutter,
              title: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                  const DirectorSpark(size: 20),
                  const SizedBox(width: 8),
                  Text('Memories', style: type.title.copyWith(fontSize: 24)),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(MSpace.gutter, MSpace.xs, MSpace.gutter, MSpace.lg),
              sliver: SliverToBoxAdapter(
                child: FadeRise(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_weekdays[now.weekday - 1]} · ${now.day} ${_months[now.month - 1]}'.toUpperCase(),
                        style: type.overline,
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: firstName.isEmpty ? 'Namaste' : 'Namaste, ', style: type.headline),
                            if (firstName.isNotEmpty)
                              TextSpan(
                                text: firstName,
                                style: type.headline.copyWith(
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w400,
                                  color: p.isDark ? p.marigold : p.plum,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: MSpace.gutter),
              sliver: SliverToBoxAdapter(
                child: FadeRise(
                  index: 1,
                  child: hero == null
                      ? (_refreshing
                            ? const AspectRatio(
                                aspectRatio: 4 / 5,
                                child: ShimmerPlaceholder(borderRadius: MRadius.xlAll),
                              )
                            : EmptyState(
                                title: 'Your first event awaits',
                                message:
                                    'Start an album for the festival and invite the family. Everyone shoots, we make the film.',
                              ))
                      : PhotoHeroCard(
                          photo: MPhotoSource.immich(hero.thumbnailAssetId ?? '', large: true),
                          kicker: 'Latest event',
                          title: hero.name,
                          subtitle: '${hero.assetCount} photos & videos · ${_ago(hero.updatedAt)}',
                          chips: [
                            if (hero.isShared) const FrostedChip(icon: Icons.groups_rounded, label: 'Family album'),
                          ],
                          onTap: () => _openAlbum(hero),
                          action: PillButton(
                            label: 'Make a memory',
                            icon: Icons.auto_awesome_rounded,
                            glow: true,
                            onPressed: () => _makeMemory(hero),
                          ),
                        ),
                ),
              ),
            ),
            if (others.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: MSpace.section)),
              SliverToBoxAdapter(
                child: SectionHeader(kicker: '${albums.length} albums', title: 'Your events'),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: MSpace.md)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.gutter),
                    itemCount: others.length,
                    separatorBuilder: (_, _) => const SizedBox(width: MSpace.sm),
                    itemBuilder: (context, i) {
                      final a = others[i];
                      return FadeRise(
                        index: i,
                        child: MemoryAlbumCard(
                          cover: MPhotoSource.immich(a.thumbnailAssetId ?? ''),
                          title: a.name,
                          meta: '${a.assetCount} items',
                          onTap: () => _openAlbum(a),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: MSpace.section)),
            SliverToBoxAdapter(child: _YearStrip(future: _year)),
            const SliverToBoxAdapter(child: SizedBox(height: MSpace.section)),
            SliverToBoxAdapter(
              child: ValueListenableBuilder<List<RecentReel>>(
                valueListenable: recentReels,
                builder: (context, reels, _) =>
                    _RecentReels(reels: reels, onMake: hero == null ? null : () => _makeMemory(hero)),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: MSpace.xxxl)),
          ],
        ),
      ),
    );
  }
}

class _YearStrip extends StatelessWidget {
  final Future<List<_MonthBucket>>? future;
  const _YearStrip({required this.future});

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return FutureBuilder<List<_MonthBucket>>(
      future: future,
      builder: (context, snap) {
        final buckets = snap.data ?? const <_MonthBucket>[];
        final loading = snap.connectionState != ConnectionState.done;
        if (!loading && buckets.isEmpty) return const SizedBox.shrink();
        final year = buckets.isNotEmpty ? buckets.first.year : DateTime.now().year;
        final total = buckets.fold<int>(0, (s, b) => s + b.assets.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(kicker: loading ? 'Archive' : '$total moments', title: 'Your year · $year'),
            const SizedBox(height: MSpace.md),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: MSpace.gutter),
                itemCount: loading ? 4 : buckets.length,
                separatorBuilder: (_, _) => const SizedBox(width: MSpace.sm),
                itemBuilder: (context, i) {
                  if (loading) {
                    return const ShimmerPlaceholder(width: 120, height: 168, borderRadius: MRadius.lgAll);
                  }
                  final b = buckets[i];
                  final cover = b.assets.first;
                  return FadeRise(
                    index: i,
                    child: SizedBox(
                      width: 120,
                      child: ClipRRect(
                        borderRadius: MRadius.lgAll,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MPhoto(source: MPhotoSource.immich(cover.id, thumbhash: cover.thumbHash)),
                            const DecoratedBox(decoration: BoxDecoration(gradient: kPhotoScrim)),
                            Positioned(
                              left: 12,
                              bottom: 10,
                              right: 8,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _months[b.month - 1],
                                    style: type.display.copyWith(color: Colors.white, fontSize: 30, height: 1),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${b.assets.length} moments',
                                    style: type.label.copyWith(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentReels extends StatelessWidget {
  final List<RecentReel> reels;
  final VoidCallback? onMake;
  const _RecentReels({required this.reels, required this.onMake});

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(kicker: 'Made by the director', title: 'Recent reels'),
        const SizedBox(height: MSpace.md),
        if (reels.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MSpace.gutter),
            child: Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: MRadius.xlAll,
                border: Border.all(color: p.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    height: 168,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const MPhoto(source: MStockPhotos.diwali),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.transparent, p.surface], stops: const [0.6, 1]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(MSpace.xs, MSpace.md, MSpace.md, MSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('No reels yet', style: type.title.copyWith(fontSize: 20)),
                          const SizedBox(height: 4),
                          Text(
                            'Say what you want. Get two post-ready cuts.',
                            style: type.bodyMuted.copyWith(fontSize: 14),
                          ),
                          const SizedBox(height: MSpace.sm),
                          PillButton(
                            label: 'Make one',
                            icon: Icons.mic_rounded,
                            onPressed: onMake,
                            height: 48,
                            expand: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 260,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: MSpace.gutter),
              itemCount: reels.length,
              separatorBuilder: (_, _) => const SizedBox(width: MSpace.sm),
              itemBuilder: (context, i) {
                final r = reels[i];
                return FadeRise(
                  index: i,
                  child: SizedBox(
                    width: 146,
                    child: ClipRRect(
                      borderRadius: MRadius.lgAll,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: p.indigoNight),
                          MPhoto(source: MPhotoSource.network(r.coverUrl), fallback: MStockPhotos.diwali),
                          const DecoratedBox(decoration: BoxDecoration(gradient: kPhotoScrim)),
                          const Positioned(
                            top: 10,
                            left: 10,
                            child: FrostedChip(icon: Icons.play_arrow_rounded, label: 'Reel'),
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: Text(
                              r.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: type.title.copyWith(color: Colors.white, fontSize: 17, height: 1.2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
