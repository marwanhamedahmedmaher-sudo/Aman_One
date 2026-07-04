// ============================================================================
// admin-users — Supervisor admin-portal backend: manage sales-rep accounts.
//
// Called by docs/admin-portal.html (served via admin-portal-page). The caller
// logs in with phone+password; this function verifies the JWT resolves to an
// ACTIVE supervisor or admin in public.users, then performs the privileged
// operation with the service-role key (never exposed to the page).
//
//   POST /functions/v1/admin-users   { action: 'list' }
//   POST /functions/v1/admin-users   { action: 'create_rep', name, phone,
//                                      employee_id, region, business_unit? }
//   POST /functions/v1/admin-users   { action: 'suspend',        user_id }
//   POST /functions/v1/admin-users   { action: 'reactivate',     user_id }
//   POST /functions/v1/admin-users   { action: 'reset_password', user_id }
//
// Guardrails:
//   * Targets must be role='sales_rep' — the portal can never touch admin or
//     supervisor accounts (no privilege escalation, no self-lockout).
//   * A SUPERVISOR is scoped to their own business_unit: list shows only
//     same-unit users, create_rep always lands in the supervisor's unit
//     (any client-sent business_unit is ignored), and mutations against a
//     rep from another unit are refused. role='admin' is unrestricted.
//   * create_rep always provisions role='sales_rep', must_change_password=true,
//     phone_confirm=true (no SMS). Region restricted to the roster vocabulary.
//   * Suspend = Admin API ban + users.status='suspended' (there is no DB
//     trigger syncing the two — both are set here). An already-issued JWT
//     stays valid until it expires (≤1h); the ban blocks refresh and re-login.
//   * Temp passwords are returned ONCE in the response and never stored or
//     written to audit/new_data. If the profile insert fails after the auth
//     user was created, the auth user is deleted — no orphans (2026-06-29
//     lesson).
//   * Every mutation writes an audit_log row with the caller as actor —
//     closes part of the V1 "admin actions only logged by Dashboard" gap.
// ============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// Roster vocabulary (2026-07-02 territory audit): never bare 'Cairo'.
const REGIONS = ['Greater Cairo', 'Delta', 'Upper Egypt'];
const BAN_DURATION = '87600h'; // ~10 years; cleared with 'none'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}
const fail = (status: number, error: string, detail?: string) =>
  json({ error, detail }, status);

// 16-char alphanumeric temp password (matches provision_rep.sh convention:
// no symbols that confuse copy-paste in messengers). Rejection sampling
// avoids modulo bias.
function genPassword(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let out = '';
  const buf = new Uint8Array(64);
  while (out.length < 16) {
    crypto.getRandomValues(buf);
    for (const b of buf) {
      if (out.length >= 16) break;
      if (b < chars.length * 4) out += chars[b % chars.length]; // 248 < 256 → unbiased
    }
  }
  return out;
}

// Normalize an Egyptian mobile number to E.164 (+201XXXXXXXXX) or null.
// Accepts local 01…, 201…, +201…, 00201…, Arabic-Indic digits, spaces/dashes.
function normalizePhone(raw: unknown): string | null {
  let p = String(raw ?? '')
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[\s\-().]/g, '');
  if (p.startsWith('00')) p = '+' + p.slice(2);
  if (/^01[0-9]{9}$/.test(p)) p = '+2' + p;
  else if (/^201[0-9]{9}$/.test(p)) p = '+' + p;
  return /^\+201[0125][0-9]{8}$/.test(p) ? p : null;
}

