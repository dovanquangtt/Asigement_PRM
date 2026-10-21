import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google verifies identity; application roles are always read from SQLite.
abstract interface class GoogleAuth {
  Future<({String id, String email})> authenticate();
  Future<void> signOut();
}

class DeviceGoogleAuth implements GoogleAuth {
  static Future<void>? _initialization;

  Future<void> _initialize() async {
    const serverId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    if (serverId.isEmpty) {
      throw StateError('GOOGLE_WEB_CLIENT_ID');
    }
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: serverId,
      ));
    } catch (_) {
      // A failed initialization must not prevent retrying in this process.
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<({String id, String email})> authenticate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Google sign-in is configured for Android.');
    }
    await _initialize();
    await GoogleSignIn.instance.signOut();
    final account = await GoogleSignIn.instance.authenticate();
    return (id: account.id, email: account.email);
  }

  @override
  Future<void> signOut() async {
    if (_initialization != null) {
      await _initialization;
      await GoogleSignIn.instance.signOut();
    }
  }
}
