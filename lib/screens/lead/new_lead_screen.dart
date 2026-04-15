import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/merchant_provider.dart';
import '../../theme/app_theme.dart';
import 'lead_success_screen.dart';

class NewLeadScreen extends StatefulWidget {
  const NewLeadScreen({super.key});

  @override
  State<NewLeadScreen> createState() => _NewLeadScreenState();
}

class _NewLeadScreenState extends State<NewLeadScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(LeadProvider provider) async {
    // Sync controller values to provider
    provider.updateLead(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      nationalId: _nationalIdController.text.trim(),
      notes: _notesController.text.trim(),
    );

    if (!provider.isValid) return;

    final success = await provider.submit();
    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LeadSuccessScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LeadProvider(),
      child: Consumer<LeadProvider>(
        builder: (context, provider, _) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                backgroundColor: AppColors.primary,
                title: Text(
                  '\u062a\u0633\u062c\u064a\u0644 \u0639\u0645\u064a\u0644 \u062c\u062f\u064a\u062f',
                  style: AppTheme.heading3.copyWith(color: AppColors.textWhite),
                ),
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textWhite),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                        onPressed: provider.isSubmitting
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
