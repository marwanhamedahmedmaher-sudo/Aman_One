import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/field_task.dart';
import '../../providers/field_tasks_provider.dart';
import '../../theme/app_theme.dart';
import 'task_plan_screen.dart';

/// Weekly planning overview: the working week (Sun–Thu), each day showing its 3
/// windows with how many stops the rep has planned. Tap a window to build/edit
/// that window's plan.
class WeeklyPlanScreen extends StatefulWidget {
  const WeeklyPlanScreen({super.key});

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<FieldTasksProvider>();
    Future.microtask(provider.loadWeekTasks);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldTasksProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('تخطيط الأسبوع', style: AppTheme.heading3),
        backgroundColor: AppColors.white,
      ),
      body: SafeArea(
        child: _body(provider),
      ),
    );
  }

  Widget _body(FieldTasksProvider provider) {
    if (provider.weekLoading && provider.weekTasks.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (provider.weekTasks.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: provider.loadWeekTasks,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.event_note_outlined,
                        size: 36, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text('لا توجد مهام للأسبوع', style: AppTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final byDay = _groupByDay(provider.weekTasks);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: provider.loadWeekTasks,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('خطّط زياراتك للأسبوع القادم (الأحد – الخميس)',
              style: AppTheme.bodyMedium.copyWith(color: AppColors.textLight)),
          const SizedBox(height: 12),
          for (final entry in byDay.entries) ...[
            _dayHeader(entry.key),
            const SizedBox(height: 8),
            ...entry.value.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _WindowRow(
                    task: t,
                    count: provider.planCount(t.id),
                    onTap: () => _openPlan(t),
                  ),
                )),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _openPlan(FieldTask task) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TaskPlanScreen(task: task)))
        .then((_) {
      if (mounted) context.read<FieldTasksProvider>().loadWeekTasks();
    });
  }

  Widget _dayHeader(DateTime day) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_dayLabel(day),
              style: AppTheme.bodyMedium.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  /// Group tasks by their Cairo-local day, preserving order (already sorted by
  /// task_date then window_start server-side).
  Map<DateTime, List<FieldTask>> _groupByDay(List<FieldTask> tasks) {
    final map = <DateTime, List<FieldTask>>{};
    for (final t in tasks) {
      final cairo = t.windowStart.toUtc().add(const Duration(hours: 2));
      final day = DateTime(cairo.year, cairo.month, cairo.day);
      map.putIfAbsent(day, () => []).add(t);
    }
    return map;
  }

  static const _weekdaysAr = [
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  static String _dayLabel(DateTime day) {
    final idx = day.weekday == DateTime.sunday ? 0 : day.weekday;
    return '${_weekdaysAr[idx]} ${day.day}/${day.month}';
  }
}

class _WindowRow extends StatelessWidget {
  final FieldTask task;
  final int count;
  final VoidCallback onTap;
  const _WindowRow(
      {required this.task, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
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
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.place_outlined,
                  size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style:
                          AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text('${_t(task.windowStart)} – ${_t(task.windowEnd)}',
                      style: AppTheme.bodySmall,
                      textDirection: TextDirection.ltr),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: count > 0 ? AppColors.primaryLight : AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 0 ? '$count مكان' : 'لا خطة',
                style: AppTheme.bodySmall.copyWith(
                  color: count > 0 ? AppColors.primary : AppColors.textLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  static String _t(DateTime dt) {
    final cairo = dt.toUtc().add(const Duration(hours: 2));
    return '${cairo.hour.toString().padLeft(2, '0')}:${cairo.minute.toString().padLeft(2, '0')}';
  }
}
