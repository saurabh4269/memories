import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/camera/capture_queue.dart';
import 'package:immich_mobile/memories/camera/config.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:openapi/api.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

/// [CaptureSink] backed by the app's existing Immich services:
/// - [ForegroundUploadService.uploadShareIntent] (same path as "share to Immich") for the upload,
/// - `PUT /api/albums/{id}/assets` to add it to the event album,
/// - `PUT /api/assets/{id}/metadata` (fallback: description) for the camera=front/back tag,
/// - photo_manager to save a copy into the device gallery.
class ImmichCaptureSink implements CaptureSink {
  ImmichCaptureSink(this._uploadService, this._api);

  final ForegroundUploadService _uploadService;
  final ApiService _api;

  @override
  Future<void> saveToGallery(CaptureJob job) async {
    final title = p.basename(job.file.path);
    if (job.isVideo) {
      await PhotoManager.editor.saveVideo(job.file, title: title);
    } else {
      await PhotoManager.editor.saveImageWithPath(job.file.path, title: title);
    }
  }

  @override
  Future<String> upload(CaptureJob job, {void Function(double progress)? onProgress}) async {
    String? remoteId;
    String? error;
    await _uploadService.uploadShareIntent(
      [job.file],
      onProgress: (_, bytes, total) {
        if (total > 0) {
          onProgress?.call(bytes / total);
        }
      },
      onSuccess: (_, id) => remoteId = id,
      onError: (_, message) => error = message,
    );
    final id = remoteId;
    if (id == null) {
      throw StateError(error ?? 'Upload did not complete');
    }
    return id;
  }

  @override
  Future<void> addToAlbum(String albumId, String assetId) async {
    final results = await _api.albumsApi.addAssetsToAlbum(albumId, BulkIdsDto(ids: [assetId]));
    final result = results?.where((r) => r.id == assetId).firstOrNull;
    // "duplicate" means it is already in the album, which is fine.
    final reason = result?.error.orElse(null);
    if (result != null && !result.success && reason != BulkIdErrorReason.duplicate) {
      throw StateError('Could not add to album: $reason');
    }
  }

  @override
  Future<void> tag(String assetId, CaptureJob job, {required String memberName}) async {
    try {
      await _api.assetsApi.updateAssetMetadata(
        assetId,
        AssetMetadataUpsertDto(
          items: [
            AssetMetadataUpsertItemDto(
              key: kMemoriesMetadataKey,
              value: {
                'source': 'memories-camera',
                'camera': job.lens.tag,
                'member': memberName,
                'type': job.isVideo ? 'video' : 'photo',
                'takenAt': job.takenAt.toUtc().toIso8601String(),
              },
            ),
          ],
        ),
      );
    } catch (_) {
      // Older servers restrict metadata keys; fall back to a readable description.
      await _api.assetsApi.updateAsset(
        assetId,
        UpdateAssetDto(description: Optional.present('camera=${job.lens.tag} · by $memberName')),
      );
    }
  }

  @override
  Future<AlbumMoments?> fetchMoments(String albumId) async {
    try {
      final album = await _api.albumsApi.getAlbumInfo(albumId);
      if (album == null) {
        return null;
      }
      final contributors = album.contributorCounts.orElse(null)?.where((c) => c.assetCount > 0).length ?? 0;
      final people = contributors > 0 ? contributors : album.albumUsers.length + 1;
      return AlbumMoments(moments: album.assetCount, people: people);
    } catch (_) {
      return null;
    }
  }
}

/// The Immich-backed capture sink. Override in tests.
final memoriesCaptureSinkProvider = Provider<CaptureSink>(
  (ref) => ImmichCaptureSink(ref.watch(foregroundUploadServiceProvider), ref.watch(apiServiceProvider)),
);
