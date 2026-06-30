<#
build_cred_handouts.ps1 — turn the provisioning credential dump into distributable handouts.

Input:  the TSV written by provision_reps_aman_2026-06-29.sh when run with CRED_OUT set
        (columns: Name, Phone, EmpID, UserID, TempPassword).

Outputs (next to the input file, in a sibling folder named <input>_handouts):
  1. credentials.xlsx        — master sheet for YOUR encrypted vault only. NEVER send whole.
                               (falls back to credentials.csv (UTF-8 BOM, Arabic-safe) if Excel/COM absent)
  2. messages\<phone>.txt     — one bilingual message per rep, containing ONLY that rep's login.
                               This is what you copy-paste into WhatsApp/email, one rep at a time.

SECURITY:
  - Plaintext passwords. Run only on the encrypted laptop. Keep outputs on the encrypted volume.
  - Send each rep ONLY their own messages\<phone>.txt — never the master sheet.
  - SHRED the input TSV and the whole handouts folder once distribution is done.

Usage:
  pwsh -File scripts/build_cred_handouts.ps1 -Tsv "C:\Users\marwan.haahmed\aman-creds-2026-06-29.tsv"
  (Windows PowerShell also works: powershell -File ...)
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$Tsv
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Tsv)) { throw "Input TSV not found: $Tsv" }

$rows = Import-Csv -Path $Tsv -Delimiter "`t"
if (-not $rows -or $rows.Count -eq 0) { throw "No rows parsed from $Tsv" }

$required = @('Name', 'Phone', 'EmpID', 'TempPassword')
foreach ($col in $required) {
  if ($rows[0].PSObject.Properties.Name -notcontains $col) {
    throw "Input is missing required column '$col'. Found: $($rows[0].PSObject.Properties.Name -join ', ')"
  }
}

$base    = [System.IO.Path]::GetDirectoryName((Resolve-Path $Tsv))
$stem    = [System.IO.Path]::GetFileNameWithoutExtension($Tsv)
$outDir  = Join-Path $base "${stem}_handouts"
$msgDir  = Join-Path $outDir 'messages'
New-Item -ItemType Directory -Force -Path $msgDir | Out-Null

# --- 1. Master sheet (xlsx via Excel COM if available, else Arabic-safe CSV) ---
$xlsxPath = Join-Path $outDir 'credentials.xlsx'
$csvPath  = Join-Path $outDir 'credentials.csv'
$wroteXlsx = $false
try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false
  $wb = $excel.Workbooks.Add()
  $ws = $wb.Worksheets.Item(1)
  $ws.Name = 'Credentials'
  $headers = @('Name', 'Phone', 'EmpID', 'TempPassword')
  for ($c = 0; $c -lt $headers.Count; $c++) { $ws.Cells.Item(1, $c + 1) = $headers[$c] }
  $r = 2
  foreach ($row in $rows) {
    $ws.Cells.Item($r, 1) = [string]$row.Name
    # leading apostrophe forces text so Excel keeps the + and leading digits
    $ws.Cells.Item($r, 2) = "'" + [string]$row.Phone
    $ws.Cells.Item($r, 3) = "'" + [string]$row.EmpID
    $ws.Cells.Item($r, 4) = "'" + [string]$row.TempPassword
    $r++
  }
  $ws.Range("A1:D1").Font.Bold = $true
  $ws.Columns.Item(1).ColumnWidth = 34
  $ws.Columns.Item(2).ColumnWidth = 16
  $ws.Columns.Item(4).ColumnWidth = 20
  $wb.SaveAs($xlsxPath, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
  $wb.Close($false)
  $excel.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
  $wroteXlsx = $true
}
catch {
  # Excel not installed / COM unavailable — fall back to a UTF-8-BOM CSV (opens cleanly in Excel, Arabic-safe).
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('Name,Phone,EmpID,TempPassword')
  foreach ($row in $rows) {
    $vals = @($row.Name, $row.Phone, $row.EmpID, $row.TempPassword) | ForEach-Object {
      '"' + ([string]$_).Replace('"', '""') + '"'
    }
    [void]$sb.AppendLine($vals -join ',')
  }
  $enc = New-Object System.Text.UTF8Encoding($true)   # BOM so Excel detects UTF-8
  [System.IO.File]::WriteAllText($csvPath, $sb.ToString(), $enc)
}

# --- 2. Per-rep messages (only that rep's own credentials) ---
$appUrl = 'https://yflwudkmhqwoscipscbb.supabase.co'  # informational; reps use the APK, not this URL
$count = 0
foreach ($row in $rows) {
  $name  = [string]$row.Name
  $phone = [string]$row.Phone
  $pw    = [string]$row.TempPassword
  $safe  = ($phone -replace '[^\d]', '')
  $msg = @"
مرحباً $name،

تم إنشاء حسابك على تطبيق أمان (Aman One).
بيانات الدخول:
  • رقم الموبايل: $phone
  • كلمة المرور المؤقتة: $pw

سيُطلب منك تغيير كلمة المرور عند أول تسجيل دخول.
لا تشارك هذه البيانات مع أي شخص.

---
Hello $name,

Your Aman One account is ready.
Login:
  • Phone:    $phone
  • Temp password: $pw

You will be asked to change your password on first login.
Do not share these credentials with anyone.
"@
  $msgPath = Join-Path $msgDir "$safe.txt"
  $enc = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($msgPath, $msg, $enc)
  $count++
}

Write-Host "================================================================"
Write-Host "  Handouts built in: $outDir"
if ($wroteXlsx) { Write-Host "  Master sheet:  credentials.xlsx" }
else            { Write-Host "  Master sheet:  credentials.csv  (Excel COM unavailable; CSV opens in Excel)" }
Write-Host "  Per-rep msgs:  messages\<phone>.txt   ($count files)"
Write-Host "================================================================"
Write-Host "  REMINDERS:"
Write-Host "   - Send each rep ONLY their own messages\<phone>.txt. Never the master sheet."
Write-Host "   - Keep everything on the encrypted volume."
Write-Host "   - SHRED the input TSV + this folder once all reps have logged in."
Write-Host "================================================================"
