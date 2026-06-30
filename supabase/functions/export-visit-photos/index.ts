// ============================================================================
// export-visit-photos — supervisor/admin signed-URL export of field-visit photos
//
// The task-visit-photos bucket is PRIVATE. This function lets an authorized
// supervisor or admin pull time-limited signed URLs for all visit photos on a
// given Cairo day, as JSON or a CSV ready for Excel.
//
//   GET /functions/v1/export-visit-photos?date=YYYY-MM-DD&format=csv|json
//
// Auth: the caller's JWT must belong to a user whose public.users.role is
// 'supervisor' or 'admin' (checked under RLS with the caller's own token).
// Signing is done with the service-role key (never exposed to the client).
// ============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BUCKET = 'task-visit-photos';
const SIGNED_URL_TTL = 60 * 60 * 24 * 7; // 7 days

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function cairoToday(): string {
  const c = new Date(Date.now() + 2 * 3600 * 1000); // Cairo = UTC+2, no DST
  return c.toISOString().slice(0, 10);
}

function csvCell(v: unknown): string {
  const s = v == null ? '' : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return json({ error: 'missing_authorization' }, 401);

  // 1. Identify the caller and confirm they are supervisor/admin (under RLS).
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: auth } = await userClient.auth.getUser();
  const user = auth?.user;
  if (!user) return json({ error: 'unauthorized' }, 401);

  const { data: me } = await userClient
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single();
  if (!me || (me.role !== 'supervisor' && me.role !== 'admin')) {
    return json({ error: 'forbidden', detail: 'supervisor or admin only' }, 403);
  }

  const url = new URL(req.url);
  const date = url.searchParams.get('date') ?? cairoToday();
  const format = (url.searchParams.get('format') ?? 'json').toLowerCase();

  // 2. Service-role client for the data read + signing.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: visits, error: vErr } = await admin
    .from('task_visits')
    .select(
      'id, rep_id, recorded_at, in_window, photo_path, template_slug, ' +
        'place_name, merchant_name, business_name, contacted_count, onboarded_count, ' +
        'application_submitted, ' +
        'governorates(name_ar), aman_branches(name_ar), field_tasks!inner(title, task_date)',
    )
    .eq('field_tasks.task_date', date)
    .order('recorded_at', { ascending: true });

  if (vErr) return json({ error: 'query_failed', detail: vErr.message }, 500);
  if (!visits || visits.length === 0) {
    return format === 'csv'
      ? new Response('﻿no_data\n', {
          headers: { ...CORS, 'Content-Type': 'text/csv; charset=utf-8' },
        })
      : json({ date, count: 0, rows: [] });
  }

  // 3. Rep names (FK is to auth.users, so resolve public.users separately).
  const repIds = [...new Set(visits.map((v) => v.rep_id))];
  const { data: users } = await admin
    .from('users')
    .select('id, name, employee_id')
    .in('id', repIds);
  const userMap = new Map((users ?? []).map((u) => [u.id, u]));

  // 4. Batch-sign every photo path.
  const paths = visits.map((v) => v.photo_path).filter(Boolean) as string[];
  const { data: signed } = await admin.storage.from(BUCKET).createSignedUrls(paths, SIGNED_URL_TTL);
  const urlByPath = new Map((signed ?? []).map((s) => [s.path, s.signedUrl]));

  const entity = (v: Record<string, unknown>) =>
    (v.place_name as string) ||
    [v.merchant_name, v.business_name].filter(Boolean).join(' - ') ||
    ((v.aman_branches as { name_ar?: string } | null)?.name_ar ?? '');

  const rows = visits.map((v) => {
    const u = userMap.get(v.rep_id);
    const isM2 = v.template_slug === 'merchants_acceptance_finance';
    return {
      rep_name: u?.name ?? '',
      employee_id: u?.employee_id ?? '',
      task: (v.field_tasks as { title?: string })?.title ?? '',
      date,
      entity: entity(v as Record<string, unknown>),
      governorate: (v.governorates as { name_ar?: string } | null)?.name_ar ?? '',
      submitted: v.application_submitted == null
        ? ''
        : (v.application_submitted ? 'نعم' : 'لا'),
      // M2 doesn't collect counts (asks «هل تم التقديم؟» instead).
      contacted: isM2 ? '' : v.contacted_count,
      onboarded: isM2 ? '' : v.onboarded_count,
      recorded_at: v.recorded_at,
      in_window: v.in_window,
      photo_url: urlByPath.get(v.photo_path) ?? '',
    };
  });

  if (format === 'csv') {
    const headers = [
      'اسم المندوب', 'رقم الموظف', 'المهمة', 'التاريخ', 'الجهة', 'المحافظة',
      'تم التقديم', 'عدد المتواصل معهم', 'عدد المسجلين', 'وقت الزيارة', 'الالتزام', 'رابط الصورة',
    ];
    const lines = [headers.join(',')];
    for (const r of rows) {
      lines.push([
        r.rep_name, r.employee_id, r.task, r.date, r.entity, r.governorate,
        r.submitted, r.contacted, r.onboarded, r.recorded_at,
        r.in_window ? 'في الموعد' : 'خارج الموعد', r.photo_url,
      ].map(csvCell).join(','));
    }
    return new Response('﻿' + lines.join('\n'), {
      headers: {
        ...CORS,
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="visit-photos-${date}.csv"`,
      },
    });
  }

  return json({ date, count: rows.length, ttl_seconds: SIGNED_URL_TTL, rows });
});
