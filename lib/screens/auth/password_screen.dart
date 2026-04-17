import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_header.dart';
import '../main/main_shell.dart';
import 'change_password_screen.dart';

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('\u064a\u0631\u062c\u0649 \u0625\u062f\u062e\u0627\u0644 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631')),
      );
      return;
    }

    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    final result =
        await auth.signIn(auth.currentPhone, _passwordController.text);

    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                result.error ?? '\u0641\u0634\u0644 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644')),
      );
      return;
    }

    if (result.mustChangePassword) {
      // Navigate to change password screen for first-login rotation
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ChangePasswordScreen(isFirstLogin: true),
        ),
      );
      return;
    }

    // Successful login — check biometric opt-in opportunity
    await _offerBiometricSetup(auth);

    if (!mounted) return;

    // Navigate to main app
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  Future<void> _offerBiometricSetup(AuthProvider auth) async {
    try {
      // Check if biometric is available on device
      final canCheck = await auth.canUseBiometric();
      if (canCheck) return; // Already set up

      // Check if device supports biometrics at all
      final available = await auth.isBiometricAvailable();
      if (!available) return;

      if (!mounted) return;

      // Show opt-in dialog
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '\u062a\u0641\u0639\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0628\u0627\u0644\u0628\u0635\u0645\u0629',
            style: AppTheme.heading3,
            textAlign: TextAlign.right,
          ),
          content: Text(
            '\u0647\u0644 \u062a\u0631\u064a\u062f \u062a\u0641\u0639\u064a\u0644 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0628\u0627\u0644\u0628\u0635\u0645\u0629 \u0644\u0644\u0645\u0631\u0627\u062a \u0627\u0644\u0642\u0627\u062f\u0645\u0629\u061f',
            style: AppTheme.bodyMedium,
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('\u0644\u0627\u062d\u0642\u0627\u064b', style: AppTheme.linkText),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: AppTheme.primaryButton(),
              child: Text('\u062a\u0641\u0639\u064a\u0644', style: AppTheme.buttonText),
            ),
          ],
        ),
      );

      if (accepted == true) {
        await auth.enableBiometric(
            auth.currentPhone, _passwordController.text);
      }
    } catch (_) {
      // Silently skip biometric setup on error
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final phone = auth.currentPhone;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AuthHeader(height: 280),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Phone number display
                      Text(
                        phone,
                        style: AppTheme.bodyLarge.copyWith(
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Password label
                      Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 16, color: AppColors.textMedium),
                          const SizedBox(width: 6),
                          Text('\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631', style: AppTheme.labelText),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Password input
                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        style: AppTheme.inputText,
                        decoration: AppTheme.inputDecoration(
                          hintText: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                        ).copyWith(
                          prefixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.textLight,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Login button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _handleLogin,
                          style: AppTheme.primaryButton(),
                          child: _loading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text('\u062f\u062e\u0648\u0644', style: AppTheme.buttonText),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Change phone link
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('\u062a\u063a\u064a\u064a\u0631 \u0631\u0642\u0645 \u0627\u0644\u0645\u0648\u0628\u0627\u064a\u0644',
                              style: AppTheme.linkText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
