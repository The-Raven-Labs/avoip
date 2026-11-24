import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the app's traffic on Wi-Fi (Android only).
///
/// The SC-1's own hotspot has no internet. Android then tends to send an
/// app's requests over mobile data instead, so the controller can't be
/// reached even though the phone is connected to it. Binding the app's
/// process to the Wi-Fi network makes every request, including the preview
/// pictures, go out over Wi-Fi.
///
/// Safe to call often: it does nothing on other platforms, and on a Wi-Fi that
/// already has internet it changes nothing. Call [bindToWifi] again after the
/// phone may have changed Wi-Fi, because the binding follows one network.
class NetworkBinding {
  static const MethodChannel _channel = MethodChannel(
    'com.authenticav/network',
  );

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Routes the app's traffic over the phone's Wi-Fi. Returns false if the
  /// phone has no Wi-Fi connection (or this isn't Android).
  static Future<bool> bindToWifi() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('bindToWifi') ?? false;
    } on PlatformException catch (e) {
      debugPrint('NetworkBinding: bindToWifi failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Lets Android choose the network for the app's traffic again.
  static Future<void> release() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException catch (e) {
      debugPrint('NetworkBinding: release failed: ${e.message}');
    } on MissingPluginException {
      // Nothing was bound.
    }
  }
}
