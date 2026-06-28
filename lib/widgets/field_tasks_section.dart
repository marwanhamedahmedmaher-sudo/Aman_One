import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/field_task.dart';
import '../providers/field_tasks_provider.dart';
import '../theme/app_theme.dart';

/// The unified daily field-visit schedule (3 windows) with a per-task
/// "submit location" check-in button. Renders at the top of the tasks page.
class FieldTasksSection extends StatelessWidget {
  const FieldTasksSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldTasksProvider>();

    if (provider.isLoading && provider.tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (provider.tasks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            'مهام اليوم', // Today's schedule
            style: AppTheme.heading3,
          ),
        ),
        const SizedBox(height: 8),
        ...provider.tasks.map((t) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _FieldTaskCard(task: t),
            )),
        const Divider(height: 24, thickness: 6, color: AppColors.background),
      ],
    );
  }
}

class _FieldTaskCard extends StatelessWidget {
  final FieldTask task;
  const _FieldTaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldTasksProvider>();
    final submitting = provider.isSubmitting(task.id);

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: task.hasCheckin
                      ? AppColors.background
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.place_outlined,
                  size: 22,
                  color:
                      task.hasCheckin ? AppColors.textLight : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: AppTheme.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _windowLabel(task),
                      style: AppTheme.bodySmall,
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.description,
              style: AppTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 14),
          if (task.hasCheckin)
            _checkinResult(task.checkin!)
          else
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: submitting ? null : () => _onSubmit(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textWhite,
                        ),
                      )
                    : const Icon(Icons.my_location, size: 18),
                label: Text(
                  submitting ? 'جارٍ تحديد الموقع...' : 'تسجيل الموقع',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _checkinResult(TaskCheckin c) {
    final color = c.inWindow ? AppColors.primary : AppColors.buttonOrange;
    final label = c.inWindow
        ? 'تم تسجيل الموقع داخل الوقت المحدد'
        : 'تم تسجيل الموقع خارج الوقت المحدد';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(c.inWindow ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTheme.bodySmall
                  .copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            _timeOfDay(c.recordedAt),
            style: AppTheme.bodySmall.copyWith(color: color),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit(BuildContext context) async {
    final provider = context.read<FieldTasksProvider>();

    // One-time consent gate before the first location is ever captured.
    if (!provider.locationConsent) {
      final agreed = await _showConsentDialog(context);
      if (agreed != true) return;
      final saved = await provider.grantConsent();
      if (!saved) {
        if (context.mounted) _snack(context, provider.error ?? 'تعذّر حفظ الموافقة', isError: true);
        return;
      }
    }

    final outcome = await provider.submitCheckin(provider.tasks
        .firstWhere((t) => t.id == task.id, orElse: () => task));
    if (!context.mounted) return;

    if (outcome.success) {
      _snack(
        context,
        outcome.inWindow
            ? 'تم تسجيل موقعك بنجاح داخل الوقت المحدد'
            : 'تم تسجيل موقعك (خارج الوقت المحدد)',
        isError: false,
      );
    } else if (outcome.error != null) {
      _snack(context, outcome.error!, isError: true);
    }
  }

  Future<bool?> _showConsentDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تسجيل الموقع', style: AppTheme.heading3),
        content: Text(
          'سيقوم تطبيق أمان بتسجيل موقعك الحالي عند الضغط على "تسجيل الموقع" '
          'لكل مهمة، وذلك لأغراض الإشراف فقط. لا يتم تتبع موقعك في الخلفية، '
          'ويتم تسجيل الموقع فقط لحظة ضغطك على الزر.',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('رفض',
                style: AppTheme.bodyMedium.copyWith(color: AppColors.textLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: AppTheme.primaryButton(),
            child: Text('موافق', style: AppTheme.buttonText),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTheme.bodyMedium.copyWith(color: AppColors.textWhite)),
        backgroundColor: isError ? AppColors.buttonRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---- formatting helpers (Cairo local = UTC+2, no DST) ----

  static String _windowLabel(FieldTask t) =>
      '${_timeOfDay(t.windowStart)} – ${_timeOfDay(t.windowEnd)}';

  static String _timeOfDay(DateTime dt) {
    final cairo = dt.toUtc().add(const Duration(hours: 2));
    final h = cairo.hour.toString().padLeft(2, '0');
    final m = cairo.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
