import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class LeadSuccessScreen extends StatelessWidget {
  const LeadSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                '\u062a\u0645 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u0639\u0645\u064a\u0644 \u0628\u0646\u062c\u0627\u062d',
                style: AppTheme.heading2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Subtitle
              Text(
                '\u062a\u0645 \u0625\u0636\u0627\u0641\u0629 \u0627\u0644\u0639\u0645\u064a\u0644 \u0627\u0644\u062c\u062f\u064a\u062f \u0628\u0646\u062c\u0627\u062d\n\u0634\u0643\u0631\u0627\u064b \u0644\u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0645\u0646\u0635\u0629 \u0623\u0645\u0627\u0646',
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
                  child: Text(
                    '\u0627\u0644\u0639\u0648\u062f\u0629 \u0644\u0644\u0631\u0626\u064a\u0633\u064a\u0629',
                    style: AppTheme.buttonText,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
