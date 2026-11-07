import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/repositories/credit_card_repository.dart';
import '../models/credit_card_model.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';
import 'transaction_provider.dart';

final creditCardRepositoryProvider = Provider<CreditCardRepository>((ref) {
  return CreditCardRepository();
});

final creditCardsStreamProvider = StreamProvider<List<CreditCardModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(creditCardRepositoryProvider).watchCards(uid);
});

/// Cards keyed by id, so a transaction row can show its card's current name
/// without a lookup per row. A deleted card is absent; callers fall back to
/// the name stored on the transaction.
final creditCardLookupProvider = Provider<Map<String, CreditCardModel>>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).asData?.value ?? const [];
  return {for (final c in cards) c.id: c};
});

/// The calendar month containing [now], both ends inclusive — the same window
/// the dashboard and budgets use, so the numbers agree across screens.
DateTimeRange monthRangeFor(DateTime now) => DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
    );

/// What was spent on each card in the month containing [now], keyed by card
/// id. Only expenses count: a refund to the card is not spending. [now] is
/// injected so the month boundary can be tested without the wall clock.
Map<String, double> creditCardSpendFor(
  Iterable<TransactionModel> transactions, {
  required DateTime now,
}) {
  final month = monthRangeFor(now);
  final totals = <String, double>{};
  for (final t in transactions) {
    final cardId = t.creditCardId;
    if (cardId == null || t.type != TransactionType.expense) continue;
    if (t.date.isBefore(month.start) || t.date.isAfter(month.end)) continue;
    totals[cardId] = (totals[cardId] ?? 0) + t.amount;
  }
  return totals;
}

/// This month's spend per card, recomputed from the local ledger on every
/// write so it is right offline and the moment an expense is saved.
final creditCardSpendProvider = Provider<Map<String, double>>((ref) {
  final transactions =
      ref.watch(allTransactionsStreamProvider).asData?.value ?? const [];
  return creditCardSpendFor(transactions, now: DateTime.now());
});

class CreditCardActionsNotifier extends Notifier<AsyncValue<void>> {
  late CreditCardRepository _repo;
  String? _uid;

  @override
  AsyncValue<void> build() {
    _repo = ref.watch(creditCardRepositoryProvider);
    _uid = ref.watch(currentUidProvider);
    return const AsyncData(null);
  }

  /// Returns the saved card, with its id, or null on failure.
  Future<CreditCardModel?> addCard(CreditCardModel card) async {
    if (_uid == null) return null;
    state = const AsyncLoading();
    final result = await _repo.addCard(_uid!, card);
    return result.when(
      success: (saved) {
        state = const AsyncData(null);
        return saved;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return null;
      },
    );
  }

  Future<bool> updateCard(CreditCardModel card) async {
    if (_uid == null) return false;
    state = const AsyncLoading();
    final result = await _repo.updateCard(_uid!, card);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteCard(String cardId) async {
    if (_uid == null) return false;
    final result = await _repo.deleteCard(_uid!, cardId);
    return result.isSuccess;
  }
}

final creditCardActionsProvider =
    NotifierProvider<CreditCardActionsNotifier, AsyncValue<void>>(
  CreditCardActionsNotifier.new,
);
