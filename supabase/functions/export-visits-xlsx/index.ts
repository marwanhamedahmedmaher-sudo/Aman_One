// ============================================================================
// export-visits-xlsx — Excel export of field activity. Sheet 1: task_visits
// (current build) with the photo embedded inline in each row. Sheet 2 (only
// when rows exist): task_checkins — the OLD one-check-in-per-task model still
// being written by reps on the pre-visits APK. Interim visibility until the
// fleet upgrade (P1-17); remove the sheet once task_checkins goes quiet.
//
// A sales rep exports their OWN activity; a supervisor/admin exports everyone's.
// RTL Arabic worksheets. Photo bucket stays private.
//
//   GET /functions/v1/export-visits-xlsx?from=YYYY-MM-DD&to=YYYY-MM-DD  (range, inclusive)
//   GET /functions/v1/export-visits-xlsx?date=YYYY-MM-DD                (one Cairo day, legacy)
//   GET /functions/v1/export-visits-xlsx                               (all visits, capped)
//
// Photos are fetched with the service-role key and embedded as thumbnails.
// ============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { encodeBase64 } from 'jsr:@std/encoding/base64';
import ExcelJS from 'https://esm.sh/exceljs@4.4.0';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BUCKET = 'task-visit-photos';
const MAX_ROWS = 500;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function err(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function hhmmCairo(iso: string): string {
  const d = new Date(new Date(iso).getTime() + 2 * 3600 * 1000);
  return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
}

const VISIT_TYPE: Record<string, string> = {
  gov_schools_hospitals: 'مؤسسات حكومية / مدارس / مستشفيات',
  merchants_acceptance_finance: 'تجار — Acceptance / تمويل',
  aman_branch_visit: 'فرع أمان',
};
const PLACE_KIND: Record<string, string> = {
  school: 'مدرسة',
  gov_institution: 'مؤسسة حكومية',
  hospital: 'مستشفى',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return err({ error: 'missing_authorization' }, 401);

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: auth } = await userClient.auth.getUser();
  const user = auth?.user;
  if (!user) return err({ error: 'unauthorized' }, 401);

  const { data: me } = await userClient.from('users').select('role').eq('id', user.id).single();
  const role = me?.role;
  if (role !== 'sales_rep' && role !== 'supervisor' && role !== 'admin') {
    return err({ error: 'forbidden', detail: 'not authorized' }, 403);
  }
  // A sales rep exports only their own visits; supervisor/admin export everyone's.
  const privileged = role === 'supervisor' || role === 'admin';

  const url = new URL(req.url);
  const date = url.searchParams.get('date');   // legacy single-day
  const from = url.searchParams.get('from');   // YYYY-MM-DD (inclusive)
  const to = url.searchParams.get('to');       // YYYY-MM-DD (inclusive)
  const label = date ?? ((from || to) ? `${from ?? 'start'}_${to ?? 'end'}` : 'all');

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const dateFilter = (q: any) => {
    if (date) return q.eq('field_tasks.task_date', date);
    if (from) q = q.gte('field_tasks.task_date', from);
    if (to) q = q.lte('field_tasks.task_date', to);
    return q;
  };

  let q = admin
    .from('task_visits')
    .select(
      'id, rep_id, recorded_at, in_window, photo_path, template_slug, ' +
        'place_kind, place_name, products, merchant_name, business_name, ' +
        'application_submitted, contacted_count, onboarded_count, notes, lat, lng, ' +
        'governorates(name_ar), aman_branches(name_ar), field_tasks!inner(title, task_date)',
    )
    .order('recorded_at', { ascending: false })
    .limit(MAX_ROWS);
  q = dateFilter(q);
  if (!privileged) q = q.eq('rep_id', user.id); // rep → own visits only

  const { data: visits, error: vErr } = await q;
  if (vErr) return err({ error: 'query_failed', detail: vErr.message }, 500);

  // OLD-model check-ins (pre-visits APK). Same scoping + date filter. A query
  // error here must not sink the visits export — the sheet is best-effort.
  let cq = admin
    .from('task_checkins')
    .select(
      'rep_id, recorded_at, in_window, lat, lng, accuracy_m, ' +
        'field_tasks!inner(title, task_date, window_start, window_end)',
    )
    .order('recorded_at', { ascending: false })
    .limit(MAX_ROWS);
  cq = dateFilter(cq);
  if (!privileged) cq = cq.eq('rep_id', user.id);
  const { data: checkins } = await cq;

  const repIds = [
    ...new Set([...(visits ?? []), ...(checkins ?? [])].map((r) => r.rep_id)),
  ];
  const { data: users } = repIds.length
    ? await admin.from('users').select('id, name, employee_id, region').in('id', repIds)
    : { data: [] as any[] };
  const userMap = new Map((users ?? []).map((u) => [u.id, u]));

  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('الزيارات', { views: [{ rightToLeft: true }] });
  ws.columns = [
    { header: 'اسم المندوب', key: 'rep', width: 20 },
    { header: 'رقم الموظف', key: 'emp', width: 12 },
    { header: 'المنطقة', key: 'region', width: 12 },
    { header: 'المهمة', key: 'task', width: 26 },
    { header: 'التاريخ', key: 'date', width: 12 },
    { header: 'نوع الزيارة', key: 'type', width: 22 },
    { header: 'الجهة', key: 'entity', width: 22 },
    { header: 'التصنيف', key: 'kind', width: 14 },
    { header: 'المنتجات', key: 'products', width: 16 },
    { header: 'تم التقديم', key: 'submitted', width: 10 },
    { header: 'المحافظة', key: 'gov', width: 14 },
    { header: 'عدد المتواصل معهم', key: 'contacted', width: 16 },
    { header: 'عدد المسجلين', key: 'onboarded', width: 12 },
    { header: 'وقت الزيارة', key: 'time', width: 10 },
    { header: 'الالتزام', key: 'window', width: 12 },
    { header: 'تفاصيل الزيارة', key: 'notes', width: 26 },
    { header: 'رابط الخريطة', key: 'map', width: 16 },
    { header: 'الصورة', key: 'photo', width: 16 },
  ];
  ws.getRow(1).font = { bold: true };
  ws.getRow(1).alignment = { horizontal: 'center', vertical: 'middle' };
  const photoColIdx = ws.columns.length - 1;

  for (const v of visits ?? []) {
    const u = userMap.get(v.rep_id);
    const isM2 = v.template_slug === 'merchants_acceptance_finance';
    const entity =
      v.place_name ||
      [v.merchant_name, v.business_name].filter(Boolean).join(' - ') ||
      ((v.aman_branches as { name_ar?: string } | null)?.name_ar ?? '');
    const products = (v.products ?? [])
      .map((p: string) => (p === 'microfinance' ? 'تمويل' : p === 'acceptance' ? 'Acceptance' : p))
      .join(' + ');

    const row = ws.addRow({
      rep: u?.name ?? '',
      emp: u?.employee_id ?? '',
      region: u?.region ?? '',
      task: (v.field_tasks as { title?: string })?.title ?? '',
      date: (v.field_tasks as { task_date?: string })?.task_date ?? '',
      type: VISIT_TYPE[v.template_slug] ?? v.template_slug,
      entity,
      kind: v.place_kind ? (PLACE_KIND[v.place_kind] ?? '') : '',
      products,
      submitted: v.application_submitted == null ? '' : v.application_submitted ? 'نعم' : 'لا',
      gov: (v.governorates as { name_ar?: string } | null)?.name_ar ?? '',
      contacted: isM2 ? '' : v.contacted_count,
      onboarded: isM2 ? '' : v.onboarded_count,
      time: hhmmCairo(v.recorded_at),
      window: v.in_window ? 'في الموعد' : 'خارج الموعد',
      notes: v.notes ?? '',
      map: { text: 'الخريطة', hyperlink: `https://maps.google.com/?q=${v.lat},${v.lng}` },
    });
    row.height = 64;
    row.alignment = { vertical: 'middle', wrapText: true };

    if (v.photo_path) {
      try {
        const { data: blob, error: dErr } = await admin.storage.from(BUCKET).download(v.photo_path);
        if (!dErr && blob) {
          const bytes = new Uint8Array(await blob.arrayBuffer());
          const imgId = wb.addImage({ base64: encodeBase64(bytes), extension: 'jpeg' });
          ws.addImage(imgId, {
            tl: { col: photoColIdx + 0.15, row: row.number - 1 + 0.1 },
            ext: { width: 80, height: 80 },
          });
        }
      } catch (_) {
        // Skip a bad/oversized image; the rest of the row still exports.
      }
    }
  }

  // Sheet 2 — old check-ins. Skipped entirely when empty, so the sheet
  // disappears on its own once the fleet is on the visits APK.
  if ((checkins ?? []).length) {
    const ws2 = wb.addWorksheet('تسجيلات النظام القديم', { views: [{ rightToLeft: true }] });
    ws2.columns = [
      { header: 'اسم المندوب', key: 'rep', width: 20 },
      { header: 'رقم الموظف', key: 'emp', width: 12 },
      { header: 'المنطقة', key: 'region', width: 12 },
      { header: 'المهمة', key: 'task', width: 26 },
      { header: 'التاريخ', key: 'date', width: 12 },
      { header: 'الوقت المحدد', key: 'sched', width: 14 },
      { header: 'وقت التسجيل', key: 'time', width: 10 },
      { header: 'الالتزام', key: 'window', width: 12 },
      { header: 'الدقة (متر)', key: 'acc', width: 10 },
      { header: 'رابط الخريطة', key: 'map', width: 16 },
    ];
    ws2.getRow(1).font = { bold: true };
    ws2.getRow(1).alignment = { horizontal: 'center', vertical: 'middle' };

    for (const c of checkins ?? []) {
      const u = userMap.get(c.rep_id);
      const ft = c.field_tasks as {
        title?: string; task_date?: string; window_start?: string; window_end?: string;
      };
      ws2.addRow({
        rep: u?.name ?? '',
        emp: u?.employee_id ?? '',
        region: u?.region ?? '',
        task: ft?.title ?? '',
        date: ft?.task_date ?? '',
        sched: ft?.window_start && ft?.window_end
          ? `${hhmmCairo(ft.window_start)} - ${hhmmCairo(ft.window_end)}`
          : '',
        time: hhmmCairo(c.recorded_at),
        window: c.in_window ? 'في الموعد' : 'خارج الموعد',
        acc: c.accuracy_m == null ? '' : Math.round(c.accuracy_m),
        map: { text: 'الخريطة', hyperlink: `https://maps.google.com/?q=${c.lat},${c.lng}` },
      }).alignment = { vertical: 'middle', wrapText: true };
    }
  }

  const buf = await wb.xlsx.writeBuffer();
  return new Response(buf, {
    headers: {
      ...CORS,
      'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="aman-visits-${label}.xlsx"`,
    },
  });
});
