<#
CHANGE LOG
-----------------------------------------------------------------------------
SEQ                 | AUTHOR                      | DESCRIPTION
-----------------------------------------------------------------------------
1 | maintainer@emeraldcoastsystemsgroup.com   | Initial implementation
2 | maintainer@emeraldcoastsystemsgroup.com   | Harden piped strict-mode defaults, atomic install state, credential recovery, upgrade .env rewrite, public URL port sync, and owner-apps parity
3 | maintainer@emeraldcoastsystemsgroup.com   | Validate OSWARM_ENGINE_MIRROR upfront, write tokenized .installing before config files, refuse colliding Compose projects, and self-root copied oswarm.ps1

oswarm: one command installs the dependencies and the product, on Windows.

    irm https://oswarm.ai/install.ps1 | iex

What it does, in order, and skips whatever is already in place:
  1. Docker Desktop with the WSL 2 engine. WSL is enabled with `wsl --install` when it is
     missing (Windows then needs one restart; run the command again afterwards). Docker Desktop
     is installed with winget and started; its first start shows a terms window to accept.
  2. The product: the kernel image, PostgreSQL, the administrator's first password, the kernel
     itself, and the public application catalog, staged at a reviewed commit.
  3. Prints the sign-in URL, the administrator name and the generated password, and opens the
     browser.

Settings are environment variables (the script is usually piped, so there is no prompt):
  OSWARM_DIR=%USERPROFILE%\oswarm   installation directory     OSWARM_ADMIN=admin
  OSWARM_PORT=38788                 local port                 OSWARM_ADMIN_PASSWORD=...
  OSWARM_PROJECT=oswarm             Docker Compose project     OSWARM_NO_BROWSER=1
  OSWARM_IMAGE=...                  kernel image reference
  OSWARM_PUBLIC_URL=...             public URL (defaults to http://127.0.0.1:$OSWARM_PORT)
  OSWARM_CATALOG_COMMIT=...         application catalog commit
  OSWARM_OWNER_APPLICATIONS=...     engineering owner setup on first install
  OSWARM_BUNDLE_URL=...             where compose.yaml and the policy files come from

Day to day, with the copy the installer leaves in the installation directory:
  & "$env:USERPROFILE\oswarm\oswarm.ps1" status | start | stop | restart | logs | upgrade | uninstall [-Purge]

Re-running the installer on an existing installation starts it and stages the catalog if that
was never done; it never resets a password and never deletes data.
#>
[CmdletBinding()]
param(
    [ValidateSet('install','prepare','status','start','stop','restart','logs','upgrade','uninstall')][string]$Action = 'install',
    [string]$Dir = $(if ($env:OSWARM_DIR) { $env:OSWARM_DIR } elseif ((Test-Path Variable:\PSCommandPath) -and $PSCommandPath -and ([IO.Path]::GetFileName($PSCommandPath) -ieq 'oswarm.ps1')) { [IO.Path]::GetDirectoryName($PSCommandPath) } elseif ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'oswarm' } elseif (Test-Path Variable:\HOME) { Join-Path $HOME 'oswarm' } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'oswarm' }),
    [string]$Admin = $(if ($env:OSWARM_ADMIN) { $env:OSWARM_ADMIN } else { 'admin' }),
    [int]$Port = $(if ($env:OSWARM_PORT) { [int]$env:OSWARM_PORT } else { 38788 }),
    [string]$Project = $(if ($env:OSWARM_PROJECT) { $env:OSWARM_PROJECT } else { 'oswarm' }),
    [string]$Image = $(if ($env:OSWARM_IMAGE) { $env:OSWARM_IMAGE } else { '' }),
    [string]$OwnerApps = $(if ($env:OSWARM_OWNER_APPLICATIONS) { $env:OSWARM_OWNER_APPLICATIONS } else { '' }),
    [switch]$Purge
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '0.7.1'
$ImageDefault = "ghcr.io/emeraldcoastsystemsgroup/oswarm:$Version@sha256:1731a07d146774cb764a839cabf2dde20136d68c8fb67f292dbc9ecadf4febc4"
$CatalogRepo = 'https://github.com/emeraldcoastsystemsgroup/oshal-apps'
$CatalogCommit = if ($env:OSWARM_CATALOG_COMMIT) { $env:OSWARM_CATALOG_COMMIT } else { '3a0e0764f143472ac3f181bd0f98127cc23dd90b' }
$BundleUrl = if ($env:OSWARM_BUNDLE_URL) { $env:OSWARM_BUNDLE_URL } else { 'https://oswarm.ai/install' }
$InstallerUrl = if ($env:OSWARM_INSTALLER_URL) { $env:OSWARM_INSTALLER_URL } else { 'https://oswarm.ai/install.ps1' }
$InstallingToken = 'oswarm-incomplete-install-v1'
$ScriptRoot = if (Test-Path Variable:\PSScriptRoot) { $PSScriptRoot } else { '' }
$PortSet = $PSBoundParameters.ContainsKey('Port') -or [bool]$env:OSWARM_PORT
$ProjectSet = $PSBoundParameters.ContainsKey('Project') -or [bool]$env:OSWARM_PROJECT
$ImageSet = [bool]$Image
if (-not $Image) { $Image = $ImageDefault }
$script:GeneratedPassword = ''
$script:InitialOwnerPassword = ''
$script:InitialOwnerInitialized = $false
$script:CredentialsShown = $false
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Say([string]$Text) { Write-Host ''; Write-Host "== $Text" }
function Note([string]$Text) { Write-Host "   $Text" }
function Show-InitialCredentials {
    if ($script:InitialOwnerInitialized -and $script:GeneratedPassword -and -not $script:CredentialsShown) {
        Write-Host ''
        Write-Host "Administrator:   $Admin"
        Write-Host "Password:        $($script:GeneratedPassword)"
        Write-Host '                 (generated and shown once; save it even if application setup failed.)'
        $script:CredentialsShown = $true
    }
}
function Fail([string]$Text) { Show-InitialCredentials; throw "oswarm: $Text" }
function Invoke-Docker([string[]]$Arguments) {
    $output = & docker @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "docker $($Arguments -join ' ') failed: $output" }
    return $output
}
function Invoke-Compose([string[]]$Arguments, [string]$ProjectName = $Project) {
    $composeFile = Join-Path $Dir 'compose.yaml'
    $hadPrev = Test-Path Env:\OSWARM_PROJECT
    $prev = if ($hadPrev) { $env:OSWARM_PROJECT } else { '' }
    try {
        $env:OSWARM_PROJECT = $ProjectName
        & docker compose --project-directory $Dir -f $composeFile @Arguments
        if ($LASTEXITCODE -ne 0) { Fail "docker compose $($Arguments -join ' ') failed" }
    } finally {
        if ($hadPrev) { $env:OSWARM_PROJECT = $prev } else { Remove-Item Env:\OSWARM_PROJECT -ErrorAction SilentlyContinue }
    }
}
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $Utf8) }

