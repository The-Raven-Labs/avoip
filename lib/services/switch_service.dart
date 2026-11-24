import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'controller_api.dart';

export 'controller_api.dart' show ControllerApiException;

/// How the SC-1's last look at the network switch ended. Unknown values from
/// a newer controller become [unknown]; the card then shows the controller's
/// own message.
enum SwitchState {
  notConfigured,
  pending,
  ok,
  enabled,
  unsaved,
  unverified,
  failed,
  unreachable,
  authFailed,
  needsPassword,
  unknown;

  static SwitchState parse(String? raw) => switch (raw) {
    'not_configured' => notConfigured,
    'pending' => pending,
    'ok' => ok,
    'enabled' => enabled,
    'unsaved' => unsaved,
    'unverified' => unverified,
    'failed' => failed,
    'unreachable' => unreachable,
    'auth_failed' => authFailed,
    'needs_password' => needsPassword,
    _ => unknown,
  };

  /// IGMP is on, as far as the SC-1 can tell.
  bool get isGood => this == ok || this == enabled;
}

/// The multicast settings the SC-1 read from the switch. Any field is null if
/// the switch didn't report it.
class IgmpSettings {
  final bool? snooping;
  final bool? vlanSnooping;
  final bool? querier;
  final bool? vlanQuerier;

  /// e.g. "Non-Querier": another device is currently asking the questions.
  final String? querierRole;

  const IgmpSettings({
    this.snooping,
    this.vlanSnooping,
    this.querier,
    this.vlanQuerier,
    this.querierRole,
  });

  factory IgmpSettings.fromJson(Map json) {
    bool? flag(String key) => json[key] is bool ? json[key] as bool : null;
    final role = json['querier_role']?.toString().trim();
    return IgmpSettings(
      snooping: flag('snooping'),
      vlanSnooping: flag('vlan_snooping'),
      querier: flag('querier'),
      vlanQuerier: flag('vlan_querier'),
      querierRole: role == null || role.isEmpty ? null : role,
    );
  }
}

/// `GET /api/v1/switch`: the SC-1's last result of checking its network
/// switch. The switch password is never part of it.
class SwitchStatus {
  /// False when this SC-1 has no managed switch to look after.
  final bool configured;

  /// The controller's name for the switch driver, e.g. "netgear_m4250".
  final String? driver;

  /// The switch's address, as the SC-1 uses it.
  final String? host;
  final int? vlan;
  final SwitchState state;

  /// What the controller says went wrong (or null). Shown for every state
  /// except `ok`.
  final String? message;
  final IgmpSettings? igmp;
  final DateTime? checkedAt;

  /// When the SC-1 last had to change the switch itself.
  final DateTime? changedAt;

  const SwitchStatus({
    required this.configured,
    required this.state,
    this.driver,
    this.host,
    this.vlan,
    this.message,
    this.igmp,
    this.checkedAt,
    this.changedAt,
  });

  /// "Netgear M4250" from "netgear_m4250".
  String get displayName {
    final words = (driver ?? '').split('_').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'Network switch';
    return [
      words.first[0].toUpperCase() + words.first.substring(1),
      for (final w in words.skip(1)) w.toUpperCase(),
    ].join(' ');
  }

  factory SwitchStatus.fromJson(Map json) {
    String? text(String key) {
      final v = json[key]?.toString().trim();
      return v == null || v.isEmpty ? null : v;
    }

    final configured = json['configured'] != false;
    final rawState = text('state');
    return SwitchStatus(
      configured: configured,
      // A reply without a state, for a unit with no switch, is "not configured".
      state:
          rawState == null && !configured
              ? SwitchState.notConfigured
              : SwitchState.parse(rawState),
      driver: text('driver'),
      host: text('host'),
      vlan: json['vlan'] is num ? (json['vlan'] as num).toInt() : null,
      message: text('message'),
      igmp: json['igmp'] is Map ? IgmpSettings.fromJson(json['igmp']) : null,
      checkedAt: DateTime.tryParse(text('checked_at') ?? '')?.toLocal(),
      changedAt: DateTime.tryParse(text('changed_at') ?? '')?.toLocal(),
    );
  }
}

/// The controller's network switch API:
///   GET  /api/v1/switch        the last result, immediately
///   POST /api/v1/switch/igmp   check now (and set IGMP up if it isn't):
///                              a few seconds, up to about 3 minutes
/// There is no password endpoint yet, and no reply carries a password.
class SwitchService {
  static const Map<String, String> _headers = {'accept': 'application/json'};
  static const Duration _timeout = Duration(seconds: 10);

  /// A check can take about 3 minutes in the worst case.
  static const Duration checkTimeout = Duration(seconds: 200);

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v1/switch$path');

  static Future<SwitchStatus> fetch() async {
    final response = await _send(
      () => http.get(_uri(''), headers: _headers),
      timeout: _timeout,
    );
    return parse(response.body);
  }

  /// Runs a check on the SC-1 and returns its result.
  static Future<SwitchStatus> checkNow() async {
    final response = await _send(
      () => http.post(_uri('/igmp'), headers: _headers),
      timeout: checkTimeout,
      timeoutMessage:
          'The switch check is taking longer than expected. Pull down to '
          'refresh in a minute to see the result.',
    );
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['state'] != null) {
        return SwitchStatus.fromJson(decoded);
      }
    } on FormatException {
      // Fall through: ask for the stored result instead.
    }
    return fetch();
  }

  @visibleForTesting
  static SwitchStatus parse(String body) {
    const unreadable = ControllerApiException(
      'The controller sent an unreadable switch status.',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw unreadable;
    }
    if (decoded is! Map) throw unreadable;
    return SwitchStatus.fromJson(decoded);
  }

  // Only the method, path and status are logged.
  static Future<http.Response> _send(
    Future<http.Response> Function() request, {
    required Duration timeout,
    String? timeoutMessage,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ControllerApiException(
        timeoutMessage ?? "Couldn't reach the controller at ${ApiConfig.ip}.",
      );
    } catch (e) {
      debugPrint('SwitchService: $e');
      throw ControllerApiException(
        "Couldn't reach the controller at ${ApiConfig.ip}.",
      );
    }
    debugPrint(
      'SwitchService: ${response.request?.method} ${response.request?.url.path}'
      ' ← ${response.statusCode}',
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw ControllerApiException(
      ControllerApiException.messageFor(
        response.statusCode,
        response.body,
        feature: 'network switch status',
      ),
      statusCode: response.statusCode,
    );
  }
}
