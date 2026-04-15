import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../auth/phone_entry_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _confirmLogout = false;

  void _handleLogout() {
    context.read<AuthProvider>().logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          children: [
            // Title
            Text('الملف الشخصي', style: AppTheme.heading2),
            const SizedBox(height: 4),
            Text('بيانات حسابك', style: AppTheme.bodySmall),
            const SizedBox(height: 24),

            // Avatar
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(45),
              ),
              child: const Icon(Icons.person_outline,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 24),

            // Info cards
            _infoCard('الاسم بالكامل', user?.name ?? '', Icons.person_outline),
            _infoCard('رقم الموبايل', user?.phone ?? '', Icons.phone_outlined),
            _infoCard(
                'الرقم الوظيفي', user?.employeeId ?? '', Icons.tag_outlined),
            _infoCard('الوحدة التجارية', user?.businessUnit ?? '',
                Icons.business_center_outlined),
            _infoCard('المنطقة', user?.region ?? '', Icons.location_on_outlined),
            const SizedBox(height: 24),

            // Logout
            if (_confirmLogout)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'هل أنت متأكد من تسجيل الخروج؟',
                      style: AppTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                setState(() => _confirmLogout = false),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              side:
                                  const BorderSide(color: AppColors.border),
                            ),
                            child: Text('إلغاء',
                                style: AppTheme.bodyLarge
                                    .copyWith(color: AppColors.textMedium)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _handleLogout,
                            style: AppTheme.primaryButton(
                                backgroundColor: AppColors.buttonRed),
                            child: Text('خروج', style: AppTheme.buttonText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _confirmLogout = true),
                  icon: const Icon(Icons.logout, size: 20),
                  label: Text('تسجيل الخروج', style: AppTheme.buttonText),
                  style: AppTheme.primaryButton(
                      backgroundColor: AppColors.buttonRed),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label, style: AppTheme.bodySmall),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
