<#
parse_provision_creds.ps1 — recover credentials from a raw terminal capture.

Use this when the batch was run WITHOUT the CRED_OUT= dump, so the only copy of the
temp passwords is the terminal scrollback. Handles BOTH output shapes:
  1. the batch SUCCESS table (space-padded: Name  Phone  EmpID  UserID  TempPassword)
  2. the per-rep "PROVISIONED ..." boxes from individual scripts/provision_rep.sh runs

It writes a clean TSV, then (unless -NoBuild) runs build_cred_handouts.ps1 to produce
credentials.xlsx + per-rep messages\<phone>.txt.

HOW TO CAPTURE THE INPUT:
  In the Git Bash window, select EVERYTHING from the "--- SUCCESSES ---" header through
  the last "PROVISIONED" box (include the three individual blocks), copy it, paste into a
  new file e.g. C:\Users\marwan.haahmed\aman-creds-raw.txt, save as plain UTF-8.

Usage:
  powershell -File scripts/parse_provision_creds.ps1 -Raw "C:\Users\marwan.haahmed\aman-creds-raw.txt"
  (add -NoBuild to only emit the TSV)
#>

param(
  [Parameter(Mandatory = $true)] [string]$Raw,
  [string]$OutTsv,
  [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Raw)) { throw "Raw capture not found: $Raw" }
if (-not $OutTsv) {
  $dir  = [System.IO.Path]::GetDirectoryName((Resolve-Path $Raw))
  $stem = [System.IO.Path]::GetFileNameWithoutExtension($Raw)
  $OutTsv = Join-Path $dir "$stem.tsv"
}

$lines = Get-Content -Path $Raw -Encoding UTF8
$records = [System.Collections.Generic.List[object]]::new()
$byPhone = @{}

function Add-Rec($name, $phone, $emp, $uid, $pw) {
  if (-not $phone -or -not $pw) { return }
  $phone = $phone.Trim(); $pw = $pw.Trim()
  if ($byPhone.ContainsKey($phone)) { return }   # first wins; dedup across table + boxes
  $rec = [pscustomobject]@{
    Name = ("$name").Trim(); Phone = $phone; EmpID = ("$emp").Trim()
    UserID = ("$uid").Trim(); TempPassword = $pw
  }
  $byPhone[$phone] = $rec
  $records.Add($rec)
}

# --- Pass 1: padded SUCCESS-table rows ---
# Name (may contain single spaces)  Phone(+20...)  EmpID  UserID(uuid)  TempPassword
$tableRe = '^(?<name>.+?)\s{2,}(?<phone>\+\d{10,15})\s{2,}(?<emp>\S+)\s{2,}(?<uid>[0-9a-fA-F-]{36})\s{2,}(?<pw>\S+)\s*$'
foreach ($ln in $lines) {
  $m = [regex]::Match($ln, $tableRe)
  if ($m.Success) {
    Add-Rec $m.Groups['name'].Value $m.Groups['phone'].Value $m.Groups['emp'].Value $m.Groups['uid'].Value $m.Groups['pw'].Value
  }
}

# --- Pass 2: "PROVISIONED" boxes ---
$cur = $null
foreach ($ln in $lines) {
  if ($ln -match 'PROVISIONED:\s*(?<name>.+?)\s*\(') {
    if ($cur) { Add-Rec $cur.Name $cur.Phone $cur.Emp $cur.Uid $cur.Pw }
    $cur = [pscustomobject]@{ Name = $Matches['name']; Phone = ''; Emp = ''; Uid = ''; Pw = '' }
    continue
  }
  if ($null -eq $cur) { continue }
  if ($ln -match 'Phone \(login\):\s*(?<v>\S+)')  { $cur.Phone = $Matches['v']; continue }
  if ($ln -match 'Employee ID:\s*(?<v>\S+)')      { $cur.Emp   = $Matches['v']; continue }
  if ($ln -match 'Auth user ID:\s*(?<v>\S+)')     { $cur.Uid   = $Matches['v']; continue }
  if ($ln -match 'Temp password:\s*(?<v>\S+)')    { $cur.Pw    = $Matches['v']; continue }
}
if ($cur) { Add-Rec $cur.Name $cur.Phone $cur.Emp $cur.Uid $cur.Pw }

if ($records.Count -eq 0) {
  throw "Parsed 0 credential rows. Check that the capture includes the SUCCESS table and/or PROVISIONED boxes."
}

# --- Write TSV ---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("Name`tPhone`tEmpID`tUserID`tTempPassword")
foreach ($r in $records) {
  [void]$sb.AppendLine(("{0}`t{1}`t{2}`t{3}`t{4}" -f $r.Name, $r.Phone, $r.EmpID, $r.UserID, $r.TempPassword))
}
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutTsv, $sb.ToString(), $enc)
try { & icacls $OutTsv /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null } catch {}

Write-Host "Parsed $($records.Count) credential rows -> $OutTsv"
$phones = $records | ForEach-Object { $_.Phone }
$dupes  = $phones | Group-Object | Where-Object { $_.Count -gt 1 }
if ($dupes) { Write-Host "WARNING: duplicate phones in capture: $(($dupes.Name) -join ', ')" }

# --- Chain into the handout builder ---
if (-not $NoBuild) {
  $builder = Join-Path $PSScriptRoot 'build_cred_handouts.ps1'
  if (Test-Path $builder) {
    Write-Host "Building handouts..."
    & $builder -Tsv $OutTsv
  } else {
    Write-Host "build_cred_handouts.ps1 not found next to this script; TSV written, run the builder manually."
  }
}

Write-Host ""
Write-Host "When distribution is done: SHRED $OutTsv, the raw capture, and the *_handouts folder."
