import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/card_application_spec.dart';
import '../../providers/tasks_provider.dart';
import '../../services/analytics.dart';
import '../../services/ekyc_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/responsive_container.dart';
import '../lead/lead_success_screen.dart';

/// Unified merchant-onboarding wizard. Collects the shared KYC core ONCE, then
/// appends a thin module per selected product and a single deduped documents
/// step. Works the same whether the rep onboards for one product or all three.
/// Step 1 scans the ID card and pre-fills personal data via [EkycService].
class CardApplicationWizard extends StatefulWidget {
  /// Products the merchant is being onboarded for (e.g. ['Microfinance', 'BP POS']).
  final List<String> products;
  final String title;
  final String? seedName;
  final String? seedNationalId;
  final String? seedMobile;
  final String? taskAssignmentId;

  const CardApplicationWizard({
    super.key,
    required this.products,
    this.title = 'تسجيل تاجر',
    this.seedName,
    this.seedNationalId,
    this.seedMobile,
    this.taskAssignmentId,
  });

  @override
  State<CardApplicationWizard> createState() => _CardApplicationWizardState();
}

class _CardApplicationWizardState extends State<CardApplicationWizard> {
  final _supabase = Supabase.instance.client;

  CATrack _track = CATrack.individual;
  int _step = 0;
  bool _scanning = false;
  bool _submitting = false;
  String? _error;
  EkycResult? _scan;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _dropdowns = {};
  final Map<String, DateTime?> _dates = {};
  final Map<String, bool> _images = {};

  late final List<CAStep> _modules;

  // The composed flow: KYC core → product modules → deduped documents.
  // (Review is the synthetic step at index == steps length.)
  List<CAStep> get _steps => [...kycCoreSteps, ..._modules, _documentsStep()];
  int get _reviewIndex => _steps.length;

