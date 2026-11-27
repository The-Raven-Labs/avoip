import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

/// How routing one receiver went.
class RouteResult {
  final bool success;

  /// What the receiver was pointed at (a channel, or a Tx IP); null if it
  /// failed or the controller didn't say.
  final String? target;
  const RouteResult({required this.success, this.target});
}

/// How routing several receivers went.
class BatchRouteResult {
  /// Receiver IPs the controller didn't confirm.
  final Set<String> failed;

  /// For each receiver that worked: what it was pointed at.
  final Map<String, String> targets;
  const BatchRouteResult({required this.failed, this.targets = const {}});
}

/// Sends AV routing commands to the controller:
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/set
///   Body: { "device_ip": "`receiver ip`", "tx_ip": "`transmitter ip`" }
///   -> { "success", "ack", "duration_ms", "target" }
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/set/batch
///   Body: { "items": [{ "device_ip": "...", "tx_ip": "..." }, ...] }  (max 50)
///   -> { "results": [{ "success", "device_ip", "tx_ip", "target", ... }],
///        "succeeded", "failed" }
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/stop
///   Body: { "device_ip": "`receiver ip`" }
///   -> { "success", "ack", "duration_ms" }
///
/// The request is still "this receiver shows that transmitter's IP". The
/// controller then points the receiver at the transmitter's 4-digit channel,
/// so the route survives IP changes (boxes on a 169.254 network can change
/// IP). `target` is what the receiver was pointed at: a channel such as
/// "0032", or the Tx IP when the channel couldn't be used.
///
/// The controller answers 200 even when a box didn't respond, so success
/// is read from the body, not the status code.
class AVCommandService {
  static const Map<String, String> _headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
  };

  // The controller accepts at most this many pairs per batch call.
  static const int _maxBatchItems = 50;

  static Future<http.Response> _post(String path, Map<String, dynamic> body) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final encoded = jsonEncode(body);
    debugPrint('[AVCommandService] POST $uri  body=$encoded');
    return http
        .post(uri, headers: _headers, body: encoded)
        .timeout(const Duration(seconds: 8));
  }

  // True when the call returned 2xx and the box confirmed it.
  @visibleForTesting
  static bool acked(http.Response response) {
    debugPrint(
      '[AVCommandService] ← [${response.statusCode}] ${response.body}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// The `target` of a `/commands/set` reply, or null if it has none.
  @visibleForTesting
  static String? targetOf(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? _target(decoded['target']) : null;
    } catch (_) {
      return null;
    }
  }

  static String? _target(Object? raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Routes video from a transmitter to a single receiver.
  static Future<RouteResult> routeVideo({
    required String txIp,
    required String rxIp,
  }) async {
    try {
      final response = await _post('/api/v1/commands/set', {
        'device_ip': rxIp,
        'tx_ip': txIp,
      });
      final ok = acked(response);
      return RouteResult(success: ok, target: ok ? targetOf(response) : null);
    } catch (e) {
      debugPrint('[AVCommandService] FAILED tx_ip=$txIp device_ip=$rxIp: $e');
      return const RouteResult(success: false);
    }
  }

  /// Routes many receivers at once; [txIpByRxIp] maps each receiver to the
  /// transmitter it should show, so different receivers can get different
  /// sources. The result names the receivers that failed (none when all
  /// worked) and what each of the others was pointed at.
  static Future<BatchRouteResult> routeBatch(
    Map<String, String> txIpByRxIp,
  ) async {
    final failed = <String>{};
    final targets = <String, String>{};
    final pairs = txIpByRxIp.entries.toList();
    for (var i = 0; i < pairs.length; i += _maxBatchItems) {
      final chunk = pairs.skip(i).take(_maxBatchItems).toList();
      final result = await _routeChunk(chunk);
      failed.addAll(result.failed);
      targets.addAll(result.targets);
    }
    return BatchRouteResult(failed: failed, targets: targets);
  }

  static Future<BatchRouteResult> _routeChunk(
    List<MapEntry<String, String>> pairs,
  ) async {
    final rxIps = pairs.map((p) => p.key).toSet();
    try {
      final response = await _post('/api/v1/commands/set/batch', {
        'items': [
          for (final p in pairs) {'device_ip': p.key, 'tx_ip': p.value},
        ],
      });
      return BatchRouteResult(
        failed: failedReceivers(rxIps, response),
        targets: targetsByReceiver(response),
      );
    } catch (e) {
      debugPrint('[AVCommandService] BATCH FAILED $pairs: $e');
      return BatchRouteResult(failed: rxIps);
    }
  }

  /// What each receiver in a batch [response] was pointed at (only those
  /// that worked and reported a target).
  @visibleForTesting
  static Map<String, String> targetsByReceiver(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) return {};
    try {
      final decoded = jsonDecode(response.body);
      final results = decoded is Map ? decoded['results'] : null;
      if (results is! List) return {};
      return {
        for (final r in results)
          if (r is Map &&
              r['success'] == true &&
              r['device_ip'] != null &&
              _target(r['target']) != null)
            r['device_ip'].toString(): _target(r['target'])!,
      };
    } catch (_) {
      return {};
    }
  }

  /// The receivers in [rxIps] that a batch [response] didn't confirm.
  @visibleForTesting
  static Set<String> failedReceivers(
    Set<String> rxIps,
    http.Response response,
  ) {
    debugPrint(
      '[AVCommandService] ← [${response.statusCode}] ${response.body}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return rxIps;
    try {
      final decoded = jsonDecode(response.body);
      final results = decoded is Map ? decoded['results'] : null;
      if (results is! List) return rxIps;
      final ok = {
        for (final r in results)
          if (r is Map && r['success'] == true) r['device_ip'].toString(),
      };
      return rxIps.difference(ok);
    } catch (_) {
      return rxIps;
    }
  }

  /// Stops whatever is currently routed to a receiver.
  static Future<bool> stopRoute({required String rxIp}) async {
    try {
      final response = await _post('/api/v1/commands/stop', {
        'device_ip': rxIp,
      });
      return acked(response);
    } catch (e) {
      debugPrint('[AVCommandService] STOP FAILED device_ip=$rxIp: $e');
      return false;
    }
  }
}
