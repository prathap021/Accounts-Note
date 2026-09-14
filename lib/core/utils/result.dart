/// A lightweight Result/Either type so repositories never throw raw
/// exceptions into the UI layer. Every repository method returns
/// `Result<T>` and the Notifier decides how to surface `AppFailure`.
sealed class Result<T> {
  const Result();

  factory Result.success(T data) = Success<T>;
  factory Result.failure(AppFailure failure) = Failure<T>;

  R when<R>({
    required R Function(T data) success,
    required R Function(AppFailure failure) failure,
  }) {
    final self = this;
    if (self is Success<T>) return success(self.data);
    if (self is Failure<T>) return failure(self.failure);
    throw StateError('Unreachable');
  }

  bool get isSuccess => this is Success<T>;
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final AppFailure failure;
  const Failure(this.failure);
}

class AppFailure implements Exception {
  /// Internal detail (logging). Prefer [userMessage] in the UI.
  final String message;
  final String? code;
  final Object? cause;

  const AppFailure(this.message, {this.code, this.cause});

  /// Safe copy for toasts / on-screen errors.
  /// Repositories put user-facing text in [message]; [fromException] stays generic.
  String get userMessage => message;

  factory AppFailure.fromException(Object e) {
    return AppFailure(
      'Something went wrong. Please try again.',
      code: 'unknown',
      cause: e.toString(),
    );
  }

  @override
  String toString() => 'AppFailure(code: $code, message: $message)';
}
