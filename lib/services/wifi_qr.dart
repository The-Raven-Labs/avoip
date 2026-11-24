/// A Wi-Fi network read from the standard Wi-Fi QR code, e.g. the one printed
/// on an SC-1's label:
///
///   WIFI:T:WPA;S:Authentic-SC1-2063;P:XXXX-XXXX-XXXX;;
///
/// Fields are `KEY:value` separated by `;`. Inside a value, `\` escapes the
/// characters `\` `;` `,` `:` and `"`. A value wrapped in double quotes is
/// taken literally (that is how a name or password made only of hex digits is
/// told apart from raw hex).
///
/// The password is a secret: it is never printed by [toString].
class WifiQr {
  /// The network name.
  final String ssid;

  /// Null for an open network.
  final String? password;

  /// As written in the code: "WPA", "WEP", "nopass", ... upper-cased, or ""
  /// when the code doesn't say.
  final String security;

  /// True if the network doesn't broadcast its name.
  final bool hidden;

  const WifiQr({
    required this.ssid,
    this.password,
    this.security = '',
    this.hidden = false,
  });

  bool get isOpen => password == null || security == 'NOPASS';

  /// An SC-1's own hotspot: "Authentic-SC1-2063" (the unit's number), or the
  /// factory "Authentic-SC1" on older units. The app should only join networks that
  /// pass this check, never an arbitrary one from a scanned code.
  bool get isSc1Hotspot => _sc1Hotspot.hasMatch(ssid);

  static final RegExp _sc1Hotspot = RegExp(r'^Authentic-SC1(-\d+)?$');

  /// Reads [payload], or returns null if it isn't a usable Wi-Fi code (no
  /// `WIFI:` prefix, no network name, or a kind of network that needs more
  /// than a password, such as WPA-Enterprise).
  static WifiQr? parse(String payload) {
    final text = payload.trim();
    if (text.length < 5 || text.substring(0, 5).toUpperCase() != 'WIFI:') {
      return null;
    }

    String? ssid;
    String? password;
    var security = '';
    var hidden = false;
    var enterprise = false;

    for (final field in _split(text.substring(5), ';')) {
      final colon = _indexOfUnescaped(field, ':');
      if (colon <= 0) continue;
      final key = field.substring(0, colon).toUpperCase();
      final value = _value(field.substring(colon + 1));
      switch (key) {
        case 'S':
          ssid = value;
        case 'P':
          password = value;
        case 'T':
          security = value.toUpperCase();
        case 'H':
          hidden = value.toLowerCase() == 'true';
        case 'E' || 'I':
          // An EAP method or identity: WPA-Enterprise isn't a password.
          if (value.isNotEmpty) enterprise = true;
      }
    }

    if (ssid == null || ssid.isEmpty || enterprise) return null;
    if (security.contains('EAP')) return null;
    return WifiQr(
      ssid: ssid,
      password: password == null || password.isEmpty ? null : password,
      security: security,
      hidden: hidden,
    );
  }

  // Splits on [separator] where it isn't escaped, keeping the escapes in the
  // pieces so they are removed exactly once, later.
  static List<String> _split(String text, String separator) {
    final parts = <String>[];
    final current = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == r'\' && i + 1 < text.length) {
        current
          ..write(c)
          ..write(text[++i]);
      } else if (c == separator) {
        parts.add(current.toString());
        current.clear();
      } else {
        current.write(c);
      }
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts;
  }

  static int _indexOfUnescaped(String text, String char) {
    for (var i = 0; i < text.length; i++) {
      if (text[i] == r'\') {
        i++;
      } else if (text[i] == char) {
        return i;
      }
    }
    return -1;
  }

  // A quoted value is literal; otherwise `\` + one of `\ ; , : "` is that
  // character. Any other backslash is kept, as a code that didn't escape it
  // meant a real backslash.
  static String _value(String raw) {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1);
    }
    return raw.replaceAllMapped(RegExp(r'\\([\\;,:"])'), (m) => m.group(1)!);
  }

  @override
  String toString() =>
      'WifiQr(ssid: $ssid, security: $security, hidden: $hidden, '
      'password: ${password == null ? 'none' : '<hidden>'})';
}
