import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/merchant.dart';
import '../../models/task_assignment.dart';
import '../../providers/tasks_provider.dart';
import '../../theme/app_theme.dart';
import '../lead/new_lead_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<TasksProvider>();
    Future.microtask(() => provider.loadTodaysTasks());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TasksProvider>();

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '\u0627\u0644\u0645\u0647\u0627\u0645', // المهام
                    style: AppTheme.heading2,
                  ),
                ),
                if (provider.totalCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${provider.completedCount} / ${provider.totalCount}',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
              ],
            ),
          ),
          // Progress bar
          if (provider.totalCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: provider.totalCount > 0
                      ? provider.completedCount / provider.totalCount
                      : 0,
                  backgroundColor: AppColors.border,
                  color: AppColors.primary,
                  minHeight: 6,
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Body
          Expanded(child: _buildBody(provider)),
        ],
      ),
    );
  }

  Widget _buildBody(TasksProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.buttonRed),
            const SizedBox(height: 12),
            Text(provider.error!, style: AppTheme.bodyLarge),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadTodaysTasks(),
              style: AppTheme.primaryButton(),
              child: Text(
                '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629', // إعادة المحاولة
                style: AppTheme.buttonText,
              ),
            ),
          ],
        ),
      );
    }

    if (provider.tasks.isEmpty) {
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
              child: const Icon(
                Icons.assignment_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '\u0644\u0627 \u062a\u0648\u062c\u062f \u0645\u0647\u0627\u0645 \u062d\u0627\u0644\u064a\u0627\u064b', // لا توجد مهام حالياً
              style: AppTheme.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '\u0633\u062a\u0638\u0647\u0631 \u0645\u0647\u0627\u0645\u0643 \u0647\u0646\u0627 \u0642\u0631\u064a\u0628\u0627\u064b', // ستظهر مهامك هنا قريباً
              style: AppTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => provider.loadTodaysTasks(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: provider.tasks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _TaskCard(task: provider.tasks[index]);
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskAssignment task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
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
          // Top row: avatar + name + status badge
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: task.isPending
                      ? AppColors.primaryLight
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 22,
                  color:
                      task.isPending ? AppColors.primary : AppColors.textLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.leadName,
                      style: AppTheme.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.leadPhone,
                      style: AppTheme.bodySmall,
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              _statusBadge(),
            ],
          ),
          // Notes
          if (task.leadNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.leadNotes,
              style: AppTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Action buttons — only for pending tasks
          if (task.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                // Call button
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchCall(task.leadPhone),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.buttonTeal,
                        foregroundColor: AppColors.textWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.phone, size: 18),
                      label: Text(
                        '\u0627\u062a\u0635\u0627\u0644', // اتصال
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppColors.textWhite,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Register button
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _navigateToRegister(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.buttonOrange,
                        foregroundColor: AppColors.textWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(
                        '\u062a\u0633\u062c\u064a\u0644', // تسجيل
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppColors.textWhite,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Skip button
                SizedBox(
                  height: 40,
                  width: 40,
                  child: IconButton(
                    onPressed: () => _showSkipSheet(context),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.skip_next,
                        size: 20, color: AppColors.textLight),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge() {
    if (task.isPending) return const SizedBox.shrink();

    final (label, color) = switch (task.status) {
      'completed' => (
        '\u062a\u0645', // تم
        AppColors.primary,
      ),
      'skipped' => (
        '\u062a\u0645 \u0627\u0644\u062a\u062e\u0637\u064a', // تم التخطي
        AppColors.textLight,
      ),
      _ => (task.status, AppColors.textMedium),
    };

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

  Future<void> _launchCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _navigateToRegister(BuildContext context) {
    final prefill = Lead.empty().copyWith(
      name: task.leadName,
      phone: task.leadPhone,
      notes: task.leadNotes,
    );

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => NewLeadScreen(
          initialLead: prefill,
          taskAssignmentId: task.id,
        ),
      ),
    )
        .then((_) {
      // Refresh tasks after returning from registration
      if (context.mounted) {
        context.read<TasksProvider>().loadTodaysTasks();
      }
    });
  }

  void _showSkipSheet(BuildContext context) {
    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u062a\u062e\u0637\u064a \u0627\u0644\u0645\u0647\u0645\u0629', // تخطي المهمة
                style: AppTheme.heading3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                textAlign: TextAlign.right,
                style: AppTheme.inputText,
                decoration: AppTheme.inputDecoration(
                  hintText:
                      '\u0633\u0628\u0628 \u0627\u0644\u062a\u062e\u0637\u064a (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)', // سبب التخطي (اختياري)
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.read<TasksProvider>().skipTask(
                          task.id,
                          reason: reasonController.text.trim().isNotEmpty
                              ? reasonController.text.trim()
                              : null,
                        );
                  },
                  style: AppTheme.primaryButton(
                    backgroundColor: AppColors.textLight,
                  ),
                  child: Text(
                    '\u062a\u062e\u0637\u064a', // تخطي
                    style: AppTheme.buttonText,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
