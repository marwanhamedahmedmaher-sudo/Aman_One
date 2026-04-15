import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_header.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';
import 'password_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    final cleaned = _phoneController.text.trim().replaceAll(RegExp(r'\s'), '');
    if (cleaned.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال رقم موبايل صحيح من 10 أرقام'),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    auth.setPhone(cleaned);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _loading = false);

      final result = auth.checkPhone(cleaned);

      if (!result.isFirstTime) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PasswordScreen()),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtpScreen(phone: cleaned, mode: OtpMode.firstTime),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                      // Label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('رقم الموبايل', style: AppTheme.labelText),
                          const SizedBox(width: 6),
                          const Icon(Icons.phone_outlined,
                              size: 18, color: AppColors.textMedium),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Phone input
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          textAlign: TextAlign.right,
                          style: AppTheme.inputText,
                          decoration: AppTheme.inputDecoration(
                            hintText: '01XXXXXXXXX',
                          ).copyWith(counterText: ''),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Login button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _handleContinue,
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
                              : Text('تسجيل الدخول',
                                  style: AppTheme.buttonText),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Forgot password link
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            );
                          },
                          child: Text('نسيت كلمة المرور؟',
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
