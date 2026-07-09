import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/field_task.dart';
import '../../models/task_visit.dart';
import '../../providers/field_tasks_provider.dart';
import '../../providers/lookups_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_search_sheet.dart';

/// The per-mission "add planned stop" form. Same place pickers as the visit
/// form, but WITHOUT GPS / photo / counts — planning captures WHERE the rep
/// intends to go, not what happened. Saves via add_plan_item.
class AddPlanItemScreen extends StatefulWidget {
  final FieldTask task;
  const AddPlanItemScreen({super.key, required this.task});

  @override
  State<AddPlanItemScreen> createState() => _AddPlanItemScreenState();
}

class _AddPlanItemScreenState extends State<AddPlanItemScreen> {
  final _formKey = GlobalKey<FormState>();

  int? _governorateId;
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  // mission 1
  PlaceKind? _placeKind;
  final _placeNameCtrl = TextEditingController();
  // mission 2
  final Set<VisitProduct> _products = {};
  final _merchantCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  // mission 3
  String? _branchId;
  String? _branchName;

  VisitMission get _mission =>
      VisitMission.fromSlug(widget.task.templateSlug) ?? VisitMission.govSchools;
  bool get _isGov => _mission == VisitMission.govSchools;
  bool get _isMerchants => _mission == VisitMission.merchants;
  bool get _isBranch => _mission == VisitMission.branch;
  bool get _needsGovernorate => _isGov || _isMerchants;

  @override
  void initState() {
    super.initState();
    final lookups = context.read<LookupsProvider>();
    Future.microtask(lookups.ensureLoaded);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _placeNameCtrl.dispose();
    _merchantCtrl.dispose();
    _businessCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إضافة مكان للخطة', style: AppTheme.heading3),
        backgroundColor: AppColors.white,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(widget.task.title,
                  style: AppTheme.bodyMedium.copyWith(color: AppColors.textLight)),
              const SizedBox(height: 16),
              if (_isGov) ..._govFields(),
              if (_isMerchants) ..._merchantFields(),
              if (_isBranch) ..._branchFields(),
              if (_needsGovernorate) ...[
                _label('المحافظة'),
                _governorateDropdown(),
                const SizedBox(height: 16),
              ],
              _label('ملاحظات (اختياري)'),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                textAlign: TextAlign.right,
                style: AppTheme.inputText,
                decoration: AppTheme.inputDecoration(hintText: 'ملاحظات التخطيط'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: AppTheme.primaryButton(),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.textWhite),
                        )
                      : Text('إضافة للخطة', style: AppTheme.buttonText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- mission-specific fields ----

  List<Widget> _govFields() => [
        _label('نوع المنشأة'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: PlaceKind.values.map((k) {
            final selected = _placeKind == k;
            return ChoiceChip(
              label: Text(k.labelAr),
              selected: selected,
              onSelected: (_) => setState(() => _placeKind = k),
              selectedColor: AppColors.primaryLight,
              labelStyle: AppTheme.bodyMedium.copyWith(
                color: selected ? AppColors.primary : AppColors.textMedium,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _label('اسم المنشأة'),
        _textField(_placeNameCtrl, 'اسم المدرسة أو المؤسسة أو المستشفى'),
        const SizedBox(height: 16),
      ];

  List<Widget> _merchantFields() => [
        _label('المنتج'),
        Wrap(
          spacing: 8,
          children: VisitProduct.values.map((p) {
            final selected = _products.contains(p);
            return FilterChip(
              label: Text(p.labelAr),
              selected: selected,
              onSelected: (v) => setState(() {
                if (v) {
                  _products.add(p);
                } else {
                  _products.remove(p);
                }
              }),
              selectedColor: AppColors.primaryLight,
              checkmarkColor: AppColors.primary,
              labelStyle: AppTheme.bodyMedium.copyWith(
                color: selected ? AppColors.primary : AppColors.textMedium,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _label('اسم التاجر'),
        _textField(_merchantCtrl, 'اسم التاجر'),
        const SizedBox(height: 16),
        _label('اسم النشاط التجاري'),
        _textField(_businessCtrl, 'اسم المحل أو النشاط'),
        const SizedBox(height: 16),
      ];

  List<Widget> _branchFields() => [
        _label('الفرع'),
        _branchPicker(),
        const SizedBox(height: 16),
      ];

  // ---- shared field builders ----

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: AppTheme.labelText),
      );

  Widget _textField(TextEditingController c, String hint) => TextFormField(
        controller: c,
        textAlign: TextAlign.right,
        style: AppTheme.inputText,
        decoration: AppTheme.inputDecoration(hintText: hint),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
      );

  Widget _governorateDropdown() {
    final lookups = context.watch<LookupsProvider>();
    return DropdownButtonFormField<int>(
      initialValue: _governorateId,
      isExpanded: true,
      style: AppTheme.inputText,
      decoration: AppTheme.inputDecoration(hintText: 'اختر المحافظة'),
      items: lookups.governorates
          .map((g) => DropdownMenuItem(value: g.id, child: Text(g.nameAr)))
          .toList(),
      onChanged: (v) => setState(() => _governorateId = v),
    );
  }

  Widget _branchPicker() {
    final lookups = context.watch<LookupsProvider>();
    return BranchPickerField(
      branches: lookups.branches,
      loaded: lookups.loaded,
      selectedName: _branchName,
      onPicked: (b) => setState(() {
        _branchId = b.id;
        _branchName = b.nameAr;
      }),
    );
  }

  // ---- save ----

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isGov && _placeKind == null) {
      return _snack('برجاء اختيار نوع المنشأة', isError: true);
    }
    if (_isMerchants && _products.isEmpty) {
      return _snack('برجاء اختيار منتج واحد على الأقل', isError: true);
    }
    if (_isBranch && (_branchId == null || _branchId!.isEmpty)) {
      return _snack('برجاء اختيار الفرع', isError: true);
    }
    if (_needsGovernorate && _governorateId == null) {
      return _snack('برجاء اختيار المحافظة', isError: true);
    }

    setState(() => _saving = true);
    final provider = context.read<FieldTasksProvider>();
    final err = await provider.addPlanItem(
      taskId: widget.task.id,
      governorateId: _needsGovernorate ? _governorateId : null,
      notes: _notesCtrl.text.trim(),
      placeKind: _isGov ? _placeKind?.value : null,
      placeName: _isGov ? _placeNameCtrl.text.trim() : null,
      products: _isMerchants ? _products.map((p) => p.value).toList() : null,
      merchantName: _isMerchants ? _merchantCtrl.text.trim() : null,
      businessName: _isMerchants ? _businessCtrl.text.trim() : null,
      branchId: _isBranch ? _branchId : null,
      templateSlug: _mission.slug,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (err == null) {
      _snack('تمت الإضافة للخطة', isError: false);
      Navigator.of(context).pop(true);
    } else {
      _snack(err, isError: true);
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
}
