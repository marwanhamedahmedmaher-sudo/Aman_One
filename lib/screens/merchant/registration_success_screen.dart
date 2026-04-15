import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class RegistrationSuccessScreen extends StatelessWidget {
  const RegistrationSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Success checkmark
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 48,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                Text(
                  'تم إرسال الطلب بنجاح',
                  style: AppTheme.heading2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                // Subtitle
                Text(
                  'سيتم مراجعة طلبك والرد عليك قريباً\nشكراً لاستخدام منصة أمان',
                  style: AppTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),

                const Spacer(flex: 3),

                // Back to home button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context)
                          .popUntil((route) => route.isFirst);
                    },
                    style: AppTheme.primaryButton(),
                    child: Text('العودة للرئيسية', style: AppTheme.buttonText),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
