import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AuthHeader extends StatelessWidget {
  final double height;

  const AuthHeader({super.key, this.height = 280});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      height: height + topPadding,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/logo_icon.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // App name
            Text(
              'أمان وان',
              style: AppTheme.heading1.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 4),
            // Tagline
            Text(
              'منصة تسجيل التجار',
              style: AppTheme.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
