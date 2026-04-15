import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          children: [
            // Title
            Align(
              alignment: Alignment.centerRight,
              child: Text('المهام', style: AppTheme.heading2),
            ),
            const SizedBox(height: 20),
            // Empty state
            Expanded(
              child: Center(
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
                      child: const Icon(
                        Icons.assignment_outlined,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('لا توجد مهام حالياً', style: AppTheme.bodyLarge),
                    const SizedBox(height: 6),
                    Text('ستظهر مهامك هنا قريباً', style: AppTheme.bodySmall),
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
