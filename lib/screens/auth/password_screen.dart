import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_header.dart';
import '../main/main_shell.dart';

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

  void _handleLogin() {
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال كلمة المرور')),
      );
      return;
    }

    setState(() => _loading = true);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _loading = false);

      final auth = context.read<AuthProvider>();
      auth.login(userData: auth.user);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

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
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Greeting
                      Text(
                        'مرحبا، ${user?.name ?? ''}',
                        style: AppTheme.bodyMedium,
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 4),
                      // Phone
                      Text(
                        user?.phone ?? '',
                        style: AppTheme.bodyLarge.copyWith(
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 20),
                      // Password label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('كلمة المرور', style: AppTheme.labelText),
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_outline,
                              size: 16, color: AppColors.textMedium),
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
                          hintText: '••••••••',
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
                              : Text('دخول', style: AppTheme.buttonText),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Change phone link
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('تغيير رقم الموبايل',
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
