import 'package:flutter/material.dart';

import '../logic/app_state.dart';
import '../theme/app_theme.dart';

/// Shown at login when an account still has the default or an admin-set
/// password. Pops `true` once the user has set their own.
class ChangePasswordScreen extends StatefulWidget {
  final UserAccount user;
  const ChangePasswordScreen({super.key, required this.user});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = "The passwords don't match.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final problem = await AppState.instance.changeOwnPassword(
      widget.user,
      _newCtrl.text,
    );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _saving = false;
        _error = problem;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey),
    prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54),
    suffixIcon: IconButton(
      icon: Icon(
        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: Colors.white54,
      ),
      tooltip: _obscure ? 'Show password' : 'Hide password',
      onPressed: () => setState(() => _obscure = !_obscure),
    ),
    border: InputBorder.none,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(backgroundColor: AppTheme.backgroundLight, elevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  const Icon(
                    Icons.password_rounded,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Set a new password',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.user.isRootAdmin
                        ? 'You signed in with the default password. Choose your '
                            'own before continuing.'
                        : 'Your password was set by an admin. Choose your own '
                            'before continuing.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _newCtrl,
                          obscureText: _obscure,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: _decoration('New password'),
                        ),
                        const Divider(color: Colors.white10),
                        TextField(
                          controller: _confirmCtrl,
                          obscureText: _obscure,
                          style: const TextStyle(color: Colors.white),
                          decoration: _decoration('Confirm password'),
                          onSubmitted: (_) => _save(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'At least ${UserAccount.minPasswordLength} characters, '
                          'not "${UserAccount.defaultPassword}" or your username.',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentWhite,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child:
                                _saving
                                    ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                    : const Text(
                                      'Save and continue',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
