<#
CHANGE LOG
-----------------------------------------------------------------------------
SEQ                 | AUTHOR                      | DESCRIPTION
-----------------------------------------------------------------------------
1 | maintainer@emeraldcoastsystemsgroup.com   | Real PowerShell regression guards for R2, R3, R4, and P1 in install/install.ps1
#>
param([string]$TargetInstaller = (Join-Path $PSScriptRoot '../install/install.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('oswarm-ps-guards-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

function Invoke-IsolatedPs([string]$Body, [hashtable]$ExtraEnv = @{}) {
    $runner = Join-Path $work ('run-' + [guid]::NewGuid().ToString('N') + '.ps1')
    [IO.File]::WriteAllText($runner, $Body, (New-Object System.Text.UTF8Encoding $false))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Process -Id $PID).MainModule.FileName
    $psi.Arguments = "-NoLogo -NoProfile -NonInteractive -File `"$runner`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    foreach ($k in @('OSWARM_DIR','OSWARM_PORT','OSWARM_PROJECT','OSWARM_IMAGE','OSWARM_ENGINE_MIRROR','OSWARM_BUNDLE_URL','OSWARM_INSTALLER_URL')) {
        [void]$psi.EnvironmentVariables.Remove($k)
    }
    foreach ($entry in $ExtraEnv.GetEnumerator()) {
        $psi.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

try {
    $raw = [IO.File]::ReadAllText($TargetInstaller)
    $defsOnly = $raw.Substring(0, $raw.LastIndexOf("`nif (`$Action -eq 'prepare')"))
    $defsFile = Join-Path $work 'defs.ps1'
    [IO.File]::WriteAllText($defsFile, $defsOnly, (New-Object System.Text.UTF8Encoding $false))

    # 1. R2a: Invalid OSWARM_ENGINE_MIRROR refused upfront in Confirm-Inputs before creating Dir
    $r2aDir = Join-Path $work 'r2a-dir'
    $r2a = Invoke-IsolatedPs ". '$defsFile' -Dir '$r2aDir'; Confirm-Inputs" @{ OSWARM_ENGINE_MIRROR = "{`"url_prefix`":`"http://x`"}`t" }
    if ($r2a.Code -eq 0 -or (Test-Path $r2aDir)) { throw "R2a failed: invalid OSWARM_ENGINE_MIRROR was not refused upfront ($($r2a.Stdout) $($r2a.Stderr))" }

    # 2. R2b: Failure inside Write-Configuration after runtime.env leaves valid .installing token so retry runs Install-Product
    $bundleSrc = Join-Path $work 'bundle'
    New-Item -ItemType Directory -Path $bundleSrc | Out-Null
    foreach ($f in 'compose.yaml','seccomp-bwrap.json','image-release.env','image-loader.sh') {
        Copy-Item (Join-Path $repoRoot "install/docker/$f") (Join-Path $bundleSrc $f)
    }
    Copy-Item (Join-Path $repoRoot 'install/docker/.env.example') (Join-Path $bundleSrc 'env.example')
    Copy-Item $TargetInstaller (Join-Path $bundleSrc 'oswarm.ps1')
    $r2bDir = Join-Path $work 'r2b-dir'
    $r2bWrite = Invoke-IsolatedPs @"
. '$defsFile' -Dir '$r2bDir'
function Get-HostLimits { return "OSWARM_KERNEL_CPUS=2``nOSWARM_KERNEL_MEMORY=2048m``n" }
function chmod { if (`$args[0] -eq 600 -and `$args.Count -ge 4) { `$global:LASTEXITCODE = 1; throw 'simulated-mid-write-failure' }; `$global:LASTEXITCODE = 0 }
Write-Configuration '$bundleSrc'
"@
    if (-not (Test-Path (Join-Path $r2bDir 'runtime.env'))) { throw 'R2b fixture did not reach runtime.env before failing' }
    $r2bRetry = Invoke-IsolatedPs @"
. '$defsFile' -Dir '$r2bDir'
function Confirm-Docker { }
function docker { `$global:LASTEXITCODE = 0; return '' }
function Invoke-Compose { }
function Wait-Ready { }
function Install-Product { New-Item -ItemType Directory -Force -Path `$Dir | Out-Null; Write-Host 'RAN_INSTALL_PRODUCT' }
function Add-Catalog { }
function Set-InitialOwner { }
function Show-Summary { }
Invoke-Install
"@
    if ($r2bRetry.Code -ne 0 -or $r2bRetry.Stdout -notmatch 'RAN_INSTALL_PRODUCT') {
        throw "R2b failed: retry did not clean up and re-run Install-Product ($($r2bRetry.Stdout) $($r2bRetry.Stderr))"
    }

    # 3. R3: Colliding Docker Compose project refused before creating Dir
    $r3Dir = Join-Path $work 'r3-second'
    $r3 = Invoke-IsolatedPs @"
. '$defsFile' -Dir '$r3Dir' -Port 38796 -Image 'ghcr.io/emeraldcoastsystemsgroup/oswarm:0.1.0'
function Test-PortFree { return `$true }
function docker { `$global:LASTEXITCODE = 0; if (`$args[0] -eq 'ps') { return 'container123' }; return '' }
Install-Product
"@
    if ($r3.Code -eq 0 -or (Test-Path $r3Dir) -or ($r3.Stderr + $r3.Stdout) -notmatch 'OSWARM_PROJECT') {
        throw "R3 failed: colliding Compose project was not refused cleanly ($($r3.Stdout) $($r3.Stderr))"
    }

    # 4. R4: Foreign directory with notes.txt and empty/wrong .installing is refused without deleting notes.txt
    $r4Dir = Join-Path $work 'r4-mydata'
    New-Item -ItemType Directory -Path $r4Dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $r4Dir 'notes.txt'), 'keep-safe')
    [IO.File]::WriteAllText((Join-Path $r4Dir '.installing'), '')
    $r4 = Invoke-IsolatedPs @"
. '$defsFile' -Dir '$r4Dir'
function Confirm-Docker { }
Invoke-Install
"@
    if ($r4.Code -eq 0 -or -not (Test-Path (Join-Path $r4Dir 'notes.txt'))) {
        throw "R4 failed: foreign .installing directory was not preserved ($($r4.Stdout) $($r4.Stderr))"
    }

    # 5. P1: Copied <dir>/oswarm.ps1 acts on its own folder and saved OSWARM_PROJECT without -Dir or env vars
    $fakeHome = Join-Path $work 'home'
    $fakeBin = Join-Path $work 'bin'
    $firstDir = Join-Path $fakeHome 'oswarm'
    $secondDir = Join-Path $fakeHome 'second'
    $dockerLog = Join-Path $work 'ps-docker.log'
    New-Item -ItemType Directory -Path $fakeBin,$firstDir,$secondDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $firstDir 'compose.yaml'), "name: `${OSWARM_PROJECT:-oswarm}`n")
    [IO.File]::WriteAllText((Join-Path $firstDir '.env'), "OSWARM_PORT=38788`nOSWARM_PROJECT=oswarm`n")
    [IO.File]::WriteAllText((Join-Path $firstDir 'keep.txt'), 'first-alive')
    [IO.File]::WriteAllText((Join-Path $secondDir 'compose.yaml'), "name: `${OSWARM_PROJECT:-oswarm}`n")
    [IO.File]::WriteAllText((Join-Path $secondDir '.env'), "OSWARM_PORT=38796`nOSWARM_PROJECT=second`n")
    $copiedPs1 = Join-Path $secondDir 'oswarm.ps1'
    [IO.File]::WriteAllText($copiedPs1, $raw, (New-Object System.Text.UTF8Encoding $false))
    $fakeDocker = Join-Path $fakeBin 'docker'
    [IO.File]::WriteAllText($fakeDocker, "#!/usr/bin/env bash`nif [ `"`$1`" = `"info`" ]; then echo linux; exit 0; fi`nprintf 'PROJECT=%s ARGS=%s\n' `"`${OSWARM_PROJECT:-unset}`" `"`$*`" >> '$dockerLog'`nexit 0`n")
    & chmod +x $fakeDocker
    $p1 = Invoke-IsolatedPs "& '$copiedPs1' -Action uninstall -Purge" @{
        HOME = $fakeHome
        USERPROFILE = $fakeHome
        PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
    }
    if ($p1.Code -ne 0 -or (Test-Path $secondDir) -or -not (Test-Path (Join-Path $firstDir 'keep.txt'))) {
        throw "P1 failed: copied oswarm.ps1 did not target only its own folder ($($p1.Stdout) $($p1.Stderr))"
    }
    $logged = [IO.File]::ReadAllText($dockerLog)
    if ($logged -notmatch 'PROJECT=second ARGS=compose') {
        throw "P1 failed: copied oswarm.ps1 did not pass saved OSWARM_PROJECT=second ($logged)"
    }

    Write-Host 'PASS: PowerShell R2a, R2b, R3, R4, and P1 guards all passed.'
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