function Get-EnvSetting([string]$Key, [string]$EnvFile = (Join-Path $Dir '.env')) {
    if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) { return '' }
    $found = Select-String -LiteralPath $EnvFile -Pattern ("^{0}=(.*)$" -f [Regex]::Escape($Key)) -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($found) { return $found.Matches[0].Groups[1].Value.Trim() }
    return ''
}

function Read-ExistingEnv {
    if (-not $PortSet) {
        $savedPort = Get-EnvSetting 'OSWARM_PORT'
        if ($savedPort -match '^\d+$') { $script:Port = [int]$savedPort }
    }
    if (-not $ProjectSet) {
        $savedProject = Get-EnvSetting 'OSWARM_PROJECT'
        if (-not $savedProject) { $savedProject = Get-EnvSetting 'COMPOSE_PROJECT_NAME' }
        if ($savedProject) { $script:Project = $savedProject }
    }
}

function Confirm-Inputs {
    if ($Admin -notmatch '^[A-Za-z0-9._-]{1,64}$') { Fail 'the administrator name must be 1-64 letters, digits, dot, underscore or dash' }
    if ($Project -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$') { Fail 'the project name must be 1-63 letters, digits, underscore or dash' }
    if ($Port -lt 1 -or $Port -gt 65535) { Fail 'the port must be between 1 and 65535' }
    if ($CatalogCommit -notmatch '^[0-9a-f]{40}$') { Fail 'OSWARM_CATALOG_COMMIT must be a full 40-character commit' }
    if ($env:OSWARM_ENGINE_MIRROR) {
        if ($env:OSWARM_ENGINE_MIRROR -match '[\x00-\x1F\x7F]' -or $env:OSWARM_ENGINE_MIRROR -notmatch '^\{.*\}$') {
            Fail 'OSWARM_ENGINE_MIRROR must be a single-line JSON object'
        }
        try {
            $parsedMirror = $env:OSWARM_ENGINE_MIRROR | ConvertFrom-Json
            if ($null -eq $parsedMirror -or $parsedMirror -is [array] -or $parsedMirror -is [string] -or $parsedMirror -is [ValueType]) { throw 'not-object' }
        } catch { Fail 'OSWARM_ENGINE_MIRROR must be a single-line JSON object' }
    }
    if ($OwnerApps) {
        if ($OwnerApps -match '(^,|,,|,$)') { Fail 'owner-apps contains an empty application' }
        $allowed = @('engineering','design-studio','cad-studio','circuit-lab','embodied','aero-lab','scan-to-print')
        foreach ($item in ($OwnerApps -split ',')) {
            if ($allowed -notcontains $item) { Fail "unknown engineering owner application $item" }
        }
    }
}

# ----- 1. Docker Desktop ---------------------------------------------------------------------

function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    $type = (& docker info --format '{{.OSType}}' 2>$null)
    return ($LASTEXITCODE -eq 0 -and "$type".Trim() -eq 'linux')
}

