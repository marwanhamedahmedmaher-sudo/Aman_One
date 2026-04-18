import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/merchant.dart';
import '../../providers/merchant_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
import 'lead_success_screen.dart';

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
  final _notesController = TextEditingController();
  final _amountController = TextEditingController();
  final _deviceCountController = TextEditingController();
  final _avgSalesController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialLead != null) {
      _nameController.text = widget.initialLead!.name;
      _phoneController.text = widget.initialLead!.phone;
      _notesController.text = widget.initialLead!.notes;
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
    _notesController.dispose();
    _amountController.dispose();
    _deviceCountController.dispose();
    _avgSalesController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(LeadProvider provider) async {
    final amountText = _amountController.text.trim();
    final deviceText = _deviceCountController.text.trim();
    final addressText = _addressController.text.trim();
    final avgSalesText = _avgSalesController.text.trim();

    provider.updateLead(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      nationalId: _nationalIdController.text.trim(),
      notes: _notesController.text.trim(),
      businessAddress: () => addressText.isNotEmpty ? addressText : null,
    );
    provider.updateProductDetails(
      microfinanceAmount:
          amountText.isNotEmpty ? double.tryParse(amountText) : null,
      acceptanceDeviceCount:
          deviceText.isNotEmpty ? int.tryParse(deviceText) : null,
    );
    provider.updateLeadDetails(
      avgMonthlySales: () =>
          avgSalesText.isNotEmpty ? double.tryParse(avgSalesText) : null,
    );

    final validationError = provider.validate();
    if (validationError != null) {
      provider.setError(validationError);
      Analytics.track('lead_validation_failed');
      return;
    }

    final merchantId = await provider.submit();
    if (merchantId != null && mounted) {
      // If this came from a cross-sell task, mark it completed
      if (widget.taskAssignmentId != null) {
        final tasksProvider = context.read<TasksProvider>();
        await tasksProvider.completeTask(
              widget.taskAssignmentId!,
              merchantId: merchantId,
            );
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LeadSuccessScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LeadProvider()..fetchActivityTypes(),
      child: Consumer<LeadProvider>(
        builder: (context, provider, _) {
          return Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textWhite,
                title: Text(
                  '\u062a\u0633\u062c\u064a\u0644 \u0639\u0645\u064a\u0644 \u062c\u062f\u064a\u062f',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name field
                    _buildLabel('\u0627\u0633\u0645 \u0627\u0644\u062a\u0627\u062c\u0631'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      keyboardType: TextInputType.name,
                      textAlign: TextAlign.right,
                      style: AppTheme.inputText,
                      decoration: AppTheme.inputDecoration(
                        hintText: '\u0627\u062f\u062e\u0644 \u0627\u0633\u0645 \u0627\u0644\u062a\u0627\u062c\u0631',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Phone field
                    _buildLabel('\u0631\u0642\u0645 \u0627\u0644\u0645\u0648\u0628\u0627\u064a\u0644'),
                    const SizedBox(height: 8),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        maxLength: 11,
                        textAlign: TextAlign.right,
                        style: AppTheme.inputText,
                        decoration: AppTheme.inputDecoration(
                          hintText: '01XXXXXXXXX',
                        ).copyWith(counterText: ''),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // National ID field
                    _buildLabel('\u0627\u0644\u0631\u0642\u0645 \u0627\u0644\u0642\u0648\u0645\u064a'),
                    const SizedBox(height: 8),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _nationalIdController,
                        keyboardType: TextInputType.number,
                        maxLength: 14,
                        textAlign: TextAlign.right,
                        style: AppTheme.inputText,
                        decoration: AppTheme.inputDecoration(
                          hintText: 'XXXXXXXXXXXXXX',
                        ).copyWith(counterText: ''),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Products checkboxes
                    _buildLabel('\u0627\u0644\u0645\u0646\u062a\u062c\u0627\u062a'), // المنتجات
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          // Microfinance + conditional amount field
                          CheckboxListTile(
                            value: provider.lead.products.contains('Microfinance'),
                            onChanged: (_) {
                              provider.toggleProduct('Microfinance');
                              if (!provider.lead.products.contains('Microfinance')) {
                                _amountController.clear();
                              }
                            },
                            title: Text('Microfinance', style: AppTheme.inputText),
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.trailing,
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                          if (provider.lead.products.contains('Microfinance'))
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                              child: TextField(
                                controller: _amountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.right,
                                style: AppTheme.inputText,
                                decoration: AppTheme.inputDecoration(
                                  hintText: '\u0627\u062f\u062e\u0644 \u0627\u0644\u0645\u0628\u0644\u063a', // ادخل المبلغ
                                ).copyWith(
                                  prefixIcon: const Icon(Icons.attach_money, size: 20),
                                  labelText: '\u0627\u0644\u0645\u0628\u0644\u063a', // المبلغ
                                  labelStyle: AppTheme.bodySmall,
                                ),
                              ),
                            ),

                          // BP POS — no extra fields
                          CheckboxListTile(
                            value: provider.lead.products.contains('BP POS'),
                            onChanged: (_) => provider.toggleProduct('BP POS'),
                            title: Text('BP POS', style: AppTheme.inputText),
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.trailing,
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),

                          // Acceptance POS + conditional device count field
                          CheckboxListTile(
                            value: provider.lead.products.contains('Acceptance POS'),
                            onChanged: (_) {
                              provider.toggleProduct('Acceptance POS');
                              if (!provider.lead.products.contains('Acceptance POS')) {
                                _deviceCountController.clear();
                              }
                            },
                            title: Text('Acceptance POS', style: AppTheme.inputText),
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.trailing,
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                          if (provider.lead.products.contains('Acceptance POS'))
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                              child: TextField(
                                controller: _deviceCountController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.right,
                                style: AppTheme.inputText,
                                decoration: AppTheme.inputDecoration(
                                  hintText: '\u0627\u062f\u062e\u0644 \u0639\u062f\u062f \u0627\u0644\u0623\u062c\u0647\u0632\u0629', // ادخل عدد الأجهزة
                                ).copyWith(
                                  prefixIcon: const Icon(Icons.devices, size: 20),
                                  labelText: '\u0639\u062f\u062f \u0627\u0644\u0623\u062c\u0647\u0632\u0629', // عدد الأجهزة
                                  labelStyle: AppTheme.bodySmall,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Average monthly sales
                    _buildLabel('\u0645\u062a\u0648\u0633\u0637 \u0627\u0644\u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0634\u0647\u0631\u064a\u0629'), // متوسط المبيعات الشهرية
                    const SizedBox(height: 8),
                    TextField(
                      controller: _avgSalesController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: AppTheme.inputText,
                      decoration: AppTheme.inputDecoration(
                        hintText: '\u0627\u0644\u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0634\u0647\u0631\u064a\u0629 \u0628\u0627\u0644\u062c\u0646\u064a\u0647 (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)', // المبيعات الشهرية بالجنيه (اختياري)
                      ).copyWith(
                        prefixIcon: const Icon(Icons.attach_money, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Business address
                    _buildLabel('\u0639\u0646\u0648\u0627\u0646 \u0627\u0644\u0646\u0634\u0627\u0637'), // عنوان النشاط
                    const SizedBox(height: 8),
                    TextField(
                      controller: _addressController,
                      keyboardType: TextInputType.streetAddress,
                      textAlign: TextAlign.right,
                      style: AppTheme.inputText,
                      decoration: AppTheme.inputDecoration(
                        hintText: '\u0627\u062f\u062e\u0644 \u0639\u0646\u0648\u0627\u0646 \u0627\u0644\u0646\u0634\u0627\u0637 (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)', // ادخل عنوان النشاط (اختياري)
                      ).copyWith(
                        prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Activity type dropdown
                    _buildLabel('\u0646\u0648\u0639 \u0627\u0644\u0646\u0634\u0627\u0637'), // نوع النشاط
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: provider.lead.activityTypeId,
                      isExpanded: true,
                      style: AppTheme.inputText,
                      decoration: AppTheme.inputDecoration(
                        hintText: '\u0627\u062e\u062a\u0631 \u0646\u0648\u0639 \u0627\u0644\u0646\u0634\u0627\u0637 (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)', // اختر نوع النشاط (اختياري)
                      ).copyWith(
                        prefixIcon: const Icon(Icons.category_outlined, size: 20),
                      ),
                      items: provider.activityTypes.map((type) {
                        return DropdownMenuItem<String>(
                          value: type.id,
                          child: Text(type.name, style: AppTheme.inputText),
                        );
                      }).toList(),
                      onChanged: (value) {
                        final selectedType = provider.activityTypes
                            .where((t) => t.id == value)
                            .firstOrNull;
                        provider.updateLeadDetails(
                          activityTypeId: () => value,
                          activityTypeName: () => selectedType?.name,
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Notes field
                    _buildLabel('\u0645\u0644\u0627\u062d\u0638\u0627\u062a'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      keyboardType: TextInputType.multiline,
                      maxLines: 3,
                      textAlign: TextAlign.right,
                      style: AppTheme.inputText,
                      decoration: AppTheme.inputDecoration(
                        hintText: '\u0623\u0636\u0641 \u0645\u0644\u0627\u062d\u0638\u0627\u062a (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)',
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error message
                    if (provider.error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.buttonRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          provider.error!,
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppColors.buttonRed,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: provider.isSubmitting || provider.lead.products.isEmpty
                            ? null
                            : () => _handleSubmit(provider),
                        style: AppTheme.primaryButton(),
                        child: provider.isSubmitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                '\u062a\u0633\u062c\u064a\u0644',
                                style: AppTheme.buttonText,
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
          );
        },
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text, style: AppTheme.labelText);
  }
}