  @override
  void initState() {
    super.initState();
    _modules = [
      for (final p in widget.products)
        if (productModuleStep(p) != null) productModuleStep(p)!,
    ];

    for (final step in [...kycCoreSteps, ..._modules]) {
      for (final f in step.fields) {
        switch (f.kind) {
          case CAFieldKind.text:
          case CAFieldKind.multiline:
          case CAFieldKind.number:
          case CAFieldKind.phone:
          case CAFieldKind.email:
            _controllers[f.key] = TextEditingController();
            break;
          case CAFieldKind.dropdown:
            _dropdowns[f.key] = null;
            break;
          case CAFieldKind.date:
            _dates[f.key] = null;
            break;
          case CAFieldKind.idImage:
          case CAFieldKind.docImage:
            _images[f.key] = false;
            break;
        }
      }
    }
    // Pre-init every possible document so the (track-dependent) docs step is safe.
    for (final d in allDocTypes) {
      _images[d.key] = false;
    }

    if (widget.seedNationalId != null) {
      _controllers['national_id']?.text = widget.seedNationalId!;
    }
    if (widget.seedMobile != null) {
      _controllers['merchant_mobile']?.text = widget.seedMobile!;
    }
    if (widget.seedName != null && widget.seedName!.isNotEmpty) {
      _setName(widget.seedName!);
    }
    Analytics.track('onboarding_opened', properties: {
      'product_count': widget.products.length,
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  CAStep _documentsStep() {
    final docs = requiredDocs(_track, widget.products);
    return CAStep(
      title: 'المستندات المطلوبة',
      subtitle: 'كل مستند يُرفع مرة واحدة لكل التجار والمنتجات',
      icon: Icons.folder_open_outlined,
      fields: [
        for (final d in docs)
          CAField(d.key, d.label, CAFieldKind.docImage, required: !d.optional),
      ],
    );
  }

  // ===== Field visibility & values =====

  List<CAField> _visible(CAStep step) {
    return step.fields.where((f) {
      if (f.track == CATrack.both) return true;
      return (f.track == CATrack.company) == (_track == CATrack.company);
    }).toList();
  }

  String _byKey(String key) {
    if (_controllers.containsKey(key)) return _controllers[key]!.text.trim();
    if (_dropdowns.containsKey(key)) return _dropdowns[key] ?? '';
    if (_dates.containsKey(key)) {
      final d = _dates[key];
      return d == null
          ? ''
          : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return '';
  }

  String _valueOf(CAField f) {
    switch (f.kind) {
      case CAFieldKind.dropdown:
        return _dropdowns[f.key] ?? '';
      case CAFieldKind.date:
        final d = _dates[f.key];
        return d == null ? '' : '${d.day}/${d.month}/${d.year}';
      case CAFieldKind.idImage:
      case CAFieldKind.docImage:
        return (_images[f.key] ?? false) ? '✓' : '';
      default:
        return _controllers[f.key]?.text.trim() ?? '';
    }
  }

  Map<String, dynamic> _fieldsOf(CAStep step) {
    final m = <String, dynamic>{};
    for (final f in _visible(step)) {
      if (f.kind == CAFieldKind.idImage || f.kind == CAFieldKind.docImage) continue;
      final v = _byKey(f.key);
      if (v.isNotEmpty) m[f.key] = v;
    }
    return m;
  }

  // ===== OCR scan (step 1) =====

  void _setName(String full) {
    final t = full.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (t.isEmpty) return;
    _controllers['first_name']?.text = t.first;
    _controllers['family_name']?.text = t.length > 1 ? t.last : '';
    final mid = t.length > 2 ? t.sublist(1, t.length - 1) : <String>[];
    _controllers['second_name']?.text = mid.isNotEmpty ? mid[0] : '';
    _controllers['third_name']?.text = mid.length > 1 ? mid[1] : '';
  }

  void _applyScan(EkycResult r) {
    if (r.fullName != null) _setName(r.fullName!);
    if (r.nationalId != null) _controllers['national_id']?.text = r.nationalId!;
    if (r.address != null) _controllers['address']?.text = r.address!;
    if (r.birthDate != null) _dates['birth_date'] = r.birthDate;
  }

  Future<ImageSource?> _pickSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
              title: Text('الكاميرا', style: AppTheme.inputText),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: Text('المعرض', style: AppTheme.inputText),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _captureImage(CAField f) async {
    final source = await _pickSource();
    if (source == null) return;
    final isOcr = f.key == 'id_front';

    if (isOcr) setState(() => _scanning = true);
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 2000, imageQuality: 85);
      if (file == null) {
        if (mounted && isOcr) setState(() => _scanning = false);
        return;
      }
      if (isOcr) {
        Analytics.track('onboarding_scan_started');
        final bytes = await file.readAsBytes();
        final result = await EkycService.instance.scanNationalId(bytes);
        _applyScan(result);
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _images[f.key] = true;
          _scan = result;
        });
        Analytics.track('onboarding_scan_succeeded');
      } else {
        if (!mounted) return;
        setState(() => _images[f.key] = true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر التقاط الصورة. حاول مرة أخرى.')),
      );
      if (isOcr) Analytics.track('onboarding_scan_failed');
    }
  }

  // ===== Navigation & validation =====

  String? _validateStep(CAStep step) {
    for (final f in _visible(step)) {
      final v = _valueOf(f);
      if (f.required && v.isEmpty) {
        return f.kind == CAFieldKind.idImage || f.kind == CAFieldKind.docImage
            ? 'من فضلك صوّر: ${f.label}'
            : 'من فضلك أكمل: ${f.label}';
      }
      if (f.key == 'national_id' && v.isNotEmpty &&
          !RegExp(r'^\d{14}$').hasMatch(v)) {
        return 'الرقم القومي يجب أن يكون ١٤ رقم';
      }
      if (f.kind == CAFieldKind.phone && v.isNotEmpty &&
          !(v.startsWith('01') && v.length == 11)) {
        return 'رقم الموبايل غير صحيح (${f.label})';
      }
    }
    return null;
  }

  void _next() {
    if (_step < _steps.length) {
      final err = _validateStep(_steps[_step]);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
    }
    setState(() {
      _error = null;
      if (_step <= _reviewIndex) _step++;
    });
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = null;
      _step--;
    });
  }

  // ===== Submit =====

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    // KYC core — collected once, shared across every product.
    final kyc = <String, dynamic>{};
    for (final s in kycCoreSteps) {
      kyc.addAll(_fieldsOf(s));
    }
    // One entry per product, carrying only that product's deltas.
    final productsPayload = [
      for (final p in widget.products)
        {
          'product': p,
          'label': productLabelAr(p),
          'data': productModuleStep(p) != null ? _fieldsOf(productModuleStep(p)!) : {},
        }
    ];
    // Documents, deduped by type.
    final docsPayload = [
      for (final d in requiredDocs(_track, widget.products))
        {'type': d.key, 'label': d.label, 'captured': _images[d.key] ?? false}
    ];

    final application = {
      'track': _track == CATrack.company ? 'company' : 'individual',
      'kyc': kyc,
      'products': productsPayload,
      'documents': docsPayload,
    };

    final nameParts = [
      _byKey('first_name'), _byKey('second_name'),
      _byKey('third_name'), _byKey('family_name'),
    ].where((s) => s.isNotEmpty).join(' ');

    final core = <String, dynamic>{
      'name': nameParts.isNotEmpty ? nameParts : _byKey('shop_name'),
      'phone': _byKey('merchant_mobile'),
      'national_id': _byKey('national_id'),
      'products': widget.products,
      // Typed columns kept in sync with the CHECK constraints (migration 011):
      // a product's detail column is set only when that product is selected.
      'microfinance_amount': widget.products.contains('Microfinance')
          ? double.tryParse(_byKey('mf_amount'))
          : null,
      'acceptance_device_count': widget.products.contains('Acceptance POS')
          ? int.tryParse(_byKey('acc_device_count'))
          : null,
      'business_address': _byKey('branch_address_ar'),
      'notes': '',
      'status': 'lead',
    };
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) core['created_by'] = userId;

    Analytics.track('onboarding_submit_attempted', properties: {
      'track': application['track'],
      'product_count': widget.products.length,
    });

    try {
      final id = await _insertMerchant({...core, 'onboarding_application': application});
      await _onSuccess(id);
    } on PostgrestException catch (e) {
      // Graceful fallback if the JSONB column isn't migrated yet.
      if (e.code == '42703' || e.code == 'PGRST204' ||
          e.message.contains('onboarding_application')) {
        try {
          final id = await _insertMerchant(core);
          await _onSuccess(id);
          return;
        } on PostgrestException catch (e2) {
          _handlePgError(e2);
          return;
        }
      }
      _handlePgError(e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'حدث خطأ غير متوقع';
      });
      Analytics.track('onboarding_submit_failed', properties: {'reason': 'unexpected'});
    }
  }

  Future<String?> _insertMerchant(Map<String, dynamic> payload) async {
    final res = await _supabase.from('merchants').insert(payload).select('id').single();
    return res['id'] as String?;
  }

  void _handlePgError(PostgrestException e) {
    if (!mounted) return;
    String msg;
    String reason;
    if (e.code == '23505') {
      msg = 'هذا الرقم القومي مسجل بالفعل';
      reason = 'duplicate_nid';
    } else if (e.message.contains('رقم الموبايل غير صحيح')) {
      msg = 'رقم الموبايل غير صحيح';
      reason = 'invalid_phone';
    } else if (e.message.contains('رقم القومي غير صحيح')) {
      msg = 'الرقم القومي غير صحيح';
      reason = 'invalid_nid';
    } else {
      msg = 'حدث خطأ أثناء التسجيل';
      reason = 'postgrest_other';
    }
    setState(() {
      _submitting = false;
      _error = msg;
    });
    Analytics.track('onboarding_submit_failed', properties: {'reason': reason, 'pg_code': e.code});
  }

  Future<void> _onSuccess(String? merchantId) async {
    Analytics.track('onboarding_submit_succeeded', properties: {
      'product_count': widget.products.length,
    });
    // Complete the cross-sell task if this onboarding came from one.
    if (widget.taskAssignmentId != null && merchantId != null && mounted) {
      try {
        await context.read<TasksProvider>().completeTask(
              widget.taskAssignmentId!,
              merchantId: merchantId,
            );
      } catch (_) {
        // Best-effort — the merchant is already saved.
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LeadSuccessScreen()),
    );
  }

  // ===== Build =====

  @override
  Widget build(BuildContext context) {
    final isReview = _step == _reviewIndex;
    final totalSteps = _steps.length + 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textWhite,
        centerTitle: true,
        title: Text(
          widget.title,
          style: AppTheme.heading3.copyWith(color: AppColors.textWhite),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _back,
        ),
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProgress(totalSteps),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: isReview ? _buildReview() : _buildStep(_steps[_step]),
                ),
              ),
              _buildFooter(isReview),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(int totalSteps) {
    final current = _step + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('خطوة $current من $totalSteps', style: AppTheme.bodySmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: current / totalSteps,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(CAStep step) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(step.icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(step.title, style: AppTheme.heading3)),
          ],
        ),
        if (step.subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(step.subtitle, style: AppTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        if (_step == 0) ...[
          _buildTrackToggle(),
          const SizedBox(height: 16),
        ],
        for (final f in _visible(step)) ...[
          _buildField(f),
          const SizedBox(height: 16),
        ],
        if (_scan != null && _step == 1) _buildScanSummary(),
        if (_error != null) ...[
          const SizedBox(height: 4),
          _buildError(),
        ],
      ],
    );
  }

  Widget _buildTrackToggle() {
    Widget chip(String label, CATrack track) {
      final selected = _track == track;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _track = track),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.primary : AppColors.border),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTheme.inputText.copyWith(
                color: selected ? AppColors.textWhite : AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('فردي', CATrack.individual),
        const SizedBox(width: 12),
        chip('شركات', CATrack.company),
      ],
    );
  }

  Widget _buildField(CAField f) {
    switch (f.kind) {
      case CAFieldKind.idImage:
      case CAFieldKind.docImage:
        return _buildImageField(f);
      case CAFieldKind.dropdown:
        return _buildDropdown(f);
      case CAFieldKind.date:
        return _buildDate(f);
      default:
        return _buildTextField(f);
    }
  }

  Widget _label(CAField f) {
    return Text(f.required ? '${f.label} *' : f.label, style: AppTheme.labelText);
  }

  Widget _buildTextField(CAField f) {
    final isMultiline = f.kind == CAFieldKind.multiline;
    TextInputType keyboard;
    switch (f.kind) {
      case CAFieldKind.number:
        keyboard = TextInputType.number;
        break;
      case CAFieldKind.phone:
        keyboard = TextInputType.phone;
        break;
      case CAFieldKind.email:
        keyboard = TextInputType.emailAddress;
        break;
      case CAFieldKind.multiline:
        keyboard = TextInputType.multiline;
        break;
      default:
        keyboard = TextInputType.text;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        const SizedBox(height: 8),
        TextField(
          controller: _controllers[f.key],
          keyboardType: keyboard,
          maxLines: isMultiline ? 3 : 1,
          textAlign: TextAlign.right,
          style: AppTheme.inputText,
          decoration: AppTheme.inputDecoration(hintText: f.hint ?? f.label),
        ),
      ],
    );
  }

  Widget _buildDropdown(CAField f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _dropdowns[f.key],
          isExpanded: true,
          style: AppTheme.inputText,
          decoration: AppTheme.inputDecoration(hintText: 'اختر ${f.label}'),
          items: f.options
              .map((o) => DropdownMenuItem<String>(value: o, child: Text(o, style: AppTheme.inputText)))
              .toList(),
          onChanged: (v) => setState(() => _dropdowns[f.key] = v),
        ),
      ],
    );
  }

  Widget _buildDate(CAField f) {
    final d = _dates[f.key];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: d ?? DateTime(1990),
              firstDate: DateTime(1920),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _dates[f.key] = picked);
          },
          child: InputDecorator(
            decoration: AppTheme.inputDecoration().copyWith(
              prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
            ),
            child: Text(
              d == null ? 'اختر التاريخ' : '${d.day}/${d.month}/${d.year}',
              style: d == null ? AppTheme.hintText : AppTheme.inputText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageField(CAField f) {
    final captured = _images[f.key] ?? false;
    final isFront = f.key == 'id_front';
    final busy = isFront && _scanning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: captured ? AppColors.teal20 : AppColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: captured ? AppColors.teal60 : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            captured ? Icons.check_circle : Icons.add_a_photo_outlined,
            color: captured ? AppColors.teal110 : AppColors.textMedium,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(f.label, style: AppTheme.inputText)),
          TextButton(
            onPressed: busy ? null : () => _captureImage(f),
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Text(captured ? 'إعادة' : 'تصوير', style: AppTheme.linkText),
          ),
        ],
      ),
    );
  }

  Widget _buildScanSummary() {
    final s = _scan!;
    final parts = <String>[
      if (s.gender != null) s.gender!,
      if (s.governorate != null) s.governorate!,
      if (s.birthDate != null) 'مواليد ${s.birthDate!.year}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.teal20,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_outlined, color: AppColors.teal110, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(parts.join(' • '), style: AppTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _buildReview() {
    final rows = <Widget>[];

    void section(String title, List<Widget> body) {
      if (body.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(title, style: AppTheme.bodyLarge.copyWith(color: AppColors.primary)),
      ));
      rows.addAll(body);
    }

    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: Text(k, style: AppTheme.bodySmall)),
              Expanded(
                flex: 3,
                child: Text(v, style: AppTheme.bodyMedium.copyWith(color: AppColors.textDark)),
              ),
            ],
          ),
        );

    List<Widget> entriesFor(CAStep step) => [
          for (final f in _visible(step))
            if (f.kind != CAFieldKind.idImage &&
                f.kind != CAFieldKind.docImage &&
                _valueOf(f).isNotEmpty)
              kv(f.label, _valueOf(f)),
        ];

    for (final step in kycCoreSteps) {
      section(step.title, entriesFor(step));
    }
    for (final m in _modules) {
      section(m.title, entriesFor(m));
    }

    final docs = requiredDocs(_track, widget.products);
    final uploaded = docs.where((d) => _images[d.key] ?? false).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.fact_check_outlined, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text('مراجعة وتأكيد', style: AppTheme.heading3),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_track == CATrack.company ? 'شركة' : 'فرد'} • '
          '${widget.products.map(productLabelAr).join(' + ')}',
          style: AppTheme.bodyMedium,
        ),
        ...rows,
        const SizedBox(height: 12),
        Text('المستندات: $uploaded من ${docs.length} مرفوعة',
            style: AppTheme.bodyMedium.copyWith(color: AppColors.primary)),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _buildError(),
        ],
      ],
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.buttonRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _error!,
        style: AppTheme.bodyMedium.copyWith(color: AppColors.buttonRed),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildFooter(bool isReview) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(color: AppColors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting ? null : _back,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_step == 0 ? 'إلغاء' : 'السابق', style: AppTheme.inputText),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _submitting ? null : (isReview ? _submit : _next),
              style: AppTheme.primaryButton(),
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(isReview ? 'إرسال الطلب' : 'متابعة', style: AppTheme.buttonText),
            ),
          ),
        ],
      ),
    );
  }
}