function Wait-Docker {
    for ($i = 0; $i -lt 150; $i++) { if (Test-Docker) { return }; Start-Sleep -Seconds 2 }
    Fail 'Docker Desktop did not start within five minutes; start it, accept its terms, then run this installer again'
}

function Install-DockerDesktop {
    Say 'installing Docker Desktop'
    $wslReady = $false
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $null = & wsl --status 2>&1
        $wslReady = ($LASTEXITCODE -eq 0)
    }
    if (-not $wslReady) {
        Note 'enabling Windows Subsystem for Linux (Windows will ask for permission)'
        & wsl --install --no-distribution
        Write-Host ''
        Write-Host 'WSL is enabled. Restart Windows, then run the same command again to continue.'
        exit 0
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Fail 'winget is not available; install Docker Desktop from https://docs.docker.com/desktop/setup/install/windows-install/ and run this again' }
    & winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Fail 'winget could not install Docker Desktop' }
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

function Start-DockerDesktop {
    $exe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $exe) { Start-Process $exe | Out-Null } else { Fail 'Docker Desktop is installed but its program was not found; start it by hand and run this again' }
    Note 'Docker Desktop is starting; accept its terms in the window it opens. Waiting for the engine.'
}

function Confirm-Docker {
    Say 'checking Docker'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Install-DockerDesktop }
    if (-not (Test-Docker)) { Start-DockerDesktop; Wait-Docker }
    & docker compose version *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'Docker Compose v2 is missing (docker compose version failed); update Docker Desktop' }
    Note "Docker $((& docker version --format '{{.Server.Version}}' 2>$null)) with Compose $((& docker compose version --short 2>$null))"
}

# ----- 2. The product ------------------------------------------------------------------------

function Get-Bundle([string]$Destination = $Dir) {
    $here = if ($ScriptRoot -and (Test-Path (Join-Path $ScriptRoot 'docker/compose.yaml'))) { Join-Path $ScriptRoot 'docker' } else { '' }
    $files = @('compose.yaml','seccomp-bwrap.json','env.example','image-release.env','image-loader.sh')
    if ($OwnerApps) { $files += 'owner-applications.cjs' }
    foreach ($name in $files) {
        $target = Join-Path $Destination $name
        if ($here) {
            $source = if ($name -eq 'env.example') { Join-Path $here '.env.example' } else { Join-Path $here $name }
            Copy-Item $source $target
        } else {
            try { Invoke-WebRequest -UseBasicParsing -Uri "$BundleUrl/$name" -OutFile $target }
            catch { Fail "could not download $BundleUrl/$name" }
        }
    }
    $copy = Join-Path $Destination 'oswarm.ps1'
    if ($here) { Copy-Item (Join-Path $ScriptRoot 'install.ps1') $copy }
    else {
        try { Invoke-WebRequest -UseBasicParsing -Uri $InstallerUrl -OutFile $copy }
        catch { Fail "could not download $InstallerUrl" }
    }
}

