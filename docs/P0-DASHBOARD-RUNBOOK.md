# P0-18: Admin Dashboard Runbook / دليل لوحة التحكم للمشرف

**Version:** 1.0 | **Date:** 2026-04-14
**Audience:** Non-technical admin operating Supabase Dashboard for the Aman pilot.

---

## Table of Contents / الفهرس

1. [Create a New Sales Rep / إنشاء مندوب جديد](#1-create-a-new-sales-rep--إنشاء-مندوب-جديد)
2. [Suspend or Reactivate a Rep / تعليق أو إعادة تفعيل مندوب](#2-suspend-or-reactivate-a-rep--تعليق-أو-إعادة-تفعيل-مندوب)
3. [Reset a Rep's Password / إعادة تعيين كلمة مرور مندوب](#3-reset-a-reps-password--إعادة-تعيين-كلمة-مرور-مندوب)
4. [Run an Export Snippet / تشغيل استعلام تصدير](#4-run-an-export-snippet--تشغيل-استعلام-تصدير)
5. [Enable 2FA for Your Admin Account / تفعيل المصادقة الثنائية](#5-enable-2fa-for-your-admin-account--تفعيل-المصادقة-الثنائية)

---

## 1. Create a New Sales Rep / إنشاء مندوب جديد

### English

1. Open **Supabase Dashboard** and go to **Authentication** > **Users**.
2. Click **Add user** > **Create new user**.
3. Fill in:
   - **Email:** Use the rep's company email (or a placeholder like `rep_name@aman.local` if no email).
   - **Phone:** The rep's Egyptian mobile number in E.164 format: `+201012345678`.
   - **Password:** Set a temporary password (8+ characters, mix of letters and numbers). Write it down securely.
   - **Auto Confirm User:** Toggle ON.
4. Click **Create user**. Copy the new user's **UUID** from the user list.
5. Go to **SQL Editor** and run this to create their profile:
   ```sql
   INSERT INTO public.users (id, name, phone, employee_id, business_unit, region, role, must_change_password)
   VALUES (
     'PASTE-UUID-HERE',
     'Rep Full Name',
     '+201012345678',
     'EMP-001',
     'Sales Unit',
     'Cairo',
     'sales_rep',
     true
   );
   ```
6. Go to **SQL Editor** and set their role claim:
   ```sql
   SELECT public.set_claim('PASTE-UUID-HERE', 'role', '"sales_rep"');
   ```
7. Send the temporary password to the rep via **email AND WhatsApp**. Include:
   - Their phone number (login username).
   - The temporary password.
   - Instruction: "You will be asked to change your password on first login."

### Arabic / عربي

1. افتح **لوحة تحكم Supabase** واذهب إلى **Authentication** > **Users**.
2. اضغط **Add user** > **Create new user**.
3. املأ البيانات:
   - **Email:** البريد الإلكتروني للمندوب (أو بديل مثل `rep_name@aman.local`).
   - **Phone:** رقم الموبايل بصيغة `+201012345678`.
   - **Password:** كلمة مرور مؤقتة (8 أحرف على الأقل). سجلها بأمان.
   - **Auto Confirm User:** فعّل هذا الخيار.
4. اضغط **Create user**. انسخ **UUID** المستخدم الجديد.
5. اذهب إلى **SQL Editor** وأنشئ ملف المندوب بتشغيل أمر الإدراج أعلاه.
6. شغّل أمر `set_claim` لتعيين الصلاحية.
7. أرسل كلمة المرور المؤقتة للمندوب عبر **البريد الإلكتروني و واتساب**. أضف:
   - رقم الموبايل (اسم المستخدم).
   - كلمة المرور المؤقتة.
   - تعليمات: "سيُطلب منك تغيير كلمة المرور عند أول تسجيل دخول."

---

## 2. Suspend or Reactivate a Rep / تعليق أو إعادة تفعيل مندوب

### English

**To suspend:**
1. Go to **Authentication** > **Users**.
2. Find the rep by searching their phone number or email.
3. Click the rep's row to open their details.
4. Click **Ban user**. This prevents them from logging in.
5. Go to **SQL Editor** and update their status:
   ```sql
   UPDATE public.users SET status = 'suspended' WHERE phone = '+201012345678';
   ```

**To reactivate:**
1. Go to **Authentication** > **Users** > find the rep.
2. Click **Unban user**.
3. Update status in SQL Editor:
   ```sql
   UPDATE public.users SET status = 'active' WHERE phone = '+201012345678';
   ```

### Arabic / عربي

**للتعليق:**
1. اذهب إلى **Authentication** > **Users**.
2. ابحث عن المندوب بالموبايل أو البريد الإلكتروني.
3. اضغط على صف المندوب لفتح التفاصيل.
4. اضغط **Ban user** لمنعه من تسجيل الدخول.
5. حدّث الحالة في **SQL Editor**: شغّل أمر التحديث أعلاه مع `'suspended'`.

**لإعادة التفعيل:**
1. ابحث عن المندوب واضغط **Unban user**.
2. شغّل أمر التحديث مع `'active'`.

---

## 3. Reset a Rep's Password / إعادة تعيين كلمة مرور مندوب

### English

1. Go to **Authentication** > **Users** > find the rep.
2. Click the rep's row to open details.
3. In the user detail panel, update the **password** field with a new temporary password.
4. Go to **SQL Editor** and flag the password for rotation:
   ```sql
   UPDATE public.users SET must_change_password = true WHERE phone = '+201012345678';
   ```
5. Send the new temporary password to the rep via **email AND WhatsApp**:
   - "Your password has been reset. New temporary password: [PASSWORD]. You will be asked to change it on next login."

### Arabic / عربي

1. اذهب إلى **Authentication** > **Users** > ابحث عن المندوب.
2. افتح تفاصيل المندوب وغيّر كلمة المرور.
3. شغّل أمر التحديث في **SQL Editor** لتفعيل `must_change_password = true`.
4. أرسل كلمة المرور الجديدة عبر **البريد الإلكتروني و واتساب**:
   - "تم إعادة تعيين كلمة المرور. كلمة المرور المؤقتة: [PASSWORD]. سيُطلب منك تغييرها عند تسجيل الدخول."

---

## 4. Run an Export Snippet / تشغيل استعلام تصدير

### English

1. Go to **SQL Editor** in Supabase Dashboard.
2. Open the saved snippet you need (or paste from `supabase/migrations/006_export_snippets.sql`):
   - **All active leads (90 days)** — Snippet 1
   - **Last 30 days** — Snippet 2
   - **Leads by rep** — Snippet 3
   - **Audit dump** — Snippet 4 (change the two dates before running)
3. Click **Run**.
4. In the results table, click **Download CSV**.
5. The CSV file will have Arabic column headers and is ready to share.

### Arabic / عربي

1. افتح **SQL Editor** في لوحة تحكم Supabase.
2. افتح الاستعلام المحفوظ أو الصقه من ملف `006_export_snippets.sql`:
   - **جميع العملاء النشطين (90 يوم)** — استعلام 1
   - **آخر 30 يوم** — استعلام 2
   - **العملاء حسب المندوب** — استعلام 3
   - **سجل المراجعة** — استعلام 4 (غيّر التاريخين قبل التشغيل)
3. اضغط **Run**.
4. في جدول النتائج اضغط **Download CSV**.
5. ملف CSV سيحتوي على عناوين أعمدة بالعربية وجاهز للمشاركة.

---

## 5. Enable 2FA for Your Admin Account / تفعيل المصادقة الثنائية

### English

**This is mandatory for all admin accounts.**

1. Go to [supabase.com](https://supabase.com) and log into your account.
2. Click your **avatar** (top right) > **Account preferences**.
3. Under **Security**, find **Two-Factor Authentication**.
4. Click **Enable 2FA**.
5. Scan the QR code with an authenticator app (Google Authenticator, Authy, or 1Password).
6. Enter the 6-digit code to confirm.
7. **Save your recovery codes** in a secure location (password manager or printed and locked away).

### Arabic / عربي

**هذا إجراء إلزامي لجميع حسابات المشرفين.**

1. اذهب إلى [supabase.com](https://supabase.com) وسجّل الدخول.
2. اضغط على **الصورة الشخصية** (أعلى اليمين) > **Account preferences**.
3. تحت **Security** ابحث عن **Two-Factor Authentication**.
4. اضغط **Enable 2FA**.
5. امسح رمز QR بتطبيق المصادقة (Google Authenticator أو Authy أو 1Password).
6. أدخل الرمز المكون من 6 أرقام للتأكيد.
7. **احفظ رموز الاسترداد** في مكان آمن (مدير كلمات مرور أو مطبوعة ومحفوظة).

---

## Quick Reference / مرجع سريع

| Action / الإجراء | Where / أين | Time / الوقت |
|---|---|---|
| Create rep / إنشاء مندوب | Auth UI + SQL Editor | 3 min |
| Suspend rep / تعليق مندوب | Auth UI + SQL Editor | 1 min |
| Reset password / إعادة تعيين كلمة مرور | Auth UI + SQL Editor + WhatsApp | 2 min |
| Export CSV / تصدير CSV | SQL Editor | 1 min |
| Enable 2FA / تفعيل 2FA | Account settings | 2 min |

---

**Important Reminders / تذكيرات مهمة:**
- Always send temporary passwords via **both** email AND WhatsApp.
- Keep the Supabase project member list to 1-2 people maximum.
- 2FA is **mandatory** on all Supabase admin accounts.
- Never share your Supabase Dashboard credentials with anyone.
- All admin actions in the Dashboard are logged by Supabase automatically.
