import 'package:flutter/material.dart';

/// Declarative spec for the unified merchant-onboarding wizard.
///
/// The model separates *who the merchant is* (the shared [kycCoreSteps],
/// collected once) from *what they're signing up for* ([productModuleStep] —
/// the per-product deltas) and the documents they must provide ([requiredDocs],
/// deduped by type). A merchant can be onboarded for one product or all of them
/// in a single pass — the KYC core is never re-asked, and a document needed by
/// several products is collected once.

enum CAFieldKind { text, multiline, number, phone, email, date, dropdown, idImage, docImage }

/// Which customer track a field/step applies to.
enum CATrack { both, individual, company }

/// Which nationality a field/step applies to. Egyptians scan a National ID;
/// foreigners scan a passport. Asked up-front (before the ID scan) so the right
/// document and the right identity fields are shown.
enum CANationality { both, egyptian, foreigner }

class CAField {
  final String key;
  final String label; // Arabic label shown to the rep
  final CAFieldKind kind;
  final bool required;
  final CATrack track;
  final CANationality nat;
  final bool prefill; // populated from the ID-card / passport OCR scan
  final List<String> options; // for dropdown
  final String? hint;

  const CAField(
    this.key,
    this.label,
    this.kind, {
    this.required = false,
    this.track = CATrack.both,
    this.nat = CANationality.both,
    this.prefill = false,
    this.options = const [],
    this.hint,
  });
}

class CAStep {
  final String title; // Arabic step title
  final String subtitle;
  final IconData icon;
  final List<CAField> fields;

  const CAStep({
    required this.title,
    this.subtitle = '',
    required this.icon,
    required this.fields,
  });
}

/// A document type. The same type required by several products is collected
/// once (deduped on [key]).
class DocType {
  final String key;
  final String label;
  final bool optional;
  const DocType(this.key, this.label, {this.optional = false});
}

// ===== Products =============================================================

const products = ['Microfinance', 'Acceptance POS', 'BP POS'];

String productLabelAr(String product) {
  switch (product) {
    case 'Microfinance':
      return 'تمويل المشروعات';
    case 'Acceptance POS':
      return 'نقاط البيع البنكية';
    case 'BP POS':
      return 'دفع الفواتير';
  }
  return product;
}

// ===== Option lists (Arabic) ==============================================
// Hardcoded for the pilot/demo. In production these become searchable pickers
// backed by lookups (activity_types already exists; governorates, banks,
// services would graduate to reference tables).

const _governorates = [
  'القاهرة', 'الجيزة', 'الإسكندرية', 'القليوبية', 'الدقهلية', 'الشرقية',
  'الغربية', 'المنوفية', 'البحيرة', 'كفر الشيخ', 'دمياط', 'بورسعيد',
  'الإسماعيلية', 'السويس', 'الفيوم', 'بني سويف', 'المنيا', 'أسيوط',
  'سوهاج', 'قنا', 'الأقصر', 'أسوان', 'البحر الأحمر', 'الوادي الجديد',
  'مطروح', 'شمال سيناء', 'جنوب سيناء',
];

const _activityTypes = [
  'سوبر ماركت', 'صيدلية', 'مطعم', 'كافيه', 'بقالة',
  'ملابس', 'إلكترونيات', 'مواد بناء', 'خدمات', 'أخرى',
];

const _deviceTypes = ['POS ثابت', 'POS محمول', 'POS لاسلكي', 'Soft POS'];

const _banks = [
  'البنك الأهلي المصري', 'بنك مصر', 'بنك القاهرة', 'البنك التجاري الدولي CIB',
  'بنك الإسكندرية', 'QNB الأهلي', 'بنك التعمير والإسكان', 'أخرى',
];

const _paymentServices = ['دفع بالكارت', 'تقسيط', 'دفع وتقسيط'];

const _billServices = [
  'كهرباء', 'مياه', 'غاز', 'تليفون أرضي', 'شحن موبايل',
  'إنترنت', 'اشتراكات وخدمات حكومية', 'متنوع',
];

const _loanPurposes = ['شراء بضاعة', 'توسعة النشاط', 'تجهيزات ومعدات', 'رأس مال عامل', 'أخرى'];

const _capacities = ['صاحب النشاط', 'مدير', 'مفوّض بالتوقيع', 'شريك'];

// ===== KYC core (collected ONCE, shared across all products) ===============

// 1) Identity document capture — the front/passport triggers the OCR pre-fill.
// Egyptians scan a National ID; foreigners scan a passport (chosen up-front).
const CAStep _idStep = CAStep(
  title: 'تصوير وثيقة الهوية',
  subtitle: 'صوّر بطاقة الرقم القومي أو جواز السفر لملء البيانات تلقائياً',
  icon: Icons.document_scanner_outlined,
  fields: [
    // Egyptian — National ID card (front triggers NID OCR).
    CAField('id_front', 'صورة البطاقة (الوجه)', CAFieldKind.idImage,
        required: true, prefill: true, nat: CANationality.egyptian),
    CAField('id_back', 'صورة البطاقة (الخلف)', CAFieldKind.idImage,
        nat: CANationality.egyptian),
    // Foreigner — passport (triggers passport OCR).
    CAField('passport_image', 'صورة جواز السفر', CAFieldKind.idImage,
        required: true, prefill: true, nat: CANationality.foreigner),
  ],
);

