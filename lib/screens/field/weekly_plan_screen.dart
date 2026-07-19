import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/field_task.dart';
import '../../providers/field_tasks_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/cairo_datetime.dart';
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
    if (provider.error != null && provider.weekTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.buttonRed),
            const SizedBox(height: 12),
            Text(provider.error!, style: AppTheme.bodyLarge),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: provider.loadWeekTasks,
              style: AppTheme.primaryButton(),
              child: Text('إعادة المحاولة', style: AppTheme.buttonText),
            ),
          ],
        ),
      );
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
          Text('خطّط زياراتك لكامل الأسبوع (الجمعة – الخميس)',
              style: AppTheme.bodyMedium.copyWith(color: AppColors.textLight)),
          const SizedBox(height: 8),
          _planningWindowBanner(),
          const SizedBox(height: 12),
          for (final entry in byDay.entries) ...[
            // Label from a real task timestamp (not the naive grouping key).
            _dayHeader(entry.value.first.windowStart),
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

  /// Shows whether the planning window (Thu 6pm → Fri 2pm) is open. When closed,
  /// the server refuses add/remove; this tells the rep why before they try.
  Widget _planningWindowBanner() {
    final open = cairoPlanningWindowOpen();
    final closingSoon = open && cairoPlanningWindowClosingSoon();
    // Three states: open (green), open-but-closing-soon after 12pm (amber),
    // closed (red). The hard cutoff is 2pm — soft close is a UI nudge only.
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;
    if (!open) {
      bg = const Color(0xFFFDECEC);
      fg = AppColors.buttonRed;
      icon = Icons.lock_clock_outlined;
      text = 'التخطيط مغلق — متاح من الخميس ٦ مساءً حتى الجمعة ٢ ظهراً';
    } else if (closingSoon) {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFB26A00);
      icon = Icons.timelapse_outlined;
      text = 'التخطيط يُغلق الساعة ٢ ظهراً — سارِع بإنهاء خطتك';
    } else {
      bg = AppColors.primaryLight;
      fg = AppColors.primary;
      icon = Icons.lock_open_outlined;
      text = 'التخطيط مفتوح الآن — عدّل خطتك قبل الجمعة ٢ ظهراً';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: AppTheme.bodySmall.copyWith(color: fg)),
          ),
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

  Widget _dayHeader(DateTime windowStart) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(cairoDayLabel(windowStart),
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
      final cairo = toCairo(t.windowStart);
      final day = DateTime(cairo.year, cairo.month, cairo.day);
      map.putIfAbsent(day, () => []).add(t);
    }
    return map;
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
                  Text('${cairoHm(task.windowStart)} – ${cairoHm(task.windowEnd)}',
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
}
