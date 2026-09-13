/// Safe copy shown in toasts / inline errors — never surface raw backend details.
const kSomethingWentWrong = 'Something went wrong. Please try again.';

/// Maps any failure/exception to a single user-facing message.
String userFacingError([Object? _]) => kSomethingWentWrong;
