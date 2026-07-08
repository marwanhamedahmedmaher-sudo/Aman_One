import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/field_task.dart';
import '../../models/task_plan_item.dart';
import '../../providers/field_tasks_provider.dart';
import '../../theme/app_theme.dart';
import 'add_plan_item_screen.dart';
import 'add_visit_screen.dart';

/// The plan for one field task (one window on one day): the rep's list of
/// intended stops. Add («أضف مكان»), remove, and — when it's time — execute a
/// planned stop, which opens the visit form pre-filled ("plan drives the visit").
class TaskPlanScreen extends StatefulWidget {
  final FieldTask task;
  const TaskPlanScreen({super.key, required this.task});

  @override
  State<TaskPlanScreen> createState() => _TaskPlanScreenState();
}

class _TaskPlanScreenState extends State<TaskPlanScreen> {
  late Future<List<TaskPlanItem>> _future;
  List<TaskPlanItem> _items = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<FieldTasksProvider>().fetchPlanItems(widget.task.id);
    _future.then((v) {
      if (mounted) setState(() => _items = v);
    });
  }

  Future<void> _addPlace() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddPlanItemScreen(task: widget.task)),
    );
    if (added == true && mounted) setState(_reload);
  }

  Future<void> _execute(TaskPlanItem item) async {
    final logged = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddVisitScreen(task: widget.task, planItem: item),
      ),
    );
    if (logged == true && mounted) setState(_reload);
  }

  Future<void> _remove(TaskPlanItem item) async {
    final provider = context.read<FieldTasksProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('حذف المكان', style: AppTheme.heading3),
        content: Text('هل تريد حذف "${item.title}" من الخطة؟',
            style: AppTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('إلغاء',
                style: AppTheme.bodyMedium.copyWith(color: AppColors.textLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: AppTheme.primaryButton(backgroundColor: AppColors.buttonRed),
            child: Text('حذف', style: AppTheme.buttonText),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await provider.removePlanItem(item.id, taskId: widget.task.id);
    if (!mounted) return;
    if (ok) {
      setState(_reload);
    } else {
      _snack(provider.error ?? 'تعذّر حذف المكان', isError: true);
    }
  }

  void _snack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: AppTheme.bodyMedium.copyWith(color: AppColors.textWhite)),
        backgroundColor: isError ? AppColors.buttonRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title, style: AppTheme.heading3),
        backgroundColor: AppColors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPlace,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textWhite,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text('أضف مكان', style: AppTheme.buttonText),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _windowBanner(),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _windowBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(_dateLabel(widget.task.windowStart), style: AppTheme.bodySmall),
          const Spacer(),
          Text(
            '${_t(widget.task.windowStart)} – ${_t(widget.task.windowEnd)}',
            style: AppTheme.bodyMedium.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.w600),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return FutureBuilder<List<TaskPlanItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && _items.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (_items.isEmpty) return _emptyState();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _PlanCard(
            item: _items[i],
            onVisit: () => _execute(_items[i]),
            onRemove: () => _remove(_items[i]),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
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
            child: const Icon(Icons.map_outlined,
                size: 36, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('لا توجد أماكن مخططة بعد', style: AppTheme.bodyLarge),
          const SizedBox(height: 6),
          Text('اضغط "أضف مكان" لتخطيط زياراتك', style: AppTheme.bodySmall),
        ],
      ),
    );
  }

  static String _t(DateTime dt) {
    final cairo = dt.toUtc().add(const Duration(hours: 2));
    return '${cairo.hour.toString().padLeft(2, '0')}:${cairo.minute.toString().padLeft(2, '0')}';
  }

  static const _weekdaysAr = [
    'الأحد', // DateTime.sunday == 7 -> handled below
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  static String _dateLabel(DateTime dt) {
    final cairo = dt.toUtc().add(const Duration(hours: 2));
    // DateTime.weekday: Mon=1..Sun=7. Map to Arabic (Sun first).
    final idx = cairo.weekday == DateTime.sunday ? 0 : cairo.weekday;
    final name = _weekdaysAr[idx];
    return '$name ${cairo.day}/${cairo.month}';
  }
}

class _PlanCard extends StatelessWidget {
  final TaskPlanItem item;
  final VoidCallback onVisit;
  final VoidCallback onRemove;
  const _PlanCard(
      {required this.item, required this.onVisit, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final visited = item.isVisited;
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.title,
                    style:
                        AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (visited)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('تمت الزيارة',
                      style: AppTheme.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (item.governorateName != null)
                _meta(Icons.location_city_outlined, item.governorateName!),
              if (item.products.isNotEmpty)
                _meta(Icons.sell_outlined, _productsLabel(item.products)),
              if (item.placeKind != null)
                _meta(Icons.category_outlined, _placeKindLabel(item.placeKind!)),
            ],
          ),
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item.notes,
                style: AppTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (!visited) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: onVisit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textWhite,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                      label: Text('تسجيل الزيارة',
                          style: AppTheme.bodyMedium.copyWith(
                              color: AppColors.textWhite,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  width: 40,
                  child: IconButton(
                    onPressed: onRemove,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: AppColors.buttonRed),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textLight),
        const SizedBox(width: 4),
        Text(text, style: AppTheme.bodySmall),
      ],
    );
  }

  static String _productsLabel(List<String> products) => products
      .map((p) => p == 'microfinance'
          ? 'تمويل'
          : p == 'acceptance'
              ? 'Acceptance'
              : p)
      .join(' + ');

  static String _placeKindLabel(String k) => switch (k) {
        'school' => 'مدرسة',
        'gov_institution' => 'مؤسسة حكومية',
        'hospital' => 'مستشفى',
        _ => k,
      };
}