const maskPhone = (p: string) => (p.length >= 8 ? `${p.slice(0, 6)}****${p.slice(-4)}` : '****');

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return fail(405, 'method_not_allowed');

  // --- Caller gate: valid JWT → active supervisor/admin -----------------------
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return fail(401, 'missing_authorization');

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: auth } = await userClient.auth.getUser();
  const caller = auth?.user;
  if (!caller) return fail(401, 'unauthorized');

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: me } = await admin
    .from('users')
    .select('name, role, status, business_unit')
    .eq('id', caller.id)
    .single();
  if (!me || !['supervisor', 'admin'].includes(me.role) || me.status !== 'active') {
    return fail(403, 'forbidden', 'هذا الحساب غير مصرّح له باستخدام بوابة الإدارة.');
  }
  // Supervisor → confined to their own business unit; admin → all units.
  const buScope: string | null = me.role === 'supervisor' ? me.business_unit : null;

  const body = await req.json().catch(() => ({}));
  const action = body?.action;

  // The mutation has already succeeded when this runs, so an audit failure
  // must not fail the request — but it must be loud in the function logs.
  const audit = async (auditAction: string, targetId: string | null, details: Record<string, unknown>) => {
    const { error } = await admin.from('audit_log').insert({
      actor_id: caller.id,
      action: auditAction,
      table_name: 'users',
      record_id: targetId,
      new_data: { ...details, via: 'admin-portal' },
    });
    if (error) console.error('audit_write_failed', auditAction, targetId, error.message);
  };

  // Load a mutation target and enforce the sales_rep-only + same-unit rules.
  async function getTarget(id: string) {
    if (!id || typeof id !== 'string') return { error: fail(400, 'bad_request', 'user_id مطلوب.') };
    const { data: target } = await admin
      .from('users')
      .select('id, name, phone, employee_id, business_unit, role, status')
      .eq('id', id)
      .single();
    if (!target) return { error: fail(404, 'not_found', 'المستخدم غير موجود.') };
    if (target.role !== 'sales_rep') {
      return { error: fail(403, 'forbidden', 'لا يمكن تعديل حسابات المشرفين أو مسؤولي النظام من هذه البوابة.') };
    }
    if (buScope && target.business_unit !== buScope) {
      return { error: fail(403, 'forbidden', 'هذا المندوب يتبع وحدة عمل أخرى — يمكنك إدارة مناديب وحدتك فقط.') };
    }
    return { target };
  }

  try {
    switch (action) {
      // ------------------------------------------------------------------ list
      case 'list': {
        let lq = admin
          .from('users')
          .select('id, name, phone, employee_id, business_unit, region, role, status, must_change_password, created_at')
          .order('name', { ascending: true })
          .limit(500);
        if (buScope) lq = lq.eq('business_unit', buScope); // supervisor → own unit only
        const { data: users, error } = await lq;
        if (error) return fail(500, 'query_failed', error.message);
        return json({ users });
      }

      // ------------------------------------------------------------ create_rep
      case 'create_rep': {
        // String() first: a non-string JSON value must land in the 400 paths
        // below, not throw and surface as a generic 500.
        const name = String(body.name ?? '').replace(/\s+/g, ' ').trim();
        const employeeId = String(body.employee_id ?? '').trim();
        const region = String(body.region ?? '').trim();
        // Supervisor always provisions into their OWN unit — the client-sent
        // value is ignored. Admin may set any unit (defaults to Outdoor Retail).
        const businessUnit = buScope ?? (String(body.business_unit ?? '').trim() || 'Outdoor Retail');

        if (name.length < 3) return fail(400, 'bad_request', 'أدخل اسم المندوب كاملًا.');
        if (!employeeId) return fail(400, 'bad_request', 'الرقم الوظيفي مطلوب.');
        if (!REGIONS.includes(region)) {
          return fail(400, 'bad_request', `المنطقة يجب أن تكون واحدة من: ${REGIONS.join(' / ')}`);
        }
        const phone = normalizePhone(body.phone ?? '');
        if (!phone) return fail(400, 'bad_request', 'رقم الموبايل غير صحيح — أدخل رقمًا مصريًا مثل 01012345678.');

        // Dedup by phone against existing profiles (friendly error before the
        // Admin API rejects it anyway).
        const { data: dupPhone } = await admin.from('users').select('id, name').eq('phone', phone).maybeSingle();
        if (dupPhone) return fail(409, 'duplicate_phone', `رقم الموبايل مسجل بالفعل باسم: ${dupPhone.name}`);
        const { data: dupEmp } = await admin.from('users').select('id, name').eq('employee_id', employeeId).maybeSingle();
        if (dupEmp) return fail(409, 'duplicate_employee_id', `الرقم الوظيفي مسجل بالفعل باسم: ${dupEmp.name}`);

        const tempPassword = genPassword();

        const { data: created, error: createErr } = await admin.auth.admin.createUser({
          phone,
          password: tempPassword,
          phone_confirm: true, // pre-confirmed — no SMS (permanent V1 rule)
        });
        if (createErr || !created?.user) {
          const msg = createErr?.message ?? 'unknown';
          if (/already|exists|registered/i.test(msg)) {
            return fail(409, 'duplicate_phone', 'رقم الموبايل مسجل بالفعل في نظام الدخول.');
          }
          return fail(500, 'auth_create_failed', msg);
        }
        const uid = created.user.id;

        const { error: profileErr } = await admin.from('users').insert({
          id: uid,
          name,
          phone,
          employee_id: employeeId,
          business_unit: businessUnit,
          region,
          role: 'sales_rep',
          must_change_password: true,
        });
        if (profileErr) {
          // No orphan auth users — delete what we just created.
          await admin.auth.admin.deleteUser(uid).catch(() => {});
          return fail(500, 'profile_insert_failed', profileErr.message);
        }

        // Belt-and-braces role claim (RLS reads public.users; claim kept in
        // sync for anything that inspects the JWT). Non-fatal on failure.
        const { error: claimErr } = await admin.rpc('set_claim', {
          uid,
          claim: 'role',
          value: 'sales_rep',
        });

        await audit('rep_provisioned', uid, {
          name,
          phone_masked: maskPhone(phone),
          employee_id: employeeId,
          region,
          business_unit: businessUnit,
        });

        return json({
          user_id: uid,
          name,
          phone,
          temp_password: tempPassword, // shown once, never stored
          claim_warning: claimErr ? claimErr.message : undefined,
        });
      }

      // --------------------------------------------------------------- suspend
      case 'suspend': {
        const { target, error } = await getTarget(body.user_id);
        if (error) return error;
        if (target.id === caller.id) return fail(400, 'bad_request', 'لا يمكنك إيقاف حسابك.');

        const { error: banErr } = await admin.auth.admin.updateUserById(target.id, {
          ban_duration: BAN_DURATION,
        });
        if (banErr) return fail(500, 'ban_failed', banErr.message);

        const { error: stErr } = await admin.from('users').update({ status: 'suspended' }).eq('id', target.id);
        if (stErr) return fail(500, 'status_update_failed', stErr.message);

        await audit('rep_suspended', target.id, {
          name: target.name,
          phone_masked: maskPhone(target.phone),
          employee_id: target.employee_id,
        });
        return json({ ok: true, status: 'suspended' });
      }

      // ------------------------------------------------------------ reactivate
      case 'reactivate': {
        const { target, error } = await getTarget(body.user_id);
        if (error) return error;

        const { error: banErr } = await admin.auth.admin.updateUserById(target.id, {
          ban_duration: 'none',
        });
        if (banErr) return fail(500, 'unban_failed', banErr.message);

        const { error: stErr } = await admin.from('users').update({ status: 'active' }).eq('id', target.id);
        if (stErr) return fail(500, 'status_update_failed', stErr.message);

        await audit('rep_reactivated', target.id, {
          name: target.name,
          phone_masked: maskPhone(target.phone),
          employee_id: target.employee_id,
        });
        return json({ ok: true, status: 'active' });
      }

      // -------------------------------------------------------- reset_password
      case 'reset_password': {
        const { target, error } = await getTarget(body.user_id);
        if (error) return error;

        const tempPassword = genPassword();
        const { error: pwErr } = await admin.auth.admin.updateUserById(target.id, {
          password: tempPassword,
        });
        if (pwErr) return fail(500, 'password_update_failed', pwErr.message);

        // Rep must rotate on next login (same flow as provisioning).
        const { error: mcpErr } = await admin
          .from('users')
          .update({ must_change_password: true })
          .eq('id', target.id);
        if (mcpErr) return fail(500, 'status_update_failed', mcpErr.message);

        await audit('rep_password_reset', target.id, {
          name: target.name,
          phone_masked: maskPhone(target.phone),
          employee_id: target.employee_id,
        });
        return json({ ok: true, temp_password: tempPassword }); // shown once, never stored
      }

      default:
        return fail(400, 'bad_request', 'unknown action');
    }
  } catch (e) {
    return fail(500, 'internal', e instanceof Error ? e.message : String(e));
  }
});
