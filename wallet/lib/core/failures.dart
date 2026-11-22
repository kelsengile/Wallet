/// Base type for errors surfaced from services and the database layer.
sealed class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class DatabaseFailure extends Failure {
  const DatabaseFailure([super.message = 'Could not read or save your data.']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No connection. Check your network and try again.']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Sign-in failed. Check your details and try again.']);
}

class SyncFailure extends Failure {
  const SyncFailure([super.message = 'Sync failed. Your changes are saved on this device.']);
}

class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Some of the information is invalid.']);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong.']);
}