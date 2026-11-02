/// Backend settings, injected with `--dart-define=API_BASE_URL=...`.
///
/// * Android emulator: `http://10.0.2.2:8080` (the host computer's localhost).
/// * Physical device: `http://<LAN IP of the computer>:8080`, or an HTTPS URL.
/// When empty the app keeps working fully offline against the local SQLite database.
class ApiConfig {
  const ApiConfig._();

  static const String _raw = String.fromEnvironment('API_BASE_URL');

  /// Base URL without trailing slash; empty when the backend is not configured.
  static String get baseUrl => _raw.replaceAll(RegExp(r'/+$'), '');

  static bool get enabled => baseUrl.isNotEmpty;

  static const Duration timeout = Duration(seconds: 20);
}
