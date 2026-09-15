import 'package:flutter_test/flutter_test.dart';
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
      expect(greetingName('selflearner021@gmail.com'), 'selflearner021');
    });

    test('falls back when there is nothing to greet', () {
      expect(greetingName(''), 'there');
      expect(greetingName('   '), 'there');
      expect(greetingName('@gmail.com'), 'there');
    });

    test('trims surrounding whitespace', () {
      expect(greetingName('  Prathap Kumar  '), 'Prathap Kumar');
    });
  });
}
