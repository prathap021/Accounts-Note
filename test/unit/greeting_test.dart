import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/utils/avatar_provider.dart';
import 'package:income_expense_tracker/core/utils/greeting.dart';

DateTime at(int hour) => DateTime(2026, 9, 15, hour, 30);

void main() {
  group('greetingFor', () {
    test('covers every hour of the day', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(greetingFor(at(hour)), isNotEmpty, reason: 'hour $hour');
      }
    });

    test('morning runs 5am to noon', () {
      expect(greetingFor(at(5)), 'Good morning');
      expect(greetingFor(at(9)), 'Good morning');
      expect(greetingFor(at(11)), 'Good morning');
    });

    test('afternoon runs noon to 5pm', () {
      expect(greetingFor(at(12)), 'Good afternoon');
      expect(greetingFor(at(16)), 'Good afternoon');
    });

    test('evening runs 5pm to 9pm', () {
      expect(greetingFor(at(17)), 'Good evening');
      expect(greetingFor(at(20)), 'Good evening');
    });

    test('night covers 9pm through to 5am', () {
      expect(greetingFor(at(21)), 'Good night');
      expect(greetingFor(at(23)), 'Good night');
      expect(greetingFor(at(0)), 'Good night');
      expect(greetingFor(at(4)), 'Good night');
    });
  });

  group('greetingName', () {
    test('keeps a multi-word name whole', () {
      expect(greetingName('A R Prathap'), 'A R Prathap');
    });

    test('keeps a single-word name', () {
      expect(greetingName('Prathap'), 'Prathap');
    });

    test('uses the local part of an email', () {
      expect(greetingName('a.person@example.com'), 'a.person');
    });

    test('falls back when there is nothing to greet', () {
      expect(greetingName(''), 'there');
      expect(greetingName('   '), 'there');
      expect(greetingName('@example.com'), 'there');
    });

    test('trims surrounding whitespace', () {
      expect(greetingName('  Prathap Kumar  '), 'Prathap Kumar');
    });
  });

  group('resolveDisplayName', () {
    test('prefers the profile name', () {
      expect(
        resolveDisplayName(
          profileName: 'A R Prathap',
          authName: 'Prathap',
          email: 'a.person@example.com',
          fallback: 'You',
        ),
        'A R Prathap',
      );
    });

    test('falls back to the auth name when the profile has not loaded', () {
      // The offline cold start: Firebase Auth has the name on disk, the
      // Firestore profile document has not resolved yet.
      expect(
        resolveDisplayName(
          profileName: null,
          authName: 'Prathap',
          email: 'a.person@example.com',
          fallback: 'You',
        ),
        'Prathap',
      );
    });

    test('falls back to the address when no name is set anywhere', () {
      expect(
        resolveDisplayName(
          authName: null,
          email: 'a.person@example.com',
          fallback: 'You',
        ),
        'a.person@example.com',
      );
    });

    test('uses the caller fallback only when nothing else is known', () {
      expect(resolveDisplayName(fallback: 'You'), 'You');
      expect(resolveDisplayName(fallback: 'Signed in user'), 'Signed in user');
    });

    test('treats blank and whitespace-only values as missing', () {
      expect(
        resolveDisplayName(
          profileName: '   ',
          authName: '',
          email: 'a.person@example.com',
          fallback: 'You',
        ),
        'a.person@example.com',
      );
      expect(
        resolveDisplayName(profileName: ' ', email: '  ', fallback: 'You'),
        'You',
      );
    });

    test('trims what it returns', () {
      expect(
        resolveDisplayName(profileName: '  Prathap  ', fallback: 'You'),
        'Prathap',
      );
    });

    test('feeds a greeting and initials that are never empty', () {
      // The two things the resolved name is actually used for.
      final name = resolveDisplayName(
        email: 'a.person@example.com',
        fallback: 'You',
      );
      expect(greetingName(name), 'a.person');
      expect(initialsFor(name), 'AP');
    });
  });
}
