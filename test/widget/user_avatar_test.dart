import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/services/avatar_cache.dart';
import 'package:accounts_note/core/theme/app_theme.dart';
import 'package:accounts_note/widgets/user_avatar.dart';

/// A real 1x1 PNG, so nothing here depends on bytes that would fail to decode.
final kPngBytes = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
));

/// The avatar is the one piece of the app that routinely has no data to show:
/// a brand-new account has no photo, and a signed-in one has a photo behind an
/// https URL that a plane or a lift takes away. These pin the rule that it
/// degrades to initials rather than to an empty circle.
///
/// Note on disk: widget tests run under fake async, where real file I/O never
/// completes. Caches here are memory-only unless a test deliberately steps
/// into `runAsync` to exercise the disk.
void main() {
  const remoteUrl = 'https://lh3.googleusercontent.com/a/photo=s96-c';

  Future<void> pumpAvatar(WidgetTester tester, UserAvatar avatar) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: avatar)),
    ));
    await tester.pump();
  }

  /// Whether a photo layer made it into the tree. It is only added once bytes
  /// resolve, so this reads as "is a photo being shown".
  int photoLayers(WidgetTester tester) =>
      tester.widgetList(find.byType(Image)).length;

  group('initials', () {
    testWidgets('shows the name initials when there is no photo',
        (tester) async {
      await pumpAvatar(
          tester, const UserAvatar(radius: 20, name: 'A R Prathap'));
      expect(find.text('AP'), findsOneWidget);
      expect(photoLayers(tester), 0);
    });

    testWidgets('falls back to the email when there is no name',
        (tester) async {
      await pumpAvatar(
        tester,
        const UserAvatar(radius: 20, email: 'a.person@example.com'),
      );
      expect(find.text('AP'), findsOneWidget);
    });

    testWidgets('shows a placeholder rather than an empty circle',
        (tester) async {
      await pumpAvatar(tester, const UserAvatar(radius: 20));
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('offline', () {
    testWidgets('keeps the initials when a remote photo cannot be fetched',
        (tester) async {
      // Exactly the offline case: the address is good, the network is not.
      final cache = AvatarCache(fetcher: (_) async => null);

      await pumpAvatar(
        tester,
        UserAvatar(
          radius: 20,
          photoUrl: remoteUrl,
          name: 'A R Prathap',
          cache: cache,
        ),
      );
      await tester.pump();

      expect(find.text('AP'), findsOneWidget);
      expect(photoLayers(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not throw when the fetch itself fails', (tester) async {
      final cache = AvatarCache(
        fetcher: (_) async => throw const SocketException('offline'),
      );

      await pumpAvatar(
        tester,
        UserAvatar(radius: 20, photoUrl: remoteUrl, name: 'Ada', cache: cache),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('paints a photo cached by an earlier run of the app',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('user_avatar_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      // runAsync, because the disk round-trip is real I/O.
      late AvatarCache offline;
      await tester.runAsync(() async {
        // Run one: online, so the bytes land on disk.
        await AvatarCache(fetcher: (_) async => kPngBytes, directory: dir)
            .load(remoteUrl);

        // Run two: offline, fresh process, same directory.
        offline = AvatarCache(fetcher: (_) async => null, directory: dir);
        expect(await offline.load(remoteUrl), kPngBytes);
      });

      await pumpAvatar(
        tester,
        UserAvatar(
          radius: 20,
          photoUrl: remoteUrl,
          name: 'A R Prathap',
          cache: offline,
        ),
      );

      expect(photoLayers(tester), 1);
      // The initials stay underneath, so the circle is still legible if the
      // image layer later fails to decode.
      expect(find.text('AP'), findsOneWidget);
    });
  });

  group('photo sources', () {
    testWidgets('renders an uploaded photo straight from its data URI',
        (tester) async {
      // Uploaded photos are held in Firestore as base64. They are already
      // local, so they must not go near the cache.
      var fetches = 0;
      final cache = AvatarCache(fetcher: (_) async {
        fetches++;
        return null;
      });

      await pumpAvatar(
        tester,
        UserAvatar(
          radius: 20,
          photoUrl: 'data:image/png;base64,${base64Encode(kPngBytes)}',
          name: 'Ada Lovelace',
          cache: cache,
        ),
      );

      expect(photoLayers(tester), 1);
      expect(fetches, 0);
    });

    testWidgets('paints an already-warm photo on the first frame',
        (tester) async {
      final cache = AvatarCache(fetcher: (_) async => kPngBytes);
      await cache.load(remoteUrl); // warm, as it is after the first screen

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: UserAvatar(
            radius: 20,
            photoUrl: remoteUrl,
            name: 'Ada',
            cache: cache,
          ),
        ),
      ));

      // No second pump: this asserts there is no flash of initials-only when
      // moving between screens.
      expect(photoLayers(tester), 1);
    });

    testWidgets('picks the photo up when it arrives after the first frame',
        (tester) async {
      final cache = AvatarCache(fetcher: (_) async => kPngBytes);

      await pumpAvatar(
        tester,
        UserAvatar(
          radius: 20,
          photoUrl: remoteUrl,
          name: 'Ada',
          cache: cache,
        ),
      );
      await tester.pump();

      expect(photoLayers(tester), 1);
    });

    testWidgets('swaps the photo when the URL changes', (tester) async {
      final cache = AvatarCache(fetcher: (_) async => kPngBytes);

      await pumpAvatar(tester, UserAvatar(radius: 20, name: 'Ada', cache: cache));
      expect(photoLayers(tester), 0);

      await pumpAvatar(
        tester,
        UserAvatar(
          radius: 20,
          photoUrl: remoteUrl,
          name: 'Ada',
          cache: cache,
        ),
      );
      await tester.pump();
      expect(photoLayers(tester), 1);
    });
  });

  group('layout', () {
    testWidgets('is a circle of the requested diameter', (tester) async {
      await pumpAvatar(tester, const UserAvatar(radius: 24, name: 'Ada'));
      expect(tester.getSize(find.byType(UserAvatar)), const Size(48, 48));
      expect(find.byType(ClipOval), findsOneWidget);
    });
  });
}
