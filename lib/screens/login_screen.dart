import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'server_setup_screen.dart';
import '../logic/app_state.dart';
import '../config/session.dart';
import 'change_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;

  void _executeLogin() async {
    final u = _usernameCtrl.text.trim();
    // Passwords are taken exactly as typed.
    final p = _passwordCtrl.text;

    if (u.isEmpty || p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter credentials.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    var user = AppState.instance.userNamed(u);
    if (user == null || !user.checkPassword(p)) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid username or password.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // The default password, or one an admin set, must be replaced first.
    if (user.mustChangePassword) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ChangePasswordScreen(user: user!)),
      );
      if (!mounted) return;
      if (changed != true) {
        setState(() => _isLoading = false);
        _passwordCtrl.clear();
        return;
      }
      user = AppState.instance.userNamed(u)!;
    }

    if (_rememberMe) {
      await Session.remember(user.username);
    } else {
      await Session.forget();
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ServerSetupScreen(isAdmin: user!.isAdmin),
        ),
      );
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _showForgotPasswordHelp() {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppTheme.brandCard,
            title: const Text(
              'Forgot password?',
              style: TextStyle(color: AppTheme.brandTextPrimary),
            ),
            content: const Text(
              'Ask your Authentic AV administrator to reset your password.',
              style: TextStyle(color: AppTheme.brandTextSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'OK',
                  style: TextStyle(color: AppTheme.brandPrimary),
                ),
              ),
            ],
          ),
    );
  }

  Widget _credentialField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.brandTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 58,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: const TextStyle(
              color: AppTheme.brandTextPrimary,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppTheme.brandTextMuted),
              prefixIcon: Icon(icon, color: AppTheme.brandTextMuted),
              suffixIcon: suffixIcon,
              filled: true,
              fillColor: AppTheme.brandCard,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.brandBorderInput),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppTheme.brandPrimary,
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.brandBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppTheme.brandBackground),
          Positioned(top: -155, left: -150, child: _CornerGlow(size: 360)),
          Positioned(bottom: -205, right: -180, child: _CornerGlow(size: 440)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Container(
                        width: 82,
                        height: 82,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.brandCard,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.brandBorder),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14111827),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Image(
                          image: AssetImage(
                            'assets/images/auth.av_icon_v2.png',
                          ),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 23,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandTextPrimary,
                          ),
                          children: [
                            TextSpan(text: 'AUTHENTIC '),
                            TextSpan(
                              text: 'AV',
                              style: TextStyle(color: AppTheme.brandPrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(color: AppTheme.brandBorder),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'C O N T R O L   S Y S T E M',
                              style: TextStyle(
                                color: AppTheme.brandTextMuted,
                                fontSize: 11,
                                letterSpacing: 2.2,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(color: AppTheme.brandBorder),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'The Authentic AV\nexperience.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.brandTextPrimary,
                          fontSize: 32,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cinematic in every sense.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.brandPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Authenticate for Control.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.brandTextMuted,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        decoration: BoxDecoration(
                          color: AppTheme.brandCard,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.brandBorder),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A111827),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _credentialField(
                              controller: _usernameCtrl,
                              label: 'Username',
                              hint: 'Enter username',
                              icon: Icons.person_outline,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),
                            _credentialField(
                              controller: _passwordCtrl,
                              label: 'Password',
                              hint: 'Enter password',
                              icon: Icons.lock_outline,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _executeLogin(),
                              suffixIcon: IconButton(
                                tooltip:
                                    _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                onPressed:
                                    () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppTheme.brandTextMuted,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged:
                                      (value) => setState(
                                        () => _rememberMe = value ?? false,
                                      ),
                                  activeColor: AppTheme.brandPrimary,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  side: const BorderSide(
                                    color: AppTheme.brandBorderInput,
                                  ),
                                ),
                                const Text(
                                  'Remember me',
                                  style: TextStyle(
                                    color: AppTheme.brandTextPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _showForgotPasswordHelp,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.brandPrimary,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppTheme.brandPrimaryDark,
                                      AppTheme.brandPrimary,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _executeLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    disabledBackgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child:
                                      _isLoading
                                          ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Text(
                                            'Sign In',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 18,
                                            ),
                                          ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerGlow extends StatelessWidget {
  final double size;
  const _CornerGlow({required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [AppTheme.brandPrimarySoft, Color(0x00EDE9FE)],
          stops: [0, 1],
        ),
      ),
    ),
  );
}
