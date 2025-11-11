import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/device.dart';
import '../models/position.dart';
import 'web_helper_stub.dart'
    if (dart.library.html) 'web_helper_web.dart' as web_helper;

class ApiService {
  final AuthService _authService = AuthService();

  String? _getWebToken() {
    if (!kIsWeb) return null;
    return web_helper.getTokenFromUrl();
  }

  Future<List<T>> _fetchList<T>({
    required String endpoint,
    required T Function(Map<String, dynamic>) fromJson,
    required String resourceName,
  }) async {
    final baseUrl = AuthService.baseUrl;
    final uri = Uri.parse('$baseUrl$endpoint');

    final headers = <String, String>{
      'accept': 'application/json',
    };

    // On web, use token from query string in Authorization header
    if (kIsWeb) {
      final token = _getWebToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    } else {
      // On native, use cookie authentication
      final cookie = await _authService.getCookie();
      if (cookie != null && cookie.isNotEmpty) {
        headers['Cookie'] = cookie;
      }
    }

    try {
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
        final items = data
            .map((json) => fromJson(json as Map<String, dynamic>))
            .toList();
        return items;
      } else {
        dev.log('Failed to fetch $resourceName: ${resp.statusCode}', name: 'API');
        return [];
      }
    } catch (e, stack) {
      dev.log('Error fetching $resourceName: $e', name: 'API', error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<Device>> fetchDevices() async {
    return _fetchList(
      endpoint: '/api/devices',
      fromJson: Device.fromJson,
      resourceName: 'devices',
    );
  }

  Future<List<Position>> fetchPositions() async {
    return _fetchList(
      endpoint: '/api/positions',
      fromJson: Position.fromJson,
      resourceName: 'positions',
    );
  }
}
