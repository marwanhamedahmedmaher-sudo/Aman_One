import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/merchant_list_provider.dart';
import '../../theme/app_theme.dart';
import '../lead/new_lead_screen.dart';
import '../merchant/merchant_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _bannerVisible = true;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MerchantListProvider>();
    Future.microtask(() => provider.fetchWeeklyCount());
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final firstName = user?.name.split(' ').first ?? 'مرحباً';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App name header with logo
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/logo_icon.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'أمان',
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'وانجز',
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            // Greeting banner
            if (_bannerVisible)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    // Location icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.location_on_outlined,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    // Text
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أهلا $firstName!',
                          style: AppTheme.bodyLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'منطقتك: ${user?.region ?? 'القاهرة'}',
                          style: AppTheme.bodySmall,
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Close button
                    GestureDetector(
                      onTap: () => setState(() => _bannerVisible = false),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close,
                            size: 16, color: AppColors.textMedium),
                      ),
                    ),
                  ],
                ),
              ),

            // Section title
            Text('الرئيسية', style: AppTheme.heading2),
            const SizedBox(height: 4),
            Text(
              'قم بتسجيل التجار الجدد ومتابعة طلباتك',
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: 16),

            // Register new lead button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final provider = context.read<MerchantListProvider>();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NewLeadScreen(),
                    ),
                  ).then((_) => provider.fetchWeeklyCount());
                },
                icon: const Icon(Icons.add, size: 22),
                label: Text('\u062a\u0633\u062c\u064a\u0644 \u0639\u0645\u064a\u0644 \u062c\u062f\u064a\u062f', style: AppTheme.buttonText),
                style: AppTheme.primaryButton(
                    backgroundColor: AppColors.buttonOrange),
              ),
            ),
            const SizedBox(height: 16),

            // Stats card — tappable → merchant list
            GestureDetector(
              onTap: () {
                final provider = context.read<MerchantListProvider>();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MerchantListScreen(),
                  ),
                ).then((_) => provider.fetchWeeklyCount());
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.people_outline,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text(
                          '${context.watch<MerchantListProvider>().weeklyCount}',
                          style: AppTheme.heading2.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 4),
                        Text('تم إنشاؤهم هذا الأسبوع',
                            style: AppTheme.bodySmall),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_left,
                        size: 22, color: AppColors.textLight),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
