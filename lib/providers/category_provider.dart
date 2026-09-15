import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/repositories/category_repository.dart';
import '../models/category_model.dart';
import 'auth_provider.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository();
});

final categoriesStreamProvider =
    StreamProvider.family<List<CategoryModel>, TransactionType?>((ref, type) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(categoryRepositoryProvider).watchCategories(uid, type: type);
});

/// Categories keyed by id, so transaction lists can render each row with its
/// own category icon and colour without a lookup per row. Archived categories
/// are absent, and callers fall back to a generic icon for those.
final categoryLookupProvider = Provider<Map<String, CategoryModel>>((ref) {
  final categories =
      ref.watch(categoriesStreamProvider(null)).asData?.value ?? const [];
  return {for (final c in categories) c.id: c};
});

class CategoryActionsNotifier extends Notifier<AsyncValue<void>> {
  late CategoryRepository _repo;
  String? _uid;

  @override
  AsyncValue<void> build() {
    _repo = ref.watch(categoryRepositoryProvider);
    _uid = ref.watch(currentUidProvider);
    return const AsyncData(null);
  }

  Future<bool> addCategory(CategoryModel category) async {
    if (_uid == null) return false;
    state = const AsyncLoading();
    final result = await _repo.addCategory(_uid!, category);
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

  Future<bool> updateCategory(CategoryModel category) async {
    if (_uid == null) return false;
    final result = await _repo.updateCategory(_uid!, category);
    return result.isSuccess;
  }

  Future<bool> removeCategory(CategoryModel category, {required bool hasTransactions}) async {
    if (_uid == null) return false;
    final result = await _repo.deleteOrArchiveCategory(
      _uid!,
      category,
      hasTransactions: hasTransactions,
    );
    return result.isSuccess;
  }
}

final categoryActionsProvider =
    NotifierProvider<CategoryActionsNotifier, AsyncValue<void>>(
  CategoryActionsNotifier.new,
);
