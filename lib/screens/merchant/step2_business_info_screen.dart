import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/merchant_provider.dart';
import '../../theme/app_theme.dart';

class Step2BusinessInfoScreen extends StatefulWidget {
  const Step2BusinessInfoScreen({super.key});

  @override
  State<Step2BusinessInfoScreen> createState() =>
      _Step2BusinessInfoScreenState();
}

class _Step2BusinessInfoScreenState extends State<Step2BusinessInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _postalCodeController;

  @override
  void initState() {
    super.initState();
    final merchant = context.read<MerchantProvider>().merchant;
    _nameController = TextEditingController(text: merchant.merchantName);
    _phoneController = TextEditingController(text: merchant.phoneNumber);
    _addressController = TextEditingController(text: merchant.address);
    _postalCodeController = TextEditingController(text: merchant.postalCode);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<MerchantProvider>();
    provider.updateBusinessInfo(
      merchantName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
    );
    provider.nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Section title
            Text('بيانات النشاط', style: AppTheme.heading3),
            const SizedBox(height: 4),
            Text(
              'أدخل بيانات التاجر والنشاط التجاري',
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // Merchant name
            _FieldLabel(icon: Icons.store_outlined, label: 'اسم التاجر / المحل'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              style: AppTheme.inputText,
              decoration: AppTheme.inputDecoration(
                hintText: 'مثال: محل الأمان',
              ),
              validator: (value) {
                if (value == null || value.trim().length < 3) {
                  return 'يرجى إدخال اسم التاجر (3 أحرف على الأقل)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Phone number
            _FieldLabel(icon: Icons.phone_outlined, label: 'رقم الهاتف'),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextFormField(
                controller: _phoneController,
                style: AppTheme.inputText,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: AppTheme.inputDecoration(
                  hintText: '01XXXXXXXXX',
                ),
                validator: (value) {
                  if (value == null || value.length < 10) {
                    return 'يرجى إدخال رقم هاتف صحيح';
                  }
                  if (!value.startsWith('01')) {
                    return 'رقم الهاتف يجب أن يبدأ بـ 01';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),

            // Business type
            _FieldLabel(icon: Icons.category_outlined, label: 'نوع النشاط'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: provider.merchant.businessType.isEmpty
                  ? null
                  : provider.merchant.businessType,
              style: AppTheme.inputText,
              decoration: AppTheme.inputDecoration(hintText: 'اختر نوع النشاط'),
              items: MerchantProvider.businessTypes
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  provider.updateBusinessInfo(businessType: value);
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'يرجى اختيار نوع النشاط';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Address
            _FieldLabel(
                icon: Icons.location_on_outlined, label: 'العنوان التفصيلي'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _addressController,
              style: AppTheme.inputText,
              maxLines: 2,
              decoration: AppTheme.inputDecoration(
                hintText: 'الشارع، المنطقة، المعلم القريب',
              ),
              validator: (value) {
                if (value == null || value.trim().length < 5) {
                  return 'يرجى إدخال العنوان التفصيلي';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Region
            _FieldLabel(icon: Icons.map_outlined, label: 'المنطقة / المحافظة'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: provider.merchant.region.isEmpty
                  ? null
                  : provider.merchant.region,
              style: AppTheme.inputText,
              decoration: AppTheme.inputDecoration(hintText: 'اختر المنطقة'),
              items: MerchantProvider.regions
                  .map((region) => DropdownMenuItem(
                        value: region,
                        child: Text(region),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  provider.updateBusinessInfo(region: value);
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'يرجى اختيار المنطقة';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Postal code
            _FieldLabel(
                icon: Icons.markunread_mailbox_outlined, label: 'الرمز البريدي'),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextFormField(
                controller: _postalCodeController,
                style: AppTheme.inputText,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: AppTheme.inputDecoration(
                  hintText: 'XXXXX',
                ),
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      value.length != 5) {
                    return 'الرمز البريدي يجب أن يكون 5 أرقام';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => provider.previousStep(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: Text(
                      'السابق',
                      style: AppTheme.buttonText
                          .copyWith(color: AppColors.textMedium),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saveAndNext,
                    style: AppTheme.primaryButton(),
                    child: Text('التالي', style: AppTheme.buttonText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FieldLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label, style: AppTheme.labelText),
        const SizedBox(width: 6),
        Icon(icon, size: 18, color: AppColors.textMedium),
      ],
    );
  }
}
