#Requires -RunAsAdministrator

$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'

Write-Host ""
Write-Host "============================================================================"
Write-Host "[1/3] Fixing corrupted system PATH entries"
Write-Host "============================================================================"
Write-Host ""

$current = (Get-ItemProperty -Path $regPath -Name Path).Path
$entries = $current -split ';' | Where-Object { $_ -ne '' }

$fixed = [System.Collections.Generic.List[string]]::new()
$seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($e in $entries) {
    $clean = $e.Trim()
    if ($clean -eq '') { continue }

    # Repair entries where spaces were stripped (e.g. C:\ProgramFiles\ -> C:\Program Files\)
    if ($clean -match '^C:\\ProgramFiles\\') {
        $repaired = $clean -replace '^C:\\ProgramFiles\\', 'C:\Program Files\'
        Write-Host "  [FIX] $clean  ->  $repaired"
        $clean = $repaired
    }

    if ($seen.Add($clean)) {
        $fixed.Add($clean)
    } else {
        Write-Host "  [DUP] removed duplicate: $clean"
    }
}

$newPath = $fixed -join ';'
Set-ItemProperty -Path $regPath -Name Path -Value $newPath
Write-Host "[OK] System PATH repaired"
Write-Host ""

Write-Host "============================================================================"
Write-Host "[2/3] Ensuring required tool paths are present"
Write-Host "============================================================================"
Write-Host ""

$toAdd = @(
    'C:\Program Files\7-Zip',
    'C:\tools\make381',
    'C:\Program Files\CMake\bin'
)

$current = (Get-ItemProperty -Path $regPath -Name Path).Path
$changed = $false

foreach ($p in $toAdd) {
    $entries = $current -split ';'
    if ($entries -contains $p) {
        Write-Host "  [OK]  already present: $p"
    } else {
        $current += ";$p"
        $changed = $true
        Write-Host "  [ADD] $p"
    }
}

if ($changed) {
    Set-ItemProperty -Path $regPath -Name Path -Value $current
    Write-Host "[OK] PATH updated"
}
Write-Host ""

Write-Host "============================================================================"
Write-Host "[3/3] Verifying tool files on disk"
Write-Host "============================================================================"
Write-Host ""

$tools = @{
    'C:\Program Files\7-Zip\7z.exe'    = '7-Zip'
    'C:\tools\make381\make.exe'         = 'Make 3.81'
}

foreach ($path in $tools.Keys) {
    if (Test-Path $path) {
        Write-Host "  [OK]  $($tools[$path]): $path"
    } else {
        Write-Host "  [FAIL] $($tools[$path]) not found at: $path"
    }
}

# CMake - can be anywhere
$cmakeExe = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmakeExe) {
    Write-Host "  [OK]  CMake: $($cmakeExe.Source)"
} else {
    Write-Host "  [FAIL] CMake not found in PATH"
}

Write-Host ""
Write-Host "============================================================================"
Write-Host "Done - please RESTART your computer to apply PATH changes."
Write-Host "Then run Verify-Setup.bat to confirm all tools are detected."
Write-Host "============================================================================"
Write-Host ""
