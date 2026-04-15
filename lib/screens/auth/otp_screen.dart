import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/otp_input.dart';
import 'set_password_screen.dart';

enum OtpMode { firstTime, forgotPassword }

class OtpScreen extends StatefulWidget {
  final String phone;
  final OtpMode mode;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.mode,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _otp = '';
  bool _loading = false;
  int _timer = 580; // 9:40
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timer <= 0) {
        timer.cancel();
      } else {
        setState(() => _timer--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String get _formattedTimer {
    final minutes = _timer ~/ 60;
    final seconds = _timer % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleVerify() {
    if (_otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رمز التحقق كاملاً')),
      );
      return;
    }

    setState(() => _loading = true);

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _loading = false);

      final auth = context.read<AuthProvider>();
      final valid = auth.verifyOtp(_otp);

      if (!valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رمز التحقق غير صحيح. استخدم: 123456'),
          ),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SetPasswordScreen(mode: widget.mode),
        ),
      );
    });
  }

  void _handleResend() {
    setState(() {
      _timer = 580;
      _otp = '';
    });
    _startTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إرسال رمز التحقق مرة أخرى')),
    );
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
                    children: [
                      Text('أدخل رمز التحقق', style: AppTheme.heading3),
                      const SizedBox(height: 8),
                      Text(
                        'تم إرسال رمز التحقق إلى\n${widget.phone}',
                        style: AppTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      // OTP input
                      OtpInput(
                        onChanged: (val) => setState(() => _otp = val),
                      ),
                      const SizedBox(height: 16),
                      // Timer
                      Text(
                        'صالح لمدة $_formattedTimer',
                        style: AppTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      // Verify button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              (_loading || _otp.length < 6) ? null : _handleVerify,
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
                              : Text('تحقق', style: AppTheme.buttonText),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Resend
                      TextButton(
                        onPressed: _timer > 0 ? null : _handleResend,
                        child: Text(
                          'إعادة إرسال الرمز',
                          style: AppTheme.linkText.copyWith(
                            color: _timer > 0
                                ? AppColors.textLight
                                : AppColors.primary,
                          ),
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
