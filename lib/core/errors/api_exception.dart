/// Error returned by the backend (`{"code","message"}`) or raised by the network layer.
class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'ERROR', this.status = 0});

  /// User-safe Vietnamese text, ready to show in a snackbar or dialog.
  final String message;
  final String code;

  /// HTTP status, 0 when no response was received.
  final int status;

  bool get isUnauthorized => status == 401;
  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiException($status $code: $message)';
}
