import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'controller_api.dart';

export 'controller_api.dart' show ControllerApiException;

/// A one-time code from the SC-1 that allows a factory reset.
class ResetPreparation {
  final String confirmCode;
  final int expiresInSeconds;

  /// False when this SC-1 isn't allowed to forget its saved Wi-Fi; the rest
  /// is still cleared.
  final bool wifiCanBeCleared;

  const ResetPreparation({
    required this.confirmCode,
    required this.expiresInSeconds,
    required this.wifiCanBeCleared,
  });
}

/// What the SC-1 cleared.
class ResetResult {
  final List<String> cleared;

  /// "scheduled": it leaves its Wi-Fi in a few seconds. "not_permitted":
  /// the Wi-Fi was kept. Anything else is passed through as reported.
  final String? wifi;

  const ResetResult({required this.cleared, required this.wifi});

  bool get leavesWifi => wifi == 'scheduled';
}

/// SC-1 factory reset, two calls so it can't happen by accident:
///   POST /api/v1/system/reset/prepare
///     → {confirm_code, expires_in_seconds, wifi_can_be_cleared}
///   POST /api/v1/system/reset {"confirm_code": "..."}
///     → 200 {cleared, wifi}, or 403 confirm_code_invalid (wrong, used or
///       older than 60 s: prepare again).
/// Clears scenes, settings, the device list and saved Wi-Fi on the SC-1;
/// the Tx/Rx boxes and the SC-1 software aren't touched.
class SystemResetService {
  static const Duration _timeout = Duration(seconds: 15);
  static const Map<String, String> _headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
  };

  static Future<ResetPreparation> prepare() async {
    final body = await _post('/api/v1/system/reset/prepare', null);
    final code = body['confirm_code']?.toString() ?? '';
    if (code.isEmpty) {
      throw const ControllerApiException(
        'The controller sent no confirmation code.',
      );
    }
    final expires = body['expires_in_seconds'];
    return ResetPreparation(
      confirmCode: code,
      expiresInSeconds: expires is num ? expires.toInt() : 60,
      wifiCanBeCleared: body['wifi_can_be_cleared'] == true,
    );
  }

  static Future<ResetResult> reset(String confirmCode) async {
    final body = await _post('/api/v1/system/reset', {
      'confirm_code': confirmCode,
    });
    final cleared = body['cleared'];
    return ResetResult(
      cleared: [
        if (cleared is List)
          for (final c in cleared) c.toString(),
      ],
      wifi: body['wifi']?.toString(),
    );
  }

  /// True when the code was wrong, already used or expired.
  static bool isInvalidCode(ControllerApiException e) => e.statusCode == 403;

  static Future<Map> _post(String path, Map<String, String>? body) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: _headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (e) {
      debugPrint('SystemResetService: $e');
      throw ControllerApiException(
        "Couldn't reach the controller at ${ApiConfig.ip}.",
      );
    }
    debugPrint('SystemResetService: POST $path ← ${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ControllerApiException(
        response.statusCode == 403
            ? 'The confirmation code expired. Please confirm again.'
            : ControllerApiException.messageFor(
              response.statusCode,
              response.body,
              feature: 'factory reset',
            ),
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
