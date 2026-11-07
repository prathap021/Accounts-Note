import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/features/dashboard/dashboard_screen.dart';

/// The dashboard donut shows the user's own categories, and only those.
///
/// It used to roll everything past the top six into an "Everything else"
/// wedge. That read as a category the user did not have, and hid real ones
/// (a month with seven categories lost the smallest into it).
void main() {
  // Stand-ins for the user's category colours.
  const colors = {
    'Food': Colors.orange,
    'Bills': Colors.red,
    'Gym': Colors.green,
  };
  Color colorOf(String name, int rank) => colors[name] ?? Colors.grey;

  List<ExpenseSlice> slicesOf(Map<String, double> data) =>
      buildExpenseSlices(data, colorOf: colorOf);

  test('an empty breakdown yields no slices', () {
    expect(slicesOf(const {}), isEmpty);
  });

  test('orders slices largest first', () {
    final slices = slicesOf({'Food': 70, 'Bills': 6170, 'Gym': 1575});
    expect(slices.map((s) => s.label), ['Bills', 'Gym', 'Food']);
  });

  test('drops zero-valued categories', () {
    final slices = slicesOf({'Food': 70, 'Unused': 0});
    expect(slices.map((s) => s.label), ['Food']);
  });

  test('every category keeps its own wedge, however many there are', () {
    final data = {
      'Rent': 18000.0,
      'Shopping': 2499.0,
      'Food': 1690.0,
      'Bills': 1150.0,
      'Health': 800.0,
      'Entertainment': 649.0,
      'Transport': 320.0,
      'Pets': 134.0,
      'Gifts': 99.0,
    };
    final labels = slicesOf(data).map((s) => s.label).toList();

    expect(labels, hasLength(9));
    expect(labels.toSet(), data.keys.toSet(),
        reason: 'only the categories the user spent in, nothing invented');
    expect(labels, contains('Transport'),
        reason: 'the seventh category used to vanish into "Everything else"');
  });

  test("a real category named Other is listed once, as itself", () {
    final slices = slicesOf({'Bills': 600, 'Other': 520, 'Food': 100});
    expect(slices.where((s) => s.label == 'Other'), hasLength(1));
    expect(slices.firstWhere((s) => s.label == 'Other').amount, 520);
  });

  test("each wedge takes its category's colour", () {
    final slices = slicesOf({'Food': 70, 'Bills': 100, 'Renamed': 10});
    final byLabel = {for (final s in slices) s.label: s.color};
    expect(byLabel['Food'], Colors.orange);
    expect(byLabel['Bills'], Colors.red);
    expect(byLabel['Renamed'], Colors.grey,
        reason: 'a name the user no longer has gets the neutral colour');
  });

  test('the wedges add up to what was spent', () {
    final data = {
      for (var i = 0; i < 10; i++) 'Cat$i': (i + 1) * 10.0,
    };
    final expected = data.values.fold<double>(0, (a, b) => a + b);
    final actual =
        slicesOf(data).fold<double>(0, (sum, s) => sum + s.amount);

    expect(actual, expected);
  });
}
