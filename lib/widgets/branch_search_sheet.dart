import 'package:flutter/material.dart';
import '../models/aman_branch.dart';
import '../theme/app_theme.dart';

/// Strip the leading "Aman -" prefix for a cleaner display label.
String branchLabel(String name) =>
    name.replaceFirst(RegExp(r'^Aman\s*[-–]\s*'), '').trim();

/// A tap-to-open branch field: shows the picked branch (or a hint) and opens a
/// searchable bottom-sheet over the ~250 branches. Shared by the visit form and
/// the planning form.
class BranchPickerField extends StatelessWidget {
  final List<AmanBranch> branches;
  final bool loaded;
  final String? selectedName;
  final ValueChanged<AmanBranch> onPicked;

  const BranchPickerField({
    super.key,
    required this.branches,
    required this.loaded,
    required this.selectedName,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    if (loaded && branches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text('لا توجد فروع متاحة حالياً', style: AppTheme.bodySmall),
      );
    }
    final selected = selectedName != null;
    return InkWell(
      onTap: () => _openSearch(context),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: AppTheme.inputDecoration(),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected ? branchLabel(selectedName!) : 'ابحث عن الفرع…',
                style: selected ? AppTheme.inputText : AppTheme.hintText,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(selected ? Icons.edit_location_alt_outlined : Icons.search,
                size: 20, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<AmanBranch>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BranchSearchSheet(branches: branches),
    );
    if (picked != null) onPicked(picked);
  }
}

/// A searchable, scrollable branch picker. Type-ahead filters the ~250 branches
/// so the rep finds their store in a couple of keystrokes instead of scrolling.
class BranchSearchSheet extends StatefulWidget {
  final List<AmanBranch> branches;
  const BranchSearchSheet({super.key, required this.branches});

  @override
  State<BranchSearchSheet> createState() => _BranchSearchSheetState();
}

class _BranchSearchSheetState extends State<BranchSearchSheet> {
  final _searchCtrl = TextEditingController();
  late List<AmanBranch> _filtered = widget.branches;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.branches
          : widget.branches
              .where((b) => b.nameAr.toLowerCase().contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textAlign: TextAlign.right,
                style: AppTheme.inputText,
                onChanged: _onSearch,
                decoration: AppTheme.inputDecoration(
                  hintText: 'ابحث باسم الفرع أو المنطقة…',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textLight),
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child:
                          Text('لا توجد نتائج مطابقة', style: AppTheme.bodyMedium),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: AppColors.border,
                          indent: 16,
                          endIndent: 16),
                      itemBuilder: (_, i) {
                        final b = _filtered[i];
                        return ListTile(
                          leading: const Icon(Icons.store_mall_directory_outlined,
                              color: AppColors.primary, size: 20),
                          title: Text(branchLabel(b.nameAr),
                              style: AppTheme.bodyLarge),
                          onTap: () => Navigator.of(context).pop(b),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