function Initialize-ReleaseImage([switch]$Upgrade, [string]$LockDirectory = '') {
    $temporary = ''
    if (-not $LockDirectory) {
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('oswarm-server-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temporary | Out-Null
        $LockDirectory = $temporary
    }
    try {
        $file = Join-Path $LockDirectory 'image-release.env'
        if (-not (Test-Path $file)) {
            $local = if ($ScriptRoot) { Join-Path $ScriptRoot 'docker/image-release.env' } else { '' }
            if ($local -and (Test-Path $local)) { Copy-Item $local $file }
            else { Invoke-WebRequest -UseBasicParsing -Uri "$BundleUrl/image-release.env" -OutFile $file }
        }
        $release = @{}
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if (-not $line -or $line.StartsWith('#')) { continue }
            if ($line -notmatch '^([A-Z0-9_]+)=(.*)$') { Fail 'invalid image release lock' }
            $key = $Matches[1]; $value = $Matches[2]
            if ($release.ContainsKey($key)) { Fail 'duplicate image release entry' }
            $release[$key] = $value
        }
        if ($release['FORMAT'] -ne '2') { Fail 'unsupported image release format; download the current installer' }
        if ($release['IMAGE'] -notmatch '^ghcr\.io/emeraldcoastsystemsgroup/oswarm:[0-9A-Za-z._-]+@sha256:[a-f0-9]{64}$' -or $release['REVISION'] -notmatch '^[a-f0-9]{40}$') { Fail 'invalid image release identity' }
        if (-not $Upgrade -and $release['IMAGE'] -ne $ImageDefault) { Fail 'this installer and its image release lock name different images; download the current installer' }
        $architecture = (Invoke-Docker @('info','--format','{{.Architecture}}') | Out-String).Trim()
        $expected = switch ($architecture) { 'x86_64' { 'amd64' } 'amd64' { 'amd64' } 'aarch64' { 'arm64' } 'arm64' { 'arm64' } default { Fail "unsupported Docker architecture $architecture" } }
        $reference = $release['IMAGE']
        & docker image inspect $reference *> $null
        if ($LASTEXITCODE -ne 0) {
            Say 'downloading the Swarm server image (pinned by digest)'
            & docker pull $reference
            if ($LASTEXITCODE -ne 0) { Fail "could not download the server image $reference; check the connection and run the same install command again" }
        }
        $record = ((Invoke-Docker @('image','inspect',$reference) | Out-String) | ConvertFrom-Json)[0]
        if ($record.Architecture -ne $expected -or $record.Config.Labels.'org.opencontainers.image.revision' -ne $release['REVISION']) { Fail "the server image's architecture or source revision does not match this release" }
        $script:Image = $reference
    } finally {
        if ($temporary) { Remove-Item -Recurse -Force $temporary -ErrorAction SilentlyContinue }
    }
}

function New-RandomBytes([int]$Count) {
    $bytes = New-Object byte[] $Count
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
    return ,$bytes
}
function New-Hex { $bytes = New-RandomBytes 32; ($bytes | ForEach-Object { $_.ToString('x2') }) -join '' }

