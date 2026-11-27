import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/logic/app_state.dart';

void main() {
  test('stores a salted hash, never the password', () {
    final a = UserAccount.withPassword(
      id: 'u1', username: 'admin', role: 'Admin', password: 'Lobby#2026', mustChangePassword: false,
    );
    final b = UserAccount.withPassword(
      id: 'u2', username: 'ops', role: 'User', password: 'Lobby#2026', mustChangePassword: false,
    );
    expect(a.passwordHash, isNot(contains('Lobby')));
    // Same password, different salt, different hash.
    expect(a.salt, isNot(b.salt));
    expect(a.passwordHash, isNot(b.passwordHash));
    expect(a.checkPassword('Lobby#2026'), isTrue);
    expect(a.checkPassword('lobby#2026'), isFalse);
    expect(a.checkPassword(''), isFalse);
  });

  test('rejects weak or default passwords', () {
    expect(UserAccount.passwordProblem('admin', 'admin'), isNotNull);
    expect(UserAccount.passwordProblem('admin', '12345'), isNotNull); // too short
    expect(UserAccount.passwordProblem('johnsmith', 'JohnSmith'), isNotNull); // = username
    expect(UserAccount.passwordProblem('admin', 'Lobby#2026'), isNull);
  });

  test('default account details', () {
    expect(UserAccount.defaultUsername, 'admin');
    expect(UserAccount.defaultPassword, 'admin');
    expect(UserAccount.rootAdminId, 'u1');
  });
}
