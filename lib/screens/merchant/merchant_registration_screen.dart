import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/merchant_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/step_indicator.dart';
import 'step1_identity_screen.dart';
import 'step2_business_info_screen.dart';
import 'step3_financial_screen.dart';

class MerchantRegistrationScreen extends StatelessWidget {
  const MerchantRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MerchantProvider(),
      child: const _MerchantRegistrationBody(),
    );
  }
}

class _MerchantRegistrationBody extends StatelessWidget {
  const _MerchantRegistrationBody();

  Future<bool> _onWillPop(BuildContext context) async {
    final provider = context.read<MerchantProvider>();

    if (provider.currentStep > 0) {
      provider.previousStep();
      return false;
    }

    // Show confirmation dialog on first step
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('إلغاء التسجيل', style: AppTheme.heading3),
          content: Text(
            'هل تريد إلغاء تسجيل التاجر؟ سيتم فقدان البيانات المدخلة.',
            style: AppTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('لا', style: AppTheme.linkText),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'نعم',
                style: AppTheme.linkText
                    .copyWith(color: AppColors.buttonRed),
              ),
            ),
          ],
        ),
      ),
    );

    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = context.watch<MerchantProvider>().currentStep;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop(context);
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            elevation: 0,
            centerTitle: true,
            title: Text('تسجيل تاجر جديد', style: AppTheme.heading3.copyWith(
              color: AppColors.white,
              fontSize: 17,
            )),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              onPressed: () async {
                final shouldPop = await _onWillPop(context);
                if (shouldPop && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
          body: Column(
            children: [
              // Step indicator
              Container(
                color: AppColors.white,
                child: StepIndicator(currentStep: currentStep),
              ),
              const Divider(height: 1, color: AppColors.border),

              // Step content
              Expanded(
                child: IndexedStack(
                  index: currentStep,
                  children: const [
                    Step1IdentityScreen(),
                    Step2BusinessInfoScreen(),
                    Step3FinancialScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
