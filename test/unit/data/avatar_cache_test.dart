import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/services/avatar_cache.dart';

/// The offline avatar guarantee lives here: bytes fetched once must survive a
/// restart of the process with no network, and a failure to fetch must never
/// throw into the widget tree.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('avatar_cache_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const url = 'https://lh3.googleusercontent.com/a/photo=s96-c';
  final bytes = Uint8List.fromList(const [1, 2, 3, 4, 5]);

  AvatarCache cacheWith(AvatarFetcher fetcher) =>
      AvatarCache(fetcher: fetcher, directory: dir);

  test('fetches once, then serves the same bytes from memory', () async {
    var calls = 0;
    final cache = cacheWith((_) async {
      calls++;
      return bytes;
    });

    expect(await cache.load(url), bytes);
    expect(await cache.load(url), bytes);
    expect(calls, 1);
    expect(cache.peek(url), bytes);
  });

  test('peek is empty until the first load completes', () async {
    final cache = cacheWith((_) async => bytes);
    expect(cache.peek(url), isNull);
    await cache.load(url);
    expect(cache.peek(url), bytes);
  });

  test('serves a photo offline after a restart', () async {
    // First run: online, so the bytes land on disk.
    await cacheWith((_) async => bytes).load(url);

    // Second run: a brand-new cache over the same directory, with a fetcher
    // that fails the way an offline device does. The photo still resolves.
    final offline = cacheWith((_) async => null);
    expect(await offline.load(url), bytes);
  });

  test('does not hit the network when the file is already on disk', () async {
    await cacheWith((_) async => bytes).load(url);

    var calls = 0;
    final restarted = cacheWith((_) async {
      calls++;
      return null;
    });
    await restarted.load(url);
    expect(calls, 0);
  });

  test('returns null when offline with nothing cached', () async {
    final cache = cacheWith((_) async => null);
    expect(await cache.load(url), isNull);
    // Nothing is written, so a later online run still fetches.
    expect(dir.listSync(), isEmpty);
  });

  test('a throwing fetcher resolves to null instead of escaping', () async {
    // The widget renders initials while this is in flight, so a thrown
    // SocketException here would land as an unhandled async error rather than
    // anywhere a user could see it.
    final cache = cacheWith((_) async => throw const SocketException('offline'));
    expect(await cache.load(url), isNull);
  });

  test('concurrent loads share a single fetch', () async {
    var calls = 0;
    final cache = cacheWith((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return bytes;
    });

    final results = await Future.wait([
      cache.load(url),
      cache.load(url),
      cache.load(url),
    ]);

    expect(results, everyElement(bytes));
    expect(calls, 1);
  });

  test('keeps separate entries per URL', () async {
    final other = Uint8List.fromList(const [9, 9]);
    final cache = cacheWith((u) async => u == url ? bytes : other);

    expect(await cache.load(url), bytes);
    expect(await cache.load('https://example.com/other.png'), other);
    expect(dir.listSync().length, 2);
  });

  test('re-fetches after an entry is evicted', () async {
    var calls = 0;
    final cache = cacheWith((_) async {
      calls++;
      return bytes;
    });

    await cache.load(url);
    await cache.evict(url);
    expect(cache.peek(url), isNull);
    expect(dir.listSync(), isEmpty);

    await cache.load(url);
    expect(calls, 2);
  });

  test('recovers from a corrupt (empty) cache file', () async {
    final cache = cacheWith((_) async => bytes);
    await cache.load(url);

    File('${dir.path}/${AvatarCache.fileNameFor(url)}').writeAsBytesSync([]);
    cache.clearMemory();

    expect(await cache.load(url), bytes);
  });

  test('works with no disk at all, for the lifetime of the process', () async {
    var calls = 0;
    final cache = AvatarCache(fetcher: (_) async {
      calls++;
      return bytes;
    });

    expect(cache.hasDiskCache, isFalse);
    expect(await cache.load(url), bytes);
    expect(await cache.load(url), bytes);
    expect(calls, 1);
  });

  group('staleness', () {
    final fresh = Uint8List.fromList(const [7, 7, 7]);

    File cacheFile() => File('${dir.path}/${AvatarCache.fileNameFor(url)}');

    /// The refresh is deliberately un-awaited, so poll for it rather than
    /// guessing how many microtasks a real file write takes.
    Future<void> settle(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('serves a stale photo immediately, then refreshes it', () async {
      await cacheWith((_) async => bytes).load(url);
      cacheFile().setLastModifiedSync(
        DateTime.now().subtract(AvatarCache.staleAfter * 2),
      );

      var calls = 0;
      final cache = cacheWith((_) async {
        calls++;
        return fresh;
      });

      // Offline-first: the old photo comes back without waiting on a fetch.
      expect(await cache.load(url), bytes);

      // The refresh runs behind it and lands in time for the next launch.
      await settle(() => cache.peek(url) == fresh);
      expect(calls, 1);
      expect(cache.peek(url), fresh);
      expect(await cacheFile().readAsBytes(), fresh);
    });

    test('keeps the stale photo when the refresh fails', () async {
      await cacheWith((_) async => bytes).load(url);
      cacheFile().setLastModifiedSync(
        DateTime.now().subtract(AvatarCache.staleAfter * 2),
      );

      var calls = 0;
      final cache = cacheWith((_) async {
        calls++;
        return null;
      });
      expect(await cache.load(url), bytes);

      await settle(() => calls > 0);
      expect(cache.peek(url), bytes);
      expect(await cacheFile().readAsBytes(), bytes);
    });

    test('does not refresh an entry that is still fresh', () async {
      await cacheWith((_) async => bytes).load(url);

      var calls = 0;
      final cache = cacheWith((_) async {
        calls++;
        return fresh;
      });
      await cache.load(url);

      // A negative: give any stray refresh real time to show up.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 0);
    });
  });

  group('fileNameFor', () {
    test('is stable for the same URL', () {
      expect(AvatarCache.fileNameFor(url), AvatarCache.fileNameFor(url));
    });

    test('differs between URLs', () {
      expect(
        AvatarCache.fileNameFor(url),
        isNot(AvatarCache.fileNameFor('$url&v=2')),
      );
    });

    test('contains nothing that could escape the cache directory', () {
      // Provider URLs carry slashes, dots and query strings; the name has to
      // be a hash or it would walk out of the directory or exceed the
      // filesystem's name limit.
      final name = AvatarCache.fileNameFor(url);
      expect(name, matches(RegExp(r'^[0-9a-f]{40}\.img$')));
    });
  });
}
