import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_header.dart';
import '../main/main_shell.dart';
import 'otp_screen.dart';
import 'phone_entry_screen.dart';

class SetPasswordScreen extends StatefulWidget {
  final OtpMode mode;

  const SetPasswordScreen({super.key, required this.mode});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _loading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_passwordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كلمة المرور يجب أن تحتوي على 8 أحرف على الأقل'),
        ),
      );
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمتا المرور غير متطابقتين')),
      );
      return;
    }

    setState(() => _loading = true);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _loading = false);

      if (widget.mode == OtpMode.forgotPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('تم تغيير كلمة المرور بنجاح. يمكنك تسجيل الدخول الآن.'),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
          (route) => false,
        );
      } else {
        final auth = context.read<AuthProvider>();
        auth.login();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (route) => false,
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
                      // Title
                      Text(
                        'تعيين كلمة مرور جديدة',
                        style: AppTheme.heading3,
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'يجب أن تحتوي على 8 أحرف على الأقل',
                        style: AppTheme.bodySmall,
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 20),
                      // New password label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('كلمة المرور الجديدة',
                              style: AppTheme.labelText),
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_outline,
                              size: 16, color: AppColors.textMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
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
                      // Confirm password label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('تأكيد كلمة المرور',
                              style: AppTheme.labelText),
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_outline,
                              size: 16, color: AppColors.textMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _confirmController,
                        obscureText: !_showConfirm,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        style: AppTheme.inputText,
                        decoration: AppTheme.inputDecoration(
                          hintText: '••••••••',
                        ).copyWith(
                          prefixIcon: IconButton(
                            icon: Icon(
                              _showConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.textLight,
                            ),
                            onPressed: () =>
                                setState(() => _showConfirm = !_showConfirm),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _handleSave,
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
                              : Text('حفظ', style: AppTheme.buttonText),
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
