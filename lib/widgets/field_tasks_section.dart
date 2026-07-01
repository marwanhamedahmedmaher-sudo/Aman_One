import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/field_task.dart';
import '../providers/field_tasks_provider.dart';
import '../screens/field/task_visits_screen.dart';
import '../theme/app_theme.dart';

/// The unified daily field-visit schedule (3 windows). Each task card opens a
/// dedicated page where the rep logs multiple visits. Renders at the top of the
/// tasks page.
class FieldTasksSection extends StatelessWidget {
  const FieldTasksSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldTasksProvider>();

    if (provider.isLoading && provider.tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (provider.tasks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text('مهام اليوم', style: AppTheme.heading3),
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
    final count = provider.visitCount(task.id);
    final done = task.status == 'completed';

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
                  color: done ? AppColors.background : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  done ? Icons.check_circle_outline : Icons.place_outlined,
                  size: 22,
                  color: done ? AppColors.textLight : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
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
              _statusBadge(),
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
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _openVisits(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: done ? AppColors.background : AppColors.primary,
                foregroundColor: done ? AppColors.textDark : AppColors.textWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: Icon(
                  done ? Icons.visibility_outlined : Icons.add_location_alt_outlined,
                  size: 18),
              label: Text(
                count == 0
                    ? 'أدخل زيارة'
                    : (done
                        ? 'عرض الزيارات ($count)'
                        : 'إضافة / عرض الزيارات ($count)'),
                style: AppTheme.bodyMedium.copyWith(
                  color: done ? AppColors.textDark : AppColors.textWhite,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    final (label, color) = switch (task.status) {
      'completed' => ('تم', AppColors.primary),
      'in_progress' => ('قيد التنفيذ', AppColors.buttonOrange),
      'skipped' => ('تم التخطي', AppColors.textLight),
      _ => ('', AppColors.textMedium),
    };
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _openVisits(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TaskVisitsScreen(task: task)))
        .then((_) {
      if (context.mounted) {
        context.read<FieldTasksProvider>().loadTodaysTasks();
      }
    });
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
