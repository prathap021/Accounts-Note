import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/utils/avatar_provider.dart';

/// The initials are what the user sees whenever the photo can't be shown —
/// offline, on a cold start, or for an account that never set one. They are
/// the fallback the whole offline avatar flow rests on, so the rules are
/// pinned here rather than left to the widget.
void main() {
  group('initialsFor', () {
    test('takes the first and last word of a full name', () {
      expect(initialsFor('A R Prathap'), 'AP');
      expect(initialsFor('Ada Lovelace'), 'AL');
    });

    test('uses a single letter for a one-word name', () {
      expect(initialsFor('Prathap'), 'P');
    });

    test('upper-cases whatever it finds', () {
      expect(initialsFor('ada lovelace'), 'AL');
    });

    test('ignores surrounding and repeated whitespace', () {
      expect(initialsFor('   ada    lovelace  '), 'AL');
    });

    test('splits on dots, dashes and underscores as well as spaces', () {
      expect(initialsFor('ada.lovelace'), 'AL');
      expect(initialsFor('ada-lovelace'), 'AL');
      expect(initialsFor('ada_lovelace'), 'AL');
    });

    test('treats an address in the name slot as an address', () {
      expect(initialsFor('a.person@example.com'), 'AP');
    });

    test('falls back to the email when there is no name', () {
      expect(initialsFor(null, email: 'a.person@example.com'), 'AP');
      expect(initialsFor('', email: 'prathap@example.com'), 'P');
      expect(initialsFor('   ', email: 'a.person@example.com'), 'AP');
    });

    test('prefers the name over the email when both are present', () {
      expect(initialsFor('Ada Lovelace', email: 'zz@example.com'), 'AL');
    });

    test('never returns an empty string', () {
      // A blank circle reads as a broken avatar, so there is always a glyph.
      expect(initialsFor(null), '?');
      expect(initialsFor(''), '?');
      expect(initialsFor('   '), '?');
      expect(initialsFor('***'), '?');
      expect(initialsFor('***', email: '@@@'), '?');
    });

    test('handles names that are not latin', () {
      expect(initialsFor('பிரதாப்'), 'ப');
      expect(initialsFor('Ада Лавлейс'), 'АЛ');
    });

    test('is at most two characters', () {
      expect(initialsFor('One Two Three Four Five').length, 2);
    });
  });

  group('dataUriImage', () {
    test('decodes a base64 data URI into memory', () {
      final uri = 'data:image/png;base64,${base64Encode(const [1, 2, 3, 4])}';
      final image = dataUriImage(uri);
      expect(image, isA<MemoryImage>());
      expect((image! as MemoryImage).bytes, const [1, 2, 3, 4]);
    });

    test('returns null for a remote URL', () {
      expect(dataUriImage('https://example.com/a.png'), isNull);
    });

    test('returns null rather than throwing on undecodable bytes', () {
      expect(dataUriImage('data:image/png;base64,not-base64!!'), isNull);
    });

    test('returns null for null or empty input', () {
      expect(dataUriImage(null), isNull);
      expect(dataUriImage(''), isNull);
    });
  });

  group('isRemoteAvatar', () {
    test('is true only for http(s) addresses', () {
      expect(isRemoteAvatar('https://lh3.googleusercontent.com/a/x=s96-c'), isTrue);
      expect(isRemoteAvatar('http://example.com/a.png'), isTrue);
      expect(isRemoteAvatar('data:image/png;base64,AAAA'), isFalse);
      expect(isRemoteAvatar('  '), isFalse);
      expect(isRemoteAvatar(null), isFalse);
    });
  });
}