// 2) Personal identity data — pre-filled from the scan, rep reviews.
const CAStep _personalStep = CAStep(
  title: 'البيانات الشخصية',
  subtitle: 'راجع البيانات المستخرجة من الوثيقة',
  icon: Icons.badge_outlined,
  fields: [
    CAField('first_name', 'الاسم الأول', CAFieldKind.text,
        required: true, prefill: true),
    CAField('second_name', 'الاسم الثاني', CAFieldKind.text, prefill: true),
    CAField('third_name', 'الاسم الثالث', CAFieldKind.text, prefill: true),
    CAField('family_name', 'اللقب العائلي', CAFieldKind.text,
        required: true, prefill: true),
    // Egyptian identity — 14-digit National ID.
    CAField('national_id', 'الرقم القومي', CAFieldKind.number,
        required: true, prefill: true, nat: CANationality.egyptian),
    // Foreigner identity — passport number + nationality (country).
    CAField('passport_number', 'رقم جواز السفر', CAFieldKind.text,
        required: true, prefill: true, nat: CANationality.foreigner),
    CAField('nationality_country', 'الجنسية', CAFieldKind.text,
        required: true, prefill: true, nat: CANationality.foreigner),
    CAField('birth_date', 'تاريخ الميلاد', CAFieldKind.date,
        required: true, prefill: true),
    CAField('address', 'العنوان', CAFieldKind.multiline,
        required: true, prefill: true),
    CAField('first_name_en', 'الاسم بالإنجليزية (First name)', CAFieldKind.text,
        prefill: true),
    CAField('family_name_en', 'اللقب بالإنجليزية (Family name)', CAFieldKind.text,
        prefill: true),
  ],
);

// 3) Business / branch data (+ company registration numbers).
const CAStep _businessStep = CAStep(
  title: 'بيانات النشاط والفرع',
  icon: Icons.storefront_outlined,
  fields: [
    CAField('shop_name', 'اسم المحل', CAFieldKind.text, required: true),
    CAField('shop_name_en', 'اسم المحل بالإنجليزية', CAFieldKind.text),
    CAField('legal_name_en', 'الاسم القانوني بالإنجليزية', CAFieldKind.text,
        track: CATrack.company),
    // Auto-extracted from the document scans in the documents step (prefill);
    // editable, so the rep can correct OCR or type manually if needed.
    CAField('commercial_reg', 'رقم السجل التجاري', CAFieldKind.text,
        track: CATrack.company, prefill: true,
        hint: 'يُستخرج تلقائياً من صورة السجل في خطوة المستندات'),
    CAField('tax_card', 'رقم البطاقة الضريبية', CAFieldKind.text,
        track: CATrack.company, prefill: true,
        hint: 'يُستخرج تلقائياً من صورة البطاقة الضريبية في خطوة المستندات'),
    CAField('activity_type', 'نوع النشاط', CAFieldKind.dropdown,
        required: true, options: _activityTypes),
    // Optional merchant information (migration 012) — the old lead form
    // captured this; keep it flowing into merchants.avg_monthly_sales.
    CAField('avg_monthly_sales', 'متوسط المبيعات الشهرية (جنيه)',
        CAFieldKind.number),
    CAField('sub_specialty', 'التخصص الفرعي', CAFieldKind.text),
    CAField('branch_name', 'اسم الفرع', CAFieldKind.text),
    CAField('governorate', 'المحافظة', CAFieldKind.dropdown,
        required: true, options: _governorates),
    CAField('city', 'المدينة', CAFieldKind.text, required: true),
    CAField('branch_address_ar', 'عنوان الفرع بالعربية', CAFieldKind.multiline,
        required: true),
    CAField('branch_address_en', 'عنوان الفرع بالإنجليزية', CAFieldKind.multiline),
    CAField('merchant_mobile', 'رقم محمول التاجر', CAFieldKind.phone, required: true),
    CAField('mobile', 'رقم محمول آخر', CAFieldKind.phone),
    CAField('work_phone', 'رقم هاتف العمل', CAFieldKind.phone),
    CAField('email', 'البريد الإلكتروني', CAFieldKind.email),
    // Nationality (Egyptian / foreigner) is chosen up-front on the first step,
    // so it is no longer a business-step field.
    CAField('capacity', 'الصفة', CAFieldKind.dropdown,
        required: true, options: _capacities),
  ],
);

