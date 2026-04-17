import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/merchant.dart';
import '../../providers/merchant_list_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'merchant_profile_screen.dart';

class MerchantListScreen extends StatefulWidget {
  const MerchantListScreen({super.key});

  @override
  State<MerchantListScreen> createState() => _MerchantListScreenState();
}

class _MerchantListScreenState extends State<MerchantListScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<MerchantListProvider>();
    Future.microtask(() => provider.fetchMerchants());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantListProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('العملاء', style: AppTheme.heading3),
        centerTitle: true,
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(provider),
    );
  }

  Widget _buildBody(MerchantListProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.buttonRed),
            const SizedBox(height: 12),
            Text(provider.error!, style: AppTheme.bodyLarge),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.fetchMerchants(),
              style: AppTheme.primaryButton(),
              child: Text('إعادة المحاولة', style: AppTheme.buttonText),
            ),
          ],
        ),
      );
    }

    if (provider.merchants.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.people_outline,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text('لا يوجد عملاء حالياً', style: AppTheme.bodyLarge),
            const SizedBox(height: 4),
            Text('قم بتسجيل عميل جديد للبدء', style: AppTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => provider.fetchMerchants(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: provider.merchants.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _MerchantCard(merchant: provider.merchants[index]);
        },
      ),
    );
  }
}

class _MerchantCard extends StatelessWidget {
  final Lead merchant;
  const _MerchantCard({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: context.read<MerchantListProvider>(),
              child: MerchantProfileScreen(merchant: merchant),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
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
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_outline,
                  size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant.name,
                    style: AppTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    maskPhone(merchant.phone),
                    style: AppTheme.bodySmall,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
            // Status + date
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusBadge(merchant.status),
                const SizedBox(height: 4),
                Text(
                  formatDate(merchant.createdAt),
                  style: AppTheme.bodySmall.copyWith(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left, size: 20, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (label, color) = merchantStatusDisplay(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
