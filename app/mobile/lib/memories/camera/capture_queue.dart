import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Which lens took the capture. Used to tag the uploaded asset.
enum CaptureLens {
  front,
  back;

  String get tag => name;
}

/// A captured photo/video waiting to be saved + uploaded.
@immutable
class CaptureJob {
  final File file;
  final bool isVideo;
  final CaptureLens lens;
  final DateTime takenAt;

  const CaptureJob({required this.file, required this.isVideo, required this.lens, required this.takenAt});
}

/// Album totals shown in the "N moments from M people" counter.
@immutable
class AlbumMoments {
  final int moments;
  final int people;

  const AlbumMoments({required this.moments, required this.people});
}

/// The side-effecting steps of the capture pipeline. Implemented against Immich in
/// `capture_uploader.dart`; replaceable in tests.
abstract interface class CaptureSink {
  /// Save to the device gallery (so it also appears in the normal camera roll).
  Future<void> saveToGallery(CaptureJob job);

  /// Upload to the server; returns the remote asset id. Throws on failure.
  Future<String> upload(CaptureJob job, {void Function(double progress)? onProgress});

  /// Add the remote asset to the event album.
  Future<void> addToAlbum(String albumId, String assetId);

  /// Tag the asset (camera=front/back, member, source). Best effort.
  Future<void> tag(String assetId, CaptureJob job, {required String memberName});

  /// Album totals; `null` if unavailable.
  Future<AlbumMoments?> fetchMoments(String albumId);
}

/// Serial upload queue with observable status for the camera's upload chip.
///
/// Uploads run one at a time and are paused while the camera is capturing
/// ([hold]/[release]): on iOS the upload service clears the system temp dir,
/// which is where the camera plugin writes in-progress captures.
class CaptureUploadQueue extends ChangeNotifier {
  CaptureUploadQueue({required this.sink, required this.albumId, required this.memberName, this.onUploaded});

  final CaptureSink sink;
  final String albumId;
  final String memberName;

  /// Called after each capture has been uploaded and added to the album.
  final void Function(String assetId)? onUploaded;

  final _log = Logger('MemoriesCaptureQueue');
  final List<CaptureJob> _pending = [];
  final List<CaptureJob> _failed = [];

  int _done = 0;
  int _holds = 0;
  bool _running = false;
  bool _disposed = false;
  double? _progress;
  Completer<void>? _released;

  int get pending => _pending.length + (_running ? 1 : 0);
  int get done => _done;
  int get failed => _failed.length;
  bool get isUploading => _running;

  /// Progress (0..1) of the item currently uploading, if known.
  double? get progress => _progress;

  /// Copies a capture out of the plugin's temp location into app storage, then queues it.
  Future<void> enqueue(String capturedPath, {required bool isVideo, required CaptureLens lens}) async {
    final file = await _persist(capturedPath);
    _pending.add(CaptureJob(file: file, isVideo: isVideo, lens: lens, takenAt: DateTime.now()));
    _notify();
    unawaited(_pump());
  }

  /// Pause starting new uploads (e.g. while recording).
  void hold() {
    _holds++;
    _released ??= Completer<void>();
  }

  void release() {
    if (_holds > 0) {
      _holds--;
    }
    if (_holds == 0) {
      _released?.complete();
      _released = null;
    }
  }

  /// Re-queue failed items.
  void retryFailed() {
    if (_failed.isEmpty) {
      return;
    }
    _pending.addAll(_failed);
    _failed.clear();
    _notify();
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      // Keeps draining after dispose so captures taken just before leaving still upload.
      while (_pending.isNotEmpty) {
        // Re-check after waking: another capture may have started meanwhile.
        while (_released != null) {
          await _released!.future;
        }
        final job = _pending.removeAt(0);
        _progress = 0;
        _notify();
        await _process(job);
        _progress = null;
        _notify();
      }
    } finally {
      _running = false;
      _notify();
    }
  }

  Future<void> _process(CaptureJob job) async {
    try {
      await sink.saveToGallery(job);
    } catch (e) {
      _log.warning('Saving capture to gallery failed', e);
    }

    final String assetId;
    try {
      assetId = await sink.upload(
        job,
        onProgress: (v) {
          _progress = v;
          _notify();
        },
      );
      await sink.addToAlbum(albumId, assetId);
    } catch (e) {
      _log.warning('Uploading capture failed', e);
      _failed.add(job);
      return;
    }

    _done++;
    try {
      await sink.tag(assetId, job, memberName: memberName);
    } catch (e) {
      _log.fine('Tagging capture failed: $e');
    }
    try {
      await job.file.delete();
    } catch (_) {}
    onUploaded?.call(assetId);
  }

  static Future<File> _persist(String path) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'memories_camera'));
    await dir.create(recursive: true);
    final ext = p.extension(path).isEmpty ? '.jpg' : p.extension(path);
    final stamp = DateTime.now();
    final name =
        'MEM_${stamp.year}${_two(stamp.month)}${_two(stamp.day)}_'
        '${_two(stamp.hour)}${_two(stamp.minute)}${_two(stamp.second)}_${stamp.millisecond}$ext';
    final source = File(path);
    final target = p.join(dir.path, name);
    try {
      return await source.rename(target);
    } on FileSystemException {
      final copy = await source.copy(target);
      try {
        await source.delete();
      } catch (_) {}
      return copy;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Queued uploads keep running in the background; only notifications stop.
    _disposed = true;
    _holds = 0;
    _released?.complete();
    _released = null;
    super.dispose();
  }
}
