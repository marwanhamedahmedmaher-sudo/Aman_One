import 'package:flutter/material.dart';
import '../../models/card_application_spec.dart';
import '../../models/merchant.dart';
import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
import '../../widgets/responsive_container.dart';
import '../acceptance/card_application_wizard.dart';

/// New-merchant launcher: capture identity + pick the products to onboard for,
/// then start the unified onboarding wizard. All product / business / document
/// data is collected once inside the wizard — this screen has no double-entry.
class NewLeadScreen extends StatefulWidget {
  final Lead? initialLead;
  final String? taskAssignmentId;

  const NewLeadScreen({
    super.key,
    this.initialLead,
    this.taskAssignmentId,
  });

  @override
  State<NewLeadScreen> createState() => _NewLeadScreenState();
}

class _NewLeadScreenState extends State<NewLeadScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialLead != null) {
      _nameController.text = widget.initialLead!.name;
      _phoneController.text = widget.initialLead!.phone;
      _selected.addAll(widget.initialLead!.products);
    }
    Analytics.track('lead_form_opened', properties: {
      'from_task': widget.taskAssignmentId != null,
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    super.dispose();
  }

  void _startOnboarding() {
    final name = _nameController.text.trim();
    final nid = _nationalIdController.text.trim();
    final phone = _phoneController.text.trim();
    // Cross-sell tasks carry admin-supplied context in the lead's notes —
    // thread it through so the merchants row doesn't land with notes=''.
    final notes = widget.initialLead?.notes.trim() ?? '';
    Analytics.track('onboarding_started', properties: {
      'product_count': _selected.length,
    });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CardApplicationWizard(
          products: _selected.toList(),
          seedName: name.isNotEmpty ? name : null,
          seedNationalId: nid.isNotEmpty ? nid : null,
          seedMobile: phone.isNotEmpty ? phone : null,
          seedNotes: notes.isNotEmpty ? notes : null,
          taskAssignmentId: widget.taskAssignmentId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textWhite,
        title: Text(
          'تسجيل تاجر جديد',
          style: AppTheme.heading3.copyWith(color: AppColors.textWhite),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ResponsiveContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              _buildLabel('اسم التاجر'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                keyboardType: TextInputType.name,
                textAlign: TextAlign.right,
                style: AppTheme.inputText,
                decoration: AppTheme.inputDecoration(hintText: 'ادخل اسم التاجر'),
              ),
              const SizedBox(height: 20),

              // Phone
              _buildLabel('رقم الموبايل'),
              const SizedBox(height: 8),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  textAlign: TextAlign.right,
                  style: AppTheme.inputText,
                  decoration: AppTheme.inputDecoration(hintText: '01XXXXXXXXX')
                      .copyWith(counterText: ''),
                ),
              ),
              const SizedBox(height: 20),

              // National ID
              _buildLabel('الرقم القومي'),
              const SizedBox(height: 8),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _nationalIdController,
                  keyboardType: TextInputType.number,
                  maxLength: 14,
                  textAlign: TextAlign.right,
                  style: AppTheme.inputText,
                  decoration: AppTheme.inputDecoration(hintText: 'XXXXXXXXXXXXXX')
                      .copyWith(counterText: ''),
                ),
              ),
              const SizedBox(height: 20),

              // Products
              _buildLabel('المنتجات'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    for (final p in products)
                      CheckboxListTile(
                        value: _selected.contains(p),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(p);
                          } else {
                            _selected.remove(p);
                          }
                        }),
                        title: Text(productLabelAr(p), style: AppTheme.inputText),
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.trailing,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_selected.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'اختر منتجًا واحدًا على الأقل لبدء تسجيل التاجر',
                    style: AppTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                _buildOnboardingCta(_selected.toList()),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnboardingCta(List<String> selectedProducts) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.orange20,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange70),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_ind_outlined, color: AppColors.orange100),
              const SizedBox(width: 8),
              Expanded(child: Text('تسجيل موحّد للتاجر', style: AppTheme.bodyLarge)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'لـ ${selectedProducts.map(productLabelAr).join(' + ')} — تُدخل البيانات والمستندات مرة واحدة',
            style: AppTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startOnboarding,
              style: AppTheme.primaryButton(backgroundColor: AppColors.orange100),
              icon: const Icon(Icons.arrow_back, size: 20),
              label: Text('بدء التسجيل', style: AppTheme.buttonText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text, style: AppTheme.labelText);
  }
}
