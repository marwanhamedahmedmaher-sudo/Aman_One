import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/field_task.dart';
import '../../models/task_visit.dart';
import '../../providers/field_tasks_provider.dart';
import '../../theme/app_theme.dart';
import 'add_visit_screen.dart';

/// Lists the visits logged for one field task and lets the rep add more
/// («أدخل زيارة») and explicitly finish the task («إنهاء المهمة»).
class TaskVisitsScreen extends StatefulWidget {
  final FieldTask task;
  const TaskVisitsScreen({super.key, required this.task});

  @override
  State<TaskVisitsScreen> createState() => _TaskVisitsScreenState();
}

class _TaskVisitsScreenState extends State<TaskVisitsScreen> {
  late Future<List<TaskVisit>> _visitsFuture;
  List<TaskVisit> _visits = [];
  bool _completing = false;

  VisitMission? get _mission => VisitMission.fromSlug(widget.task.templateSlug);
  bool get _isBranchMission => _mission == VisitMission.branch;
  bool get _capReached => _isBranchMission && _visits.length >= 2;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _visitsFuture = context.read<FieldTasksProvider>().fetchVisits(widget.task.id);
    _visitsFuture.then((v) {
      if (mounted) setState(() => _visits = v);
    });
  }

  Future<void> _addVisit() async {
    if (_mission == null) {
      _snack('نوع المهمة غير معروف', isError: true);
      return;
    }
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddVisitScreen(task: widget.task)),
    );
    if (added == true && mounted) setState(_reload);
  }

  Future<void> _completeTask() async {
    setState(() => _completing = true);
    final provider = context.read<FieldTasksProvider>();
    final ok = await provider.completeTask(widget.task.id);
    if (!mounted) return;
    setState(() => _completing = false);
    if (ok) {
      _snack('تم إنهاء المهمة', isError: false);
      Navigator.of(context).pop();
    } else {
      _snack(provider.error ?? 'تعذّر إنهاء المهمة', isError: true);
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
    final done = widget.task.status == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title, style: AppTheme.heading3),
        backgroundColor: AppColors.white,
      ),
      // Floating "add visit" icon — sits just above the bottom «إنهاء المهمة»
      // bar (which lives in bottomNavigationBar), so the two never overlap.
      floatingActionButton: (done || _capReached)
          ? null
          : FloatingActionButton(
              onPressed: _addVisit,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textWhite,
              tooltip: 'أدخل زيارة',
              child: const Icon(Icons.add_location_alt_outlined),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: done ? null : _completeBar(),
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
          const Icon(Icons.schedule, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('الوقت المحدد', style: AppTheme.bodySmall),
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
    return FutureBuilder<List<TaskVisit>>(
      future: _visitsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && _visits.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (_visits.isEmpty) {
          return _emptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          itemCount: _visits.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _VisitCard(visit: _visits[i]),
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
            child: const Icon(Icons.add_location_alt_outlined,
                size: 36, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('لا توجد زيارات بعد', style: AppTheme.bodyLarge),
          const SizedBox(height: 6),
          Text('اضغط "أدخل زيارة" لتسجيل أول زيارة',
              style: AppTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _completeBar() {
    final canComplete = _visits.isNotEmpty && !_completing;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        // Extra top padding leaves room for the floating "add visit" icon.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canComplete ? _completeTask : null,
              style: AppTheme.primaryButton(),
              child: _completing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textWhite),
                    )
                  : Text('إنهاء المهمة', style: AppTheme.buttonText),
            ),
          ),
        ),
      ),
    );
  }

  static String _t(DateTime dt) {
    final cairo = dt.toUtc().add(const Duration(hours: 2));
    return '${cairo.hour.toString().padLeft(2, '0')}:${cairo.minute.toString().padLeft(2, '0')}';
  }
}

class _VisitCard extends StatelessWidget {
  final TaskVisit visit;
  const _VisitCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    final color = visit.inWindow ? AppColors.primary : AppColors.buttonOrange;
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
                child: Text(visit.title,
                    style: AppTheme.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  visit.inWindow ? 'في الموعد' : 'خارج الموعد',
                  style: AppTheme.bodySmall.copyWith(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (visit.governorateName != null)
                _meta(Icons.location_city_outlined, visit.governorateName!),
              if (visit.products.isNotEmpty)
                _meta(Icons.sell_outlined, _productsLabel(visit.products)),
              // M2 shows «تم التقديم» instead of contacted/onboarded counts.
              if (visit.templateSlug == 'merchants_acceptance_finance')
                _meta(Icons.assignment_turned_in_outlined,
                    'تم التقديم: ${visit.applicationSubmitted == true ? 'نعم' : 'لا'}')
              else
                _meta(Icons.people_outline,
                    'تواصل ${visit.contactedCount} • تسجيل ${visit.onboardedCount}'),
              _meta(Icons.schedule, _t(visit.recordedAt)),
            ],
          ),
          if (visit.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(visit.notes,
                style: AppTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
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

  static String _productsLabel(List<String> products) {
    return products
        .map((p) => p == 'microfinance'
            ? 'تمويل'
            : p == 'acceptance'
                ? 'Acceptance'
                : p)
        .join(' + ');
  }

  static String _t(DateTime dt) {
    final cairo = dt.toUtc().add(const Duration(hours: 2));
    return '${cairo.hour.toString().padLeft(2, '0')}:${cairo.minute.toString().padLeft(2, '0')}';
  }
}
