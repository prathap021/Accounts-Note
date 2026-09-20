import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/features/dashboard/dashboard_screen.dart';

/// The dashboard donut rolls everything past the top few categories into one
/// wedge. That wedge used to be labelled "Other" — which is also a real
/// default category, so the legend could show "Other" twice with different
/// amounts and no way to tell them apart.
void main() {
  const palette = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.brown,
  ];

  List<ExpenseSlice> slicesOf(Map<String, double> data, {int max = 6}) =>
      buildExpenseSlices(data, palette: palette, maxSlices: max);

  test('an empty breakdown yields no slices', () {
    expect(slicesOf(const {}), isEmpty);
  });

  test('orders slices largest first', () {
    final slices = slicesOf({'Food': 70, 'Bills': 6170, 'Gym': 1575});
    expect(slices.map((s) => s.label), ['Bills', 'Gym', 'Food']);
  });

  test('keeps every category when there are few enough', () {
    final slices = slicesOf({'Food': 70, 'Bills': 100});
    expect(slices, hasLength(2));
    expect(slices.map((s) => s.label), isNot(contains(kOtherSlicesLabel)));
  });

  test('drops zero-valued categories', () {
    final slices = slicesOf({'Food': 70, 'Unused': 0});
    expect(slices.map((s) => s.label), ['Food']);
  });

  group('rolling up the tail', () {
    test('combines everything past the cap into one wedge', () {
      final data = {
        for (var i = 0; i < 9; i++) 'Cat$i': (9 - i) * 100.0,
      };
      final slices = slicesOf(data);

      expect(slices, hasLength(7), reason: '6 named + 1 rollup');
      expect(slices.last.label, kOtherSlicesLabel);
      // Cat6..Cat8 => 300 + 200 + 100
      expect(slices.last.amount, 600);
    });

    test('does not collide with a real category named Other', () {
      final data = {
        'Bills': 6170.0,
        'Education': 2000.0,
        'Gym': 1575.0,
        'Food': 1050.0,
        'Other': 520.0,
        'Entertainment': 500.0,
        'Travel': 200.0,
        'Pets': 134.0,
      };
      final slices = slicesOf(data);
      final labels = slices.map((s) => s.label).toList();

      expect(labels.where((l) => l == 'Other'), hasLength(1),
          reason: "the user's own 'Other' category stays exactly once");
      expect(labels, contains(kOtherSlicesLabel));
      expect(labels.toSet(), hasLength(labels.length),
          reason: 'no duplicate labels in the legend');
    });

    test('adds no rollup wedge when nothing is left over', () {
      final data = {
        for (var i = 0; i < 6; i++) 'Cat$i': 100.0,
      };
      expect(slicesOf(data).map((s) => s.label),
          isNot(contains(kOtherSlicesLabel)));
    });
  });

  test('the rollup preserves the overall total', () {
    final data = {
      for (var i = 0; i < 10; i++) 'Cat$i': (i + 1) * 10.0,
    };
    final expected = data.values.fold<double>(0, (a, b) => a + b);
    final actual =
        slicesOf(data).fold<double>(0, (sum, s) => sum + s.amount);

    expect(actual, expected,
        reason: 'the donut must add up to what was spent');
  });

  test('assigns a colour to every slice', () {
    final data = {for (var i = 0; i < 8; i++) 'Cat$i': 10.0 * (8 - i)};
    final slices = slicesOf(data);
    expect(slices.every((s) => s.color != const Color(0x00000000)), isTrue);
  });
}
