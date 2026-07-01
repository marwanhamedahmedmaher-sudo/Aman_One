import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_header.dart';
import 'forgot_password_screen.dart';
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

  /// Normalizes a phone number to the internal 11-digit local form
  /// (`01XXXXXXXXX`), accepting an optional Egypt country code entered as
  /// `+20`, `0020`, `20`, `+2`, `+02`, etc. Returns null if the number is not
  /// a valid Egyptian mobile number.
  String? _normalizePhone(String raw) {
    // Keep digits only (drops '+', spaces, dashes, and any leading '00').
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('020')) {
      // Stray leading zero before the country code, e.g. "+02" + 01XXXXXXXXX.
      digits = digits.substring(1);
    }
    // Strip the Egypt country code (20) if present.
    if (digits.startsWith('20') && digits.length == 12) {
      digits = '0${digits.substring(2)}';
    } else if (digits.startsWith('1') && digits.length == 10) {
      // National number without the leading 0.
      digits = '0$digits';
    }

    // Valid Egyptian mobile: 11 digits, starts with 01.
    if (digits.length == 11 && digits.startsWith('01')) {
      return digits;
    }
    return null;
  }

  void _handleContinue() {
    final normalized = _normalizePhone(_phoneController.text);

    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u064a\u0631\u062c\u0649 \u0625\u062f\u062e\u0627\u0644 \u0631\u0642\u0645 \u0645\u0648\u0628\u0627\u064a\u0644 \u0635\u062d\u064a\u062d \u0645\u0646 11 \u0631\u0642\u0645'),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    auth.setPhone(normalized);

    // Small delay for visual feedback, then navigate to password
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _loading = false);

      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PasswordScreen()),
      );
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 18, color: AppColors.textMedium),
                          const SizedBox(width: 6),
                          Text('\u0631\u0642\u0645 \u0627\u0644\u0645\u0648\u0628\u0627\u064a\u0644', style: AppTheme.labelText),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Phone input
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 16,
                          textAlign: TextAlign.right,
                          style: AppTheme.inputText,
                          decoration: AppTheme.inputDecoration(
                            hintText: '01XXXXXXXXX أو 20+',
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
                              : Text('\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644',
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
                          child: Text('\u0646\u0633\u064a\u062a \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631\u061f',
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