// 4) Settlement / bank.
const CAStep _settlementStep = CAStep(
  title: 'بيانات التسوية',
  subtitle: 'الحساب البنكي الذي تُورَّد إليه المبالغ',
  icon: Icons.account_balance_outlined,
  fields: [
    CAField('bank_name', 'اسم البنك', CAFieldKind.dropdown,
        required: true, options: _banks),
    CAField('bank_account_number', 'رقم الحساب البنكي', CAFieldKind.text,
        required: true),
    CAField('account_holder', 'اسم صاحب الحساب', CAFieldKind.text, required: true),
  ],
);

/// The shared KYC the merchant fills exactly once.
const List<CAStep> kycCoreSteps = [
  _idStep,
  _personalStep,
  _businessStep,
  _settlementStep,
];

// ===== Per-product modules (delta fields only, namespaced keys) ============

const CAStep _microfinanceModule = CAStep(
  title: 'بيانات تمويل المشروعات',
  icon: Icons.payments_outlined,
  fields: [
    CAField('mf_amount', 'المبلغ المطلوب', CAFieldKind.number, required: true),
    CAField('mf_purpose', 'الغرض من التمويل', CAFieldKind.dropdown,
        options: _loanPurposes),
  ],
);

const CAStep _acceptanceModule = CAStep(
  title: 'بيانات نقاط البيع البنكية',
  icon: Icons.point_of_sale_outlined,
  fields: [
    CAField('acc_device_type', 'نوع الجهاز', CAFieldKind.dropdown,
        required: true, options: _deviceTypes),
    CAField('acc_device_count', 'عدد الأجهزة', CAFieldKind.number, required: true),
    CAField('acc_device_id', 'معرف الجهاز', CAFieldKind.text),
    CAField('acc_payment_service', 'خدمة الدفع', CAFieldKind.dropdown,
        required: true, options: _paymentServices),
  ],
);

const CAStep _bpModule = CAStep(
  title: 'بيانات دفع الفواتير',
  icon: Icons.receipt_long_outlined,
  fields: [
    CAField('bp_device_type', 'نوع الجهاز', CAFieldKind.dropdown,
        required: true, options: _deviceTypes),
    CAField('bp_device_count', 'عدد الأجهزة', CAFieldKind.number, required: true),
    CAField('bp_device_id', 'معرف الجهاز', CAFieldKind.text),
    CAField('bp_bill_service', 'خدمة دفع الفواتير', CAFieldKind.dropdown,
        required: true, options: _billServices),
  ],
);

/// The delta step for a product, or null if the product has no extra fields.
CAStep? productModuleStep(String product) {
  switch (product) {
    case 'Microfinance':
      return _microfinanceModule;
    case 'Acceptance POS':
      return _acceptanceModule;
    case 'BP POS':
      return _bpModule;
  }
  return null;
}

// ===== Document registry (typed, deduped) ==================================

const _docContract = DocType('doc_contract', 'عقد أمان موقّع');
const _docCommercialReg = DocType('doc_commercial_reg', 'صورة السجل التجاري');
const _docTaxCard = DocType('doc_tax_card', 'صورة البطاقة الضريبية');
const _docShopPhoto = DocType('doc_shop_photo', 'صورة المحل');
const _docDeviceAgreement = DocType('doc_device_agreement', 'إقرار استلام الجهاز');
const _docIncomeProof = DocType('doc_income_proof', 'إثبات دخل', optional: true);

/// Every possible document — used to pre-init capture state.
const List<DocType> allDocTypes = [
  _docContract, _docCommercialReg, _docTaxCard,
  _docShopPhoto, _docDeviceAgreement, _docIncomeProof,
];

/// Documents whose capture also runs OCR to *fetch* a value into a form field.
/// Maps the document key -> the form-field key its scan populates. The wizard
/// uses this to decide whether to OCR a captured document and where to put the
/// result. Same eKYC facade as the National-ID scan — capturing the commercial
/// register / tax card image extracts the number instead of a manual entry.
const Map<String, String> ocrFetchDocs = {
  'doc_commercial_reg': 'commercial_reg',
  'doc_tax_card': 'tax_card',
};

/// Deduped union of documents required by the track + the selected products.
/// A document needed by several products appears once. ID front/back are
/// captured in the scan step, so they are not repeated here.
List<DocType> requiredDocs(CATrack track, List<String> selectedProducts) {
  final out = <String, DocType>{};
  void add(DocType d) => out.putIfAbsent(d.key, () => d);

  add(_docContract); // all merchants sign the Aman contract
  if (track == CATrack.company) {
    add(_docCommercialReg);
    add(_docTaxCard);
  }
  for (final p in selectedProducts) {
    switch (p) {
      case 'Acceptance POS':
        add(_docShopPhoto);
        add(_docDeviceAgreement);
        break;
      case 'BP POS':
        add(_docShopPhoto); // shared with Acceptance → still collected once
        break;
      case 'Microfinance':
        add(_docIncomeProof);
        break;
    }
  }
  return out.values.toList();
}
