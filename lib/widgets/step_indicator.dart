import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> labels;

  const StepIndicator({
    super.key,
    required this.currentStep,
    this.labels = const [
      'التحقق من الهوية',
      'بيانات النشاط',
      'المعلومات المالية',
    ],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (index) {
          if (index.isOdd) {
            // Connecting line
            final stepBeforeLine = index ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                color: stepBeforeLine < currentStep
                    ? AppColors.primary
                    : AppColors.border,
              ),
            );
          }

          final stepIndex = index ~/ 2;
          return _StepCircle(
            stepIndex: stepIndex,
            currentStep: currentStep,
            label: labels[stepIndex],
          );
        }),
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int stepIndex;
  final int currentStep;
  final String label;

  const _StepCircle({
    required this.stepIndex,
    required this.currentStep,
    required this.label,
  });

  bool get isCompleted => stepIndex < currentStep;
  bool get isActive => stepIndex == currentStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isCompleted || isActive)
                ? AppColors.primary
                : AppColors.white,
            border: (isCompleted || isActive)
                ? null
                : Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 18, color: AppColors.white)
                : Text(
                    '${stepIndex + 1}',
                    style: AppTheme.bodySmall.copyWith(
                      color: isActive ? AppColors.white : AppColors.textLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 80,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              fontSize: 10,
              color: (isCompleted || isActive)
                  ? AppColors.primary
                  : AppColors.textLight,
              fontWeight:
                  isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
