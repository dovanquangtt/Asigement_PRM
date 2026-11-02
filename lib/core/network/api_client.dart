import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../errors/api_exception.dart';
import 'token_store.dart';

/// Thin JSON client for the Spring Boot API: base URL, bearer token, timeouts and error mapping.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, TokenStore? tokens})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl,
      tokens = tokens ?? SecureTokenStore();

  final http.Client _client;
  final String _baseUrl;
  final TokenStore tokens;

  /// Called once when the server answers 401 (expired or revoked token).
  void Function()? onUnauthorized;

  /// Shared instance used by the app. Tests build their own.
  static ApiClient instance = ApiClient();

  Uri _uri(String path, Map<String, Object?>? query) {
    final clean = <String, String>{
      for (final e in (query ?? const {}).entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
    };
    return Uri.parse('$_baseUrl$path').replace(
      queryParameters: clean.isEmpty ? null : clean,
    );
  }

  Future<Object?> request(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    bool auth = true,
  }) async {
    if (_baseUrl.isEmpty) {
      throw const ApiException(
        'Chưa cấu hình địa chỉ máy chủ (API_BASE_URL).',
        code: 'NOT_CONFIGURED',
      );
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    if (auth) {
      final token = await tokens.read();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(ApiConfig.timeout),
      );
    } on TimeoutException {
      throw const ApiException(
        'Máy chủ phản hồi quá lâu. Hãy thử lại.',
        code: 'TIMEOUT',
      );
    } on SocketException {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng và địa chỉ API.',
        code: 'NETWORK',
      );
    } on http.ClientException {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng và địa chỉ API.',
        code: 'NETWORK',
      );
    }
    final text = utf8.decode(response.bodyBytes);
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    if (response.statusCode == 401 && auth) onUnauthorized?.call();
    final map = decoded is Map<String, dynamic> ? decoded : const {};
    throw ApiException(
      map['message'] as String? ??
          (response.statusCode >= 500
              ? 'Máy chủ gặp lỗi. Hãy thử lại sau.'
              : 'Yêu cầu không hợp lệ.'),
      code: map['code'] as String? ?? 'HTTP_${response.statusCode}',
      status: response.statusCode,
    );
  }

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, Object?>? query,
  }) async =>
      (await request('GET', path, query: query) ?? const <String, dynamic>{})
          as Map<String, dynamic>;

  Future<List<dynamic>> getList(
    String path, {
    Map<String, Object?>? query,
  }) async =>
      (await request('GET', path, query: query) ?? const <dynamic>[])
          as List<dynamic>;

  Future<Map<String, dynamic>> postMap(String path, {Object? body}) async =>
      (await request('POST', path, body: body ?? const {}) ??
              const <String, dynamic>{})
          as Map<String, dynamic>;

  Future<void> post(String path, {Object? body}) async {
    await request('POST', path, body: body ?? const {});
  }

  Future<void> delete(String path) async {
    await request('DELETE', path);
  }

  void close() => _client.close();
}