function New-Password {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $bytes = New-RandomBytes 24
    -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

function Protect-Directory([string]$Path) {
    # Only this account reads the installation directory (it holds the database password and the vault key).
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls $Path /inheritance:r /grant:r "${me}:(OI)(CI)F" /grant:r 'SYSTEM:(OI)(CI)F' *> $null
}

# The kernel runs each application's engine inside its own container, so its ceilings come from this
# machine (under Docker Desktop, from the VM Docker Desktop gave it), not from a figure for the kernel alone.
function Get-HostLimits {
    $cpus = 2; $total = 4294967296
    $answer = (& docker info --format '{{.NCPU}} {{.MemTotal}}' 2>$null)
    if ($answer -match '^(\d+) (\d+)$') { $cpus = [int]$Matches[1]; $total = [long]$Matches[2] }
    $memory = [Math]::Max(2048, [long]($total / 1048576) - 1024)
    return "OSWARM_KERNEL_CPUS=$cpus`nOSWARM_KERNEL_MEMORY=${memory}m`n"
}

function Test-RegularFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return -not [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Test-IncompleteInstall {
    $marker = Join-Path $Dir '.installing'
    $composeFile = Join-Path $Dir 'compose.yaml'
    if (-not (Test-RegularFile $marker) -or -not (Test-RegularFile $composeFile)) { return $false }
    return ([IO.File]::ReadAllText($marker).Trim() -eq $InstallingToken)
}

function Remove-IncompleteInstall {
    Note "cleaning up an incomplete earlier installation in $Dir"
    $savedProject = Get-EnvSetting 'OSWARM_PROJECT'
    if (-not $savedProject) { $savedProject = Get-EnvSetting 'COMPOSE_PROJECT_NAME' }
    if (-not $savedProject) { $savedProject = $Project }
    $realDir = [IO.Path]::GetFullPath($Dir)
    $foreignOwner = ''
    $ids = (& docker ps -a -q --filter "label=com.docker.compose.project=$savedProject" 2>$null | Out-String).Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($cid in $ids) {
        $wdir = (& docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' $cid 2>$null | Out-String).Trim()
        if ($wdir -and ([IO.Path]::GetFullPath($wdir) -ne $realDir)) { $foreignOwner = $wdir; break }
    }
    if (-not $foreignOwner) {
        try { Invoke-Compose -Arguments @('down','--volumes','--remove-orphans') -ProjectName $savedProject } catch { }
    }
    Remove-Item -Recurse -Force $Dir -ErrorAction SilentlyContinue
}

function Confirm-ProjectFree {
    $containers = (& docker ps -a -q --filter "label=com.docker.compose.project=$Project" 2>$null | Out-String).Trim()
    $volumes = (& docker volume ls -q --filter "label=com.docker.compose.project=$Project" 2>$null | Out-String).Trim()
    if ($containers -or $volumes) {
        Fail "Docker Compose project '$Project' already has containers or volumes on this machine; set OSWARM_PROJECT (or pass -Project) to a distinct project name for a second installation"
    }
}

function Write-Configuration([string]$StagedBundle = '') {
    Confirm-Inputs
    Say "creating $Dir"
    New-Item -ItemType Directory -Path $Dir | Out-Null
    if ($env:OS -eq 'Windows_NT') { Protect-Directory $Dir }
    New-Item -ItemType Directory -Path (Join-Path $Dir 'applications') | Out-Null
    $installingMarker = Join-Path $Dir '.installing'
    Write-Utf8 $installingMarker "$InstallingToken`n"
    if ($env:OS -ne 'Windows_NT') { & chmod 600 $installingMarker; & chmod 755 $Dir; & chmod 755 (Join-Path $Dir 'applications') }
    if ($StagedBundle) { Get-ChildItem -Force $StagedBundle | Copy-Item -Destination $Dir -Recurse } else { Get-Bundle $Dir }
    $publicUrl = if ($env:OSWARM_PUBLIC_URL) { $env:OSWARM_PUBLIC_URL } else { "http://127.0.0.1:$Port" }
    $settings = (Get-Content (Join-Path $Dir 'env.example') -Raw) + "`n# written by the installer`nOSWARM_PORT=$Port`nOSWARM_PUBLIC_URL=$publicUrl`nOSWARM_IMAGE=$Image`nOSWARM_PROJECT=$Project`n" + (Get-HostLimits)
    Write-Utf8 (Join-Path $Dir '.env') $settings
    Remove-Item (Join-Path $Dir 'env.example')
    $dbpass = New-Hex
    Write-Utf8 (Join-Path $Dir 'postgres.env') "POSTGRES_USER=postgres`nPOSTGRES_DB=oshal`nPOSTGRES_PASSWORD=$dbpass`n"
    $runtimeText = "OSHAL_ADMIN_SUBJECT=$Admin`nOSHAL_ADMIN_TOKEN=$(New-Hex)`nOSHAL_VAULT_KEY=$(New-Hex)`nOSHAL_POSTGRES=postgresql://postgres:$dbpass@postgres:5432/oshal`n"
    if ($env:OSWARM_ENGINE_MIRROR) { $runtimeText += "OSHAL_ENGINE_MIRROR=$($env:OSWARM_ENGINE_MIRROR)`n" }
    Write-Utf8 (Join-Path $Dir 'runtime.env') $runtimeText
    if ($env:OS -ne 'Windows_NT') { & chmod 600 (Join-Path $Dir '.env') (Join-Path $Dir 'postgres.env') (Join-Path $Dir 'runtime.env') }
}

function Wait-Ready {
    for ($i = 0; $i -lt 90; $i++) {
        try { Invoke-RestMethod -Uri "http://127.0.0.1:$Port/readyz" -TimeoutSec 2 | Out-Null; return } catch { }
        Start-Sleep -Seconds 2
    }
    Fail "the kernel did not become ready at http://127.0.0.1:$Port/readyz; inspect: oswarm.ps1 logs"
}

function Test-PortFree { $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port); try { $listener.Start(); $true } catch { $false } finally { $listener.Stop() } }

function Install-Product {
    Confirm-Inputs
    if (-not (Test-PortFree)) { Fail "port $Port is already in use on this machine; set OSWARM_PORT to another port" }
    Confirm-ProjectFree
    $password = if ($env:OSWARM_ADMIN_PASSWORD) { $env:OSWARM_ADMIN_PASSWORD } else { $script:GeneratedPassword = New-Password; $script:GeneratedPassword }
    if ($password -match '[\x00-\x1F\x7F]') { Fail 'the password may not contain control characters' }
    $bytes = [Text.Encoding]::UTF8.GetByteCount($password)
    if ($bytes -lt 12 -or $bytes -gt 1024) { Fail 'OSWARM_ADMIN_PASSWORD must be 12 to 1024 UTF-8 bytes' }
    $bundleStage = Join-Path ([IO.Path]::GetTempPath()) ('oswarm-bundle-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $bundleStage | Out-Null
    try {
        Get-Bundle $bundleStage
        if (-not $ImageSet) { Initialize-ReleaseImage -LockDirectory $bundleStage }
        Write-Configuration $bundleStage
    } finally { Remove-Item -Recurse -Force $bundleStage -ErrorAction SilentlyContinue }
    Say 'downloading the kernel image and PostgreSQL'
    & docker image inspect $Image *> $null
    if ($LASTEXITCODE -eq 0) { Note "$Image is already present"; Invoke-Compose @('pull','--quiet','postgres') } else { Invoke-Compose @('pull','--quiet') }
    Say 'starting PostgreSQL'
    Invoke-Compose @('up','-d','--wait','--wait-timeout','120','postgres')
    Say "setting the administrator's first password"
    $json = @{ username = $Admin; password = $password } | ConvertTo-Json -Compress
    $previous = [Console]::OutputEncoding; $previousOut = $OutputEncoding
    $hadPrevProj = Test-Path Env:\OSWARM_PROJECT
    $prevProj = if ($hadPrevProj) { $env:OSWARM_PROJECT } else { '' }
    try {
        [Console]::OutputEncoding = $Utf8; $OutputEncoding = $Utf8
        $env:OSWARM_PROJECT = $Project
        $composeFile = Join-Path $Dir 'compose.yaml'
        $json | & docker compose --project-directory $Dir -f $composeFile run --rm -T --no-deps kernel init-password
        if ($LASTEXITCODE -ne 0) { Fail 'administrator initialization failed; the installation directory was kept for inspection' }
    } finally {
        [Console]::OutputEncoding = $previous; $OutputEncoding = $previousOut; $json = $null
        if ($hadPrevProj) { $env:OSWARM_PROJECT = $prevProj } else { Remove-Item Env:\OSWARM_PROJECT -ErrorAction SilentlyContinue }
    }
    $script:InitialOwnerInitialized = $true
    $script:InitialOwnerPassword = $password
    $password = $null
    Write-Utf8 (Join-Path $Dir 'installation.json') ((@{ version = 1; admin = $Admin } | ConvertTo-Json -Compress) + "`n")
    if ($env:OS -ne 'Windows_NT') { & chmod 600 (Join-Path $Dir 'installation.json') }
    Remove-Item -Force (Join-Path $Dir '.installing') -ErrorAction SilentlyContinue
    Say 'starting the kernel'
    Invoke-Compose @('up','-d','kernel')
    Wait-Ready
}

function Add-Catalog {
    $destination = Join-Path $Dir 'applications'
    if (@(Get-ChildItem -Force $destination).Count) {
        if ($env:OS -ne 'Windows_NT') { & chmod -R a+rX $destination }
        return
    }
    Say "staging the application catalog ($CatalogRepo at $($CatalogCommit.Substring(0,12)))"
    $stage = Join-Path $Dir ('.catalog-stage-' + (New-Hex).Substring(0,12))
    New-Item -ItemType Directory $stage | Out-Null
    try {
        $archive = Join-Path $stage 'catalog.tar.gz'
        $catalogUrl = if ($env:OSWARM_CATALOG_URL) { $env:OSWARM_CATALOG_URL } else { "https://codeload.github.com/emeraldcoastsystemsgroup/oshal-apps/tar.gz/$CatalogCommit" }
        try { Invoke-WebRequest -UseBasicParsing -Uri $catalogUrl -OutFile $archive }
        catch { Fail "could not download the catalog at $CatalogCommit" }
        $listing = & tar -tzvf $archive
        if ($LASTEXITCODE -ne 0) { Fail 'could not read the catalog archive' }
        if ($listing | Where-Object { $_ -match '^[lh]' }) { Fail 'that catalog revision contains links; refusing' }
        $source = Join-Path $stage 'source'; New-Item -ItemType Directory $source | Out-Null
        & tar -xzf $archive -C $source --strip-components=1
        if ($LASTEXITCODE -ne 0) { Fail 'could not extract the catalog' }
        $binding = @{ version = 1; origin = $CatalogRepo; reference = $CatalogCommit; commit = $CatalogCommit; provenance = 'reconstructed-from-origin' }
        Write-Utf8 (Join-Path $source 'native-source-origin.json') (($binding | ConvertTo-Json -Compress) + "`n")
        Get-ChildItem -Force $source | Copy-Item -Destination $destination -Recurse
        if ($env:OS -ne 'Windows_NT') { & chmod -R a+rX $destination }
    } finally { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue }
    Invoke-Compose @('restart','kernel') | Out-Null
    Wait-Ready
    Note 'staged; nothing is activated until you choose applications in the App Loader'
}

function Set-InitialOwner {
    if (-not $OwnerApps) { $script:InitialOwnerPassword = ''; return }
    if (-not $script:InitialOwnerPassword) {
        Note 'existing installation: owner assignments are unchanged; owner-apps applies only to first installation'
        return
    }
    Say 'setting up the engineering applications selected by the first owner'
    $payload = @{ username = $Admin; password = $script:InitialOwnerPassword; applications = $OwnerApps } | ConvertTo-Json -Compress
    $helper = Get-Content (Join-Path $Dir 'owner-applications.cjs') -Raw
    $composeFile = Join-Path $Dir 'compose.yaml'
    $previous = [Console]::OutputEncoding; $previousOut = $OutputEncoding
    $hadPrevProj = Test-Path Env:\OSWARM_PROJECT
    $prevProj = if ($hadPrevProj) { $env:OSWARM_PROJECT } else { '' }
    try {
        [Console]::OutputEncoding = $Utf8; $OutputEncoding = $Utf8
        $env:OSWARM_PROJECT = $Project
        $payload | & docker compose --project-directory $Dir -f $composeFile exec -T kernel node -e "$helper; main().catch(e => { console.error(e.message); process.exitCode = 1; });"
        if ($LASTEXITCODE -ne 0) { Fail 'selected owner setup failed; inspect the assignment reason, then use the App Loader (passwords were not reset)' }
    } finally {
        [Console]::OutputEncoding = $previous; $OutputEncoding = $previousOut; $payload = $null; $script:InitialOwnerPassword = ''
        if ($hadPrevProj) { $env:OSWARM_PROJECT = $prevProj } else { Remove-Item Env:\OSWARM_PROJECT -ErrorAction SilentlyContinue }
    }
}

function Show-Summary {
    $version = try { (Invoke-RestMethod -Uri "http://127.0.0.1:$Port/version" -TimeoutSec 2) | ConvertTo-Json -Compress } catch { 'unknown' }
    Say 'oswarm is ready'
    Write-Host "Open:            http://127.0.0.1:$Port/login"
    if ($script:GeneratedPassword) { Show-InitialCredentials }
    else { Write-Host "Administrator:   $Admin" }
    Write-Host "Installation:    $Dir"
    Write-Host "Kernel:          $version"
    Write-Host ''
    Write-Host 'Next: sign in, open Connections and add your AI provider (the installed default answers'
    Write-Host 'nothing), then open the App Loader and install the applications you want.'
    Write-Host "Later: & `"$Dir\oswarm.ps1`" status | start | stop | restart | logs | upgrade | uninstall"
    if (-not $env:OSWARM_NO_BROWSER) { try { Start-Process "http://127.0.0.1:$Port/login" } catch { } }
}

function Invoke-Install {
    try {
        Confirm-Inputs
        Confirm-Docker
        if (Test-IncompleteInstall) { Remove-IncompleteInstall }
        if ((Test-Path -LiteralPath (Join-Path $Dir 'runtime.env') -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $Dir '.installing'))) {
            Read-ExistingEnv
            Say "$Dir is already an installation; starting it (passwords and data are never reset)"
            Invoke-Compose @('up','-d'); Wait-Ready
        } elseif (Test-Path -LiteralPath $Dir) { Fail "$Dir exists but is not an oswarm installation; choose another OSWARM_DIR" }
        else { Install-Product }
        Add-Catalog
        Set-InitialOwner
        Show-Summary
    } catch {
        Show-InitialCredentials
        throw
    }
}

function Invoke-DayTwo {
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'compose.yaml') -PathType Leaf)) { Fail "$Dir is not an oswarm installation; run the installer first" }
    if (-not (Test-Docker)) { Confirm-Docker | Out-Null }
    Read-ExistingEnv
    switch ($Action) {
        'status' { Invoke-Compose @('ps'); try { Invoke-RestMethod -Uri "http://127.0.0.1:$Port/readyz" -TimeoutSec 2 | ConvertTo-Json -Compress } catch { Write-Host 'not ready' } }
        'start' { Invoke-Compose @('up','-d'); Wait-Ready; Write-Host "ready: http://127.0.0.1:$Port/login" }
        'stop' { Invoke-Compose @('stop') }
        'restart' { Invoke-Compose @('restart'); Wait-Ready; Write-Host "ready: http://127.0.0.1:$Port/login" }
        'logs' { Invoke-Compose @('logs','--tail','200','kernel') }
        'upgrade' {
            if (-not $ImageSet) { Get-Bundle $Dir; Initialize-ReleaseImage -Upgrade -LockDirectory $Dir; $script:ImageSet = $true }
            $envPath = Join-Path $Dir '.env'
            if ($ImageSet) {
                $kept = @((Get-Content $envPath) | Where-Object { $_ -notmatch '^OSWARM_IMAGE=' })
                Write-Utf8 $envPath ((@($kept + "OSWARM_IMAGE=$Image") -join "`n") + "`n")
            }
            if ((Get-EnvSetting 'OSWARM_KERNEL_MEMORY' $envPath) -eq '2g') {
                Write-Utf8 $envPath ((Get-Content $envPath -Raw) + (Get-HostLimits))
            }
            if ($env:OS -ne 'Windows_NT') { & chmod 600 $envPath }
            & docker image inspect $Image *> $null
            if ($LASTEXITCODE -eq 0) { Invoke-Compose @('pull','--quiet','postgres') } else { Invoke-Compose @('pull','--quiet') }
            Invoke-Compose @('up','-d'); Wait-Ready
            Write-Host "upgraded: $((Invoke-RestMethod -Uri "http://127.0.0.1:$Port/version" -TimeoutSec 2) | ConvertTo-Json -Compress)"
        }
        'uninstall' {
            if ($Purge) { Say "removing containers, volumes (all data) and $Dir"; Invoke-Compose @('down','--volumes','--remove-orphans'); Remove-Item -Recurse -Force $Dir }
            else { Say "removing containers; keeping volumes and $Dir (add -Purge to delete data)"; Invoke-Compose @('down','--remove-orphans') }
        }
    }
}

if ($Action -eq 'prepare') { Confirm-Docker }
elseif ($Action -eq 'install') { Invoke-Install }
else { Invoke-DayTwo }
