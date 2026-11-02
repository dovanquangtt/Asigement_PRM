import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import 'auth_service.dart';

/// Sign-in against the Spring Boot API. On success the bearer token is kept in the
/// [ApiClient] token store so every later API call is authenticated.
class BackendAuth {
  BackendAuth([ApiClient? client]) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<UserSession> login(String username, String password) =>
      _authenticate('/api/auth/login', {
        'username': username.trim(),
        'password': password,
      });

  Future<UserSession> loginWithGoogle(String idToken) =>
      _authenticate('/api/auth/google', {'idToken': idToken});

  Future<UserSession> _authenticate(String path, Object body) async {
    try {
      final data =
          (await _client.request('POST', path, body: body, auth: false))
              as Map<String, dynamic>;
      await _client.tokens.write(data['accessToken'] as String);
      return sessionFrom(data['session'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<void> signOut() => _client.tokens.clear();

  static UserSession sessionFrom(Map<String, dynamic> s) => UserSession(
    userId: (s['userId'] as num).toInt(),
    username: s['username'] as String,
    role: s['role'] as String,
    permissions: Set.unmodifiable((s['permissions'] as List).cast<String>()),
    profile: Map.unmodifiable(
      Map<String, Object?>.from(s['profile'] as Map<dynamic, dynamic>),
    ),
  );
}
