import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'otp_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final cleaned = _phoneController.text.trim().replaceAll(RegExp(r'\s'), '');
    if (cleaned.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رقم موبايل صحيح')),
      );
      return;
    }

    setState(() => _loading = true);
    context.read<AuthProvider>().setPhone(cleaned);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _loading = false);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: cleaned,
            mode: OtpMode.forgotPassword,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Back button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.primary),
                  label: Text('العودة لتسجيل الدخول',
                      style: AppTheme.linkText.copyWith(fontSize: 13)),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Key icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.key_outlined,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text('استعادة كلمة المرور', style: AppTheme.heading2),
              const SizedBox(height: 28),
              // Phone label
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('رقم الموبايل', style: AppTheme.labelText),
                  const SizedBox(width: 6),
                  const Icon(Icons.phone_outlined,
                      size: 16, color: AppColors.textMedium),
                ],
              ),
              const SizedBox(height: 8),
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
              // Send OTP button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _handleSend,
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
                      : Text('إرسال رمز التحقق', style: AppTheme.buttonText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
