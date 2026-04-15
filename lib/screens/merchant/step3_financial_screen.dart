import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/merchant_provider.dart';
import '../../theme/app_theme.dart';
import 'registration_success_screen.dart';

class Step3FinancialScreen extends StatefulWidget {
  const Step3FinancialScreen({super.key});

  @override
  State<Step3FinancialScreen> createState() => _Step3FinancialScreenState();
}

class _Step3FinancialScreenState extends State<Step3FinancialScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _accountController;
  late final TextEditingController _ibanController;

  @override
  void initState() {
    super.initState();
    final merchant = context.read<MerchantProvider>().merchant;
    _accountController = TextEditingController(text: merchant.accountNumber);
    _ibanController = TextEditingController(text: merchant.ibanNumber);
  }

  @override
  void dispose() {
    _accountController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  Future<void> _saveAndSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<MerchantProvider>();
    provider.updateFinancialInfo(
      accountNumber: _accountController.text.trim(),
      ibanNumber: _ibanController.text.trim(),
    );

    final success = await provider.submitRegistration();
    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const RegistrationSuccessScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantProvider>();
    final merchant = provider.merchant;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Section title
            Text('المعلومات المالية', style: AppTheme.heading3),
            const SizedBox(height: 4),
            Text(
              'أدخل بيانات الحساب البنكي للتاجر',
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // Bank name
            _FieldLabel(
                icon: Icons.account_balance_outlined, label: 'اسم البنك'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: merchant.bankName.isEmpty ? null : merchant.bankName,
              style: AppTheme.inputText,
              decoration: AppTheme.inputDecoration(hintText: 'اختر البنك'),
              items: MerchantProvider.bankNames
                  .map((bank) => DropdownMenuItem(
                        value: bank,
                        child: Text(bank),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  provider.updateFinancialInfo(bankName: value);
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'يرجى اختيار البنك';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Account number
            _FieldLabel(
                icon: Icons.credit_card_outlined, label: 'رقم الحساب البنكي'),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextFormField(
                controller: _accountController,
                style: AppTheme.inputText,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: AppTheme.inputDecoration(
                  hintText: 'XXXXXXXXXX',
                ),
                validator: (value) {
                  if (value == null || value.length < 10) {
                    return 'يرجى إدخال رقم حساب صحيح (10 أرقام على الأقل)';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),

            // IBAN
            _FieldLabel(icon: Icons.numbers_outlined, label: 'رقم IBAN'),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextFormField(
                controller: _ibanController,
                style: AppTheme.inputText,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(29),
                ],
                decoration: AppTheme.inputDecoration(
                  hintText: 'EG0000000000000000000000000',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال رقم IBAN';
                  }
                  if (!value.startsWith('EG')) {
                    return 'رقم IBAN يجب أن يبدأ بـ EG';
                  }
                  if (value.length != 29) {
                    return 'رقم IBAN يجب أن يتكون من 29 حرف';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 32),

            // Review summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryVeryLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ملخص البيانات', style: AppTheme.bodyLarge),
                  const SizedBox(height: 12),

                  // Personal photo thumbnail
                  if (merchant.personalPhotoPath != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('تم رفع الصورة الشخصية',
                            style: AppTheme.bodySmall.copyWith(
                                color: AppColors.primary)),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 16,
                          backgroundImage:
                              FileImage(File(merchant.personalPhotoPath!)),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                  ],

                  _SummaryRow(label: 'اسم التاجر', value: merchant.merchantName),
                  _SummaryRow(label: 'رقم الهاتف', value: merchant.phoneNumber),
                  _SummaryRow(label: 'نوع النشاط', value: merchant.businessType),
                  _SummaryRow(label: 'المنطقة', value: merchant.region),
                  if (merchant.bankName.isNotEmpty)
                    _SummaryRow(label: 'البنك', value: merchant.bankName),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        provider.isSubmitting ? null : () => provider.previousStep(),
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
                    onPressed: provider.isSubmitting ? null : _saveAndSubmit,
                    style: AppTheme.primaryButton(
                        backgroundColor: AppColors.buttonOrange),
                    child: provider.isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: AppColors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text('إرسال الطلب', style: AppTheme.buttonText),
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: AppTheme.bodySmall.copyWith(color: AppColors.textDark),
              textAlign: TextAlign.start,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
