import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/card_application_spec.dart';
import '../../models/merchant.dart';
import '../../providers/merchant_list_provider.dart';
import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/responsive_container.dart';

class MerchantProfileScreen extends StatefulWidget {
  final Lead merchant;
  const MerchantProfileScreen({super.key, required this.merchant});

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  String? _revealedId;
  bool _isRevealing = false;

  bool get _isForeigner => widget.merchant.idDocumentType == 'passport';

  @override
  void initState() {
    super.initState();
    Analytics.track('merchant_profile_viewed', properties: {
      'merchant_id': widget.merchant.id,
      'status': widget.merchant.status,
      'product_count': widget.merchant.products.length,
      'id_document_type': widget.merchant.idDocumentType,
    });
  }

  // Reveals the right identity document: passport for foreigners, National ID
  // for Egyptians. Both go through a SECURITY DEFINER reveal-with-audit RPC.
  Future<void> _revealId() async {
    setState(() => _isRevealing = true);

    final provider = context.read<MerchantListProvider>();
    final value = _isForeigner
        ? await provider.revealPassportNumber(widget.merchant.id!)
        : await provider.revealNationalId(widget.merchant.id!);

    if (mounted) {
      setState(() {
        _revealedId = value;
        _isRevealing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('بيانات العميل', style: AppTheme.heading3),
        centerTitle: true,
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: ResponsiveContainer(
          child: Column(
          children: [
            // Avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(Icons.person_outline,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(
              widget.merchant.name,
              style: AppTheme.heading2,
            ),
            const SizedBox(height: 4),
            _statusBadge(widget.merchant.status),
            const SizedBox(height: 24),

            // Info cards
            _infoCard('رقم الموبايل', widget.merchant.phone, Icons.phone_outlined,
                textDirection: TextDirection.ltr),
            _idCard(),
            _productsCard(),
            if (widget.merchant.activityTypeName != null)
              _infoCard('\u0646\u0648\u0639 \u0627\u0644\u0646\u0634\u0627\u0637', widget.merchant.activityTypeName!, Icons.category_outlined), // نوع النشاط
            if (widget.merchant.avgMonthlySales != null)
              _infoCard(
                '\u0645\u062a\u0648\u0633\u0637 \u0627\u0644\u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0634\u0647\u0631\u064a\u0629', // متوسط المبيعات الشهرية
                '${widget.merchant.avgMonthlySales!.toStringAsFixed(widget.merchant.avgMonthlySales! == widget.merchant.avgMonthlySales!.roundToDouble() ? 0 : 2)} \u062c\u0646\u064a\u0647', // جنيه
                Icons.trending_up_outlined,
              ),
            if (widget.merchant.businessAddress != null && widget.merchant.businessAddress!.isNotEmpty)
              _infoCard('\u0639\u0646\u0648\u0627\u0646 \u0627\u0644\u0646\u0634\u0627\u0637', widget.merchant.businessAddress!, Icons.location_on_outlined), // عنوان النشاط
            if (widget.merchant.notes.isNotEmpty)
              _infoCard('ملاحظات', widget.merchant.notes, Icons.notes_outlined),
            _infoCard('تاريخ التسجيل', formatDate(widget.merchant.createdAt),
                Icons.calendar_today_outlined),
          ],
        ),
        ),
      ),
    );
  }

  Widget _productsCard() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\u0627\u0644\u0645\u0646\u062a\u062c\u0627\u062a', style: AppTheme.bodySmall), // المنتجات
                const SizedBox(height: 6),
                ...widget.merchant.products.map((product) {
                  String? detail;
                  if (product == 'Microfinance' &&
                      widget.merchant.microfinanceAmount != null) {
                    detail =
                        '\u0627\u0644\u0645\u0628\u0644\u063a: ${widget.merchant.microfinanceAmount!.toStringAsFixed(widget.merchant.microfinanceAmount! == widget.merchant.microfinanceAmount!.roundToDouble() ? 0 : 2)}'; // المبلغ:
                  } else if (product == 'Acceptance POS' &&
                      widget.merchant.acceptanceDeviceCount != null) {
                    detail =
                        '\u0639\u062f\u062f \u0627\u0644\u0623\u062c\u0647\u0632\u0629: ${widget.merchant.acceptanceDeviceCount}'; // عدد الأجهزة:
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productLabelAr(product),
                          style: AppTheme.bodyLarge
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (detail != null)
                          Padding(
                            padding:
                                const EdgeInsetsDirectional.only(start: 8),
                            child: Text(
                              detail,
                              style: AppTheme.bodySmall.copyWith(
                                color: AppColors.textMedium,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _idCard() {
    // The list query omits both identifiers by design — the reveal RPCs are the
    // sole plaintext path. Label, mask length, and reveal target all depend on
    // whether this is a foreigner (passport) or an Egyptian (National ID).
    final label = _isForeigner ? 'رقم جواز السفر' : 'الرقم القومي';
    final maskLength = _isForeigner ? 9 : 14;
    final displayValue = _revealedId ?? '*' * maskLength;

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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.badge_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.bodySmall),
                const SizedBox(height: 3),
                Text(
                  displayValue,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: _revealedId != null ? 1.2 : 0,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
          if (_revealedId == null)
            _isRevealing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : GestureDetector(
                    onTap: _revealId,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'عرض',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon,
      {TextDirection? textDirection}) {
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.bodySmall),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textDirection: textDirection,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (label, color) = merchantStatusDisplay(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
