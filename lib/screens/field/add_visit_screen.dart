import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/aman_branch.dart';
import '../../models/field_task.dart';
import '../../models/task_visit.dart';
import '../../providers/field_tasks_provider.dart';
import '../../providers/lookups_provider.dart';
import '../../services/location_service.dart';
import '../../services/visit_photo_service.dart';
import '../../theme/app_theme.dart';

/// The per-mission "add visit" form. Fields shown depend on the task's mission
/// (gov/schools, merchants, or Aman branch). Captures GPS + a required photo +
/// contacted/onboarded counts + notes, then logs the visit via the provider.
class AddVisitScreen extends StatefulWidget {
  final FieldTask task;
  const AddVisitScreen({super.key, required this.task});

  @override
  State<AddVisitScreen> createState() => _AddVisitScreenState();
}

class _AddVisitScreenState extends State<AddVisitScreen> {
  final _formKey = GlobalKey<FormState>();

  // shared
  int? _governorateId;
  final _contactedCtrl = TextEditingController();
  final _onboardedCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  XFile? _photo;
  ({double lat, double lng, double? acc, DateTime at})? _fix;
  bool _capturingGps = false;
  bool _submitting = false;

  // mission 1
  PlaceKind? _placeKind;
  final _placeNameCtrl = TextEditingController();
  // mission 2
  final Set<VisitProduct> _products = {};
  final _merchantCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  // mission 2: «هل تم التقديم؟»
  bool? _applicationSubmitted;
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
    // Capture the provider synchronously (before the async gap) to avoid using
    // BuildContext across an await.
    final lookups = context.read<LookupsProvider>();
    Future.microtask(lookups.ensureLoaded);
  }

  @override
  void dispose() {
    _contactedCtrl.dispose();
    _onboardedCtrl.dispose();
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
        title: Text('تسجيل زيارة', style: AppTheme.heading3),
        backgroundColor: AppColors.white,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
                Text(widget.task.title,
                    style: AppTheme.bodyMedium
                        .copyWith(color: AppColors.textLight)),
                const SizedBox(height: 16),

                if (_isGov) ..._govFields(),
                if (_isMerchants) ..._merchantFields(),
                if (_isBranch) ..._branchFields(),

                if (_needsGovernorate) ...[
                  _label('المحافظة'),
                  _governorateDropdown(),
                  const SizedBox(height: 16),
                ],

                // Counts are M1/M3 only — M2 asks «هل تم التقديم؟» instead
                // (rendered inside _merchantFields).
                if (!_isMerchants) ...[
                  _label('عدد العملاء الذين تم التواصل معهم'),
                  _numberField(_contactedCtrl, 'مثال: 12'),
                  const SizedBox(height: 16),
                  _label('عدد العملاء الذين تم تسجيلهم'),
                  _numberField(_onboardedCtrl, 'مثال: 3'),
                  const SizedBox(height: 16),
                ],

                _label('صورة المكان'),
                _photoPicker(),
                const SizedBox(height: 16),

                _label('الموقع'),
                _gpsRow(),
                const SizedBox(height: 16),

                _label('تفاصيل الزيارة'),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  textAlign: TextAlign.right,
                  style: AppTheme.inputText,
                  decoration: AppTheme.inputDecoration(hintText: 'تفاصيل الزيارة'),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: AppTheme.primaryButton(),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.textWhite),
                          )
                        : Text('حفظ الزيارة', style: AppTheme.buttonText),
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
        // Single-select: each chip binds to the one _placeKind value.
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
        _label('هل تم التقديم؟'),
        Row(
          children: [
            _yesNoChip('نعم', true),
            const SizedBox(width: 8),
            _yesNoChip('لا', false),
          ],
        ),
        const SizedBox(height: 16),
      ];

  Widget _yesNoChip(String label, bool value) {
    final selected = _applicationSubmitted == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _applicationSubmitted = value),
      selectedColor: AppColors.primaryLight,
      labelStyle: AppTheme.bodyMedium.copyWith(
        color: selected ? AppColors.primary : AppColors.textMedium,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  List<Widget> _branchFields() => [
        _label('الفرع'),
        _branchPicker(),
        const SizedBox(height: 16),
      ];

  /// Strip the leading "Aman -" prefix for a cleaner display label.
  static String branchLabel(String name) =>
      name.replaceFirst(RegExp(r'^Aman\s*[-–]\s*'), '').trim();

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

  Widget _numberField(TextEditingController c, String hint) => TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.right,
        style: AppTheme.inputText,
        decoration: AppTheme.inputDecoration(hintText: hint),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'هذا الحقل مطلوب';
          if (int.tryParse(v.trim()) == null) return 'أدخل رقماً صحيحاً';
          return null;
        },
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
    if (lookups.loaded && lookups.branches.isEmpty) {
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
    final selected = _branchName != null;
    return InkWell(
      onTap: () => _openBranchSearch(lookups.branches),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: AppTheme.inputDecoration(),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected ? branchLabel(_branchName!) : 'ابحث عن الفرع…',
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

  Future<void> _openBranchSearch(List<AmanBranch> branches) async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<AmanBranch>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BranchSearchSheet(branches: branches),
    );
    if (picked != null && mounted) {
      setState(() {
        _branchId = picked.id;
        _branchName = picked.nameAr;
      });
    }
  }

  Widget _photoPicker() {
    return GestureDetector(
      onTap: _submitting ? null : _choosePhotoSource,
      child: Container(
        height: _photo == null ? 96 : 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _photo == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined,
                      size: 28, color: AppColors.primary),
                  const SizedBox(height: 6),
                  Text('اضغط لالتقاط صورة', style: AppTheme.bodySmall),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(_photo!.path), fit: BoxFit.cover),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh,
                              size: 16, color: AppColors.textWhite),
                          const SizedBox(width: 4),
                          Text('إعادة الالتقاط',
                              style: AppTheme.bodySmall
                                  .copyWith(color: AppColors.textWhite)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _gpsRow() {
    final has = _fix != null;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: has
                  ? AppColors.primaryLight
                  : AppColors.inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(has ? Icons.check_circle : Icons.location_searching,
                    size: 18,
                    color: has ? AppColors.primary : AppColors.textLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    has
                        ? '${_fix!.lat.toStringAsFixed(5)}, ${_fix!.lng.toStringAsFixed(5)}'
                        : 'لم يتم تحديد الموقع',
                    style: AppTheme.bodySmall,
                    textDirection: has ? TextDirection.ltr : TextDirection.rtl,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _capturingGps ? null : _captureGps,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textWhite,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            icon: _capturingGps
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.textWhite))
                : const Icon(Icons.my_location, size: 16),
            label: Text(has ? 'تحديث' : 'تحديد',
                style: AppTheme.bodyMedium.copyWith(
                    color: AppColors.textWhite, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ---- actions ----

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.primary),
              title: Text('الكاميرا', style: AppTheme.bodyLarge),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: Text('معرض الصور', style: AppTheme.bodyLarge),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await VisitPhotoService.pick(source);
    if (file != null && mounted) setState(() => _photo = file);
  }

  Future<void> _captureGps() async {
    setState(() => _capturingGps = true);
    final res = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() => _capturingGps = false);
    if (res.isSuccess) {
      final p = res.position!;
      setState(() => _fix =
          (lat: p.latitude, lng: p.longitude, acc: p.accuracy, at: p.timestamp));
    } else {
      _snack(res.error ?? 'تعذّر تحديد الموقع', isError: true);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // mission-specific required fields
    if (_isGov && _placeKind == null) {
      return _snack('برجاء اختيار نوع المنشأة', isError: true);
    }
    if (_isMerchants && _products.isEmpty) {
      return _snack('برجاء اختيار منتج واحد على الأقل', isError: true);
    }
    if (_isBranch && (_branchId == null || _branchId!.isEmpty)) {
      return _snack('برجاء اختيار الفرع', isError: true);
    }
    if (_isMerchants && _applicationSubmitted == null) {
      return _snack('برجاء تحديد ما إذا تم التقديم', isError: true);
    }
    if (_needsGovernorate && _governorateId == null) {
      return _snack('برجاء اختيار المحافظة', isError: true);
    }

    // M2 doesn't collect counts (asks «هل تم التقديم؟» instead) — store 0/0.
    final contacted = _isMerchants ? 0 : int.parse(_contactedCtrl.text.trim());
    final onboarded = _isMerchants ? 0 : int.parse(_onboardedCtrl.text.trim());
    if (!_isMerchants && onboarded > contacted) {
      return _snack('عدد المسجلين لا يمكن أن يتجاوز عدد المتواصل معهم',
          isError: true);
    }

    if (_photo == null) {
      return _snack('صورة المكان مطلوبة', isError: true);
    }
    if (_fix == null) {
      return _snack('برجاء تحديد الموقع أولاً', isError: true);
    }

    final provider = context.read<FieldTasksProvider>();

    // One-time consent gate before any location leaves the device.
    if (!provider.locationConsent) {
      final agreed = await _consentDialog();
      if (agreed != true) return;
      final saved = await provider.grantConsent();
      if (!saved) {
        if (mounted) _snack(provider.error ?? 'تعذّر حفظ الموافقة', isError: true);
        return;
      }
    }

    setState(() => _submitting = true);

    // Upload the photo first, then log the visit with its Storage path.
    String photoPath;
    try {
      photoPath = await VisitPhotoService.upload(_photo!, widget.task.id);
    } on VisitPhotoException catch (e) {
      if (mounted) setState(() => _submitting = false);
      return _snack(e.messageAr, isError: true);
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
      return _snack('تعذّر رفع الصورة. برجاء المحاولة مرة أخرى.', isError: true);
    }

    final outcome = await provider.addVisit(
      taskId: widget.task.id,
      lat: _fix!.lat,
      lng: _fix!.lng,
      accuracyM: _fix!.acc,
      recordedAt: _fix!.at,
      photoPath: photoPath,
      contactedCount: contacted,
      onboardedCount: onboarded,
      governorateId: _needsGovernorate ? _governorateId : null,
      notes: _notesCtrl.text.trim(),
      placeKind: _isGov ? _placeKind?.value : null,
      placeName: _isGov ? _placeNameCtrl.text.trim() : null,
      products: _isMerchants ? _products.map((p) => p.value).toList() : null,
      merchantName: _isMerchants ? _merchantCtrl.text.trim() : null,
      businessName: _isMerchants ? _businessCtrl.text.trim() : null,
      branchId: _isBranch ? _branchId : null,
      applicationSubmitted: _isMerchants ? _applicationSubmitted : null,
      templateSlug: _mission.slug,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (outcome.success) {
      _snack(
        outcome.inWindow ? 'تم تسجيل الزيارة داخل الوقت المحدد' : 'تم تسجيل الزيارة',
        isError: false,
      );
      Navigator.of(context).pop(true);
    } else {
      _snack(outcome.error ?? 'تعذّر تسجيل الزيارة', isError: true);
    }
  }

  Future<bool?> _consentDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تسجيل الموقع', style: AppTheme.heading3),
        content: Text(
          'سيقوم تطبيق أمان بتسجيل موقعك الحالي عند حفظ الزيارة، وذلك لأغراض '
          'الإشراف فقط. لا يتم تتبع موقعك في الخلفية.',
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

/// A searchable, scrollable branch picker. Type-ahead filters the ~250 branches
/// so the rep finds their store in a couple of keystrokes instead of scrolling.
class _BranchSearchSheet extends StatefulWidget {
  final List<AmanBranch> branches;
  const _BranchSearchSheet({required this.branches});

  @override
  State<_BranchSearchSheet> createState() => _BranchSearchSheetState();
}

class _BranchSearchSheetState extends State<_BranchSearchSheet> {
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
    // Take most of the screen but leave room for the keyboard.
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
                      child: Text('لا توجد نتائج مطابقة',
                          style: AppTheme.bodyMedium),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const Divider(
                          height: 1, color: AppColors.border, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        final b = _filtered[i];
                        return ListTile(
                          leading: const Icon(Icons.store_mall_directory_outlined,
                              color: AppColors.primary, size: 20),
                          title: Text(
                            _AddVisitScreenState.branchLabel(b.nameAr),
                            style: AppTheme.bodyLarge,
                          ),
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
