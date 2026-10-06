import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads the bytes behind an avatar URL, or null if they can't be had.
typedef AvatarFetcher = Future<Uint8List?> Function(String url);

Future<Uint8List?> _httpFetch(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 10);
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    // Offline, DNS failure, timeout, bad URL — all mean "no photo right now",
    // which the caller renders as initials.
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Keeps remote profile photos on disk so they still render with no network.
///
/// A provider photo (Google, Apple) lives behind an https URL, so a plain
/// `NetworkImage` renders an empty circle the moment the device goes offline —
/// including on a cold start, because Flutter's image cache is memory-only and
/// dies with the process. Bytes fetched here are written to the app's support
/// directory and read back first on every later load, so the second launch is
/// offline-safe. Photos the user uploaded are stored in Firestore as `data:`
/// URIs and never reach this cache: they are already local.
class AvatarCache {
  AvatarCache({AvatarFetcher fetcher = _httpFetch, Directory? directory})
      : _fetch = fetcher {
    _directory = directory;
  }

  /// How long a cached photo is served before it is quietly refreshed. The
  /// stale copy is still shown immediately — offline-first — and the new bytes
  /// land in time for the next launch.
  static const staleAfter = Duration(days: 7);

  /// Swapped out in tests; the app uses this one everywhere.
  static AvatarCache instance = AvatarCache();

  final AvatarFetcher _fetch;
  Directory? _directory;

  final Map<String, Uint8List> _memory = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  /// True once a disk location is known. Without one the cache still works,
  /// just only for the lifetime of the process.
  bool get hasDiskCache => _directory != null;

  /// Resolves the on-disk location. Safe to call more than once; failures are
  /// swallowed because an avatar is never worth failing startup over.
  Future<void> init() async {
    if (_directory != null) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/avatar_cache');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      _directory = dir;
    } catch (e) {
      debugPrint('AvatarCache: no disk cache available ($e)');
    }
  }

  /// File name for a URL. Hashed so a query string full of `/` and `=` can't
  /// escape the directory or blow past the filesystem's name limit.
  static String fileNameFor(String url) =>
      '${sha1.convert(utf8.encode(url))}.img';

  /// Bytes already in memory, if any. Synchronous so the first frame can paint
  /// the photo instead of flashing the initials.
  Uint8List? peek(String url) => _memory[url];

  /// Disk first, network second. Returns null when the photo can't be had,
  /// which callers show as initials rather than an empty circle.
  Future<Uint8List?> load(String url) async {
    final cached = _memory[url];
    if (cached != null) return cached;

    final pending = _inFlight[url];
    if (pending != null) return pending;

    final future = _load(url);
    _inFlight[url] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(url);
    }
  }

  Future<Uint8List?> _load(String url) async {
    final file = _fileFor(url);
    if (file != null) {
      try {
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _memory[url] = bytes;
            _refreshIfStale(url, file);
            return bytes;
          }
        }
      } catch (_) {
        // A corrupt or unreadable cache entry just means we re-fetch.
      }
    }

    Uint8List? fetched;
    try {
      fetched = await _fetch(url);
    } catch (_) {
      // A load is best-effort: the caller is painting initials in the
      // meantime, and an avatar must never throw into the widget tree.
      return null;
    }
    if (fetched == null) return null;
    _memory[url] = fetched;

    if (file != null) {
      try {
        await file.writeAsBytes(fetched, flush: true);
      } catch (_) {
        // Out of space or no permission: keep serving from memory.
      }
    }
    return fetched;
  }

  /// Re-fetches an entry that has aged out, without making anyone wait. A
  /// provider that reuses one URL for a changed photo would otherwise pin the
  /// old picture forever, since nothing else ever invalidates this cache.
  void _refreshIfStale(String url, File file) {
    try {
      if (DateTime.now().difference(file.lastModifiedSync()) < staleAfter) {
        return;
      }
    } catch (_) {
      return;
    }

    unawaited(() async {
      try {
        final bytes = await _fetch(url);
        if (bytes == null) return;
        _memory[url] = bytes;
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // Offline, or no space. The stale copy stays, which is the point.
      }
    }());
  }

  File? _fileFor(String url) {
    final dir = _directory;
    if (dir == null) return null;
    return File('${dir.path}/${fileNameFor(url)}');
  }

  /// Drops everything we hold for [url]. Used when a photo is replaced at the
  /// same address, which the URL alone can't tell us about.
  Future<void> evict(String url) async {
    _memory.remove(url);
    final file = _fileFor(url);
    if (file == null) return;
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  @visibleForTesting
  void clearMemory() => _memory.clear();
}
