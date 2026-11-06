<# One-command Kubernetes setup. Node is cached for this account, without a global install. #>
param([string[]]$InstallerArguments = @())
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$NodeVersion = '24.21.0'
$SwarmVersion = '0.7.1'
if ($env:OS -ne 'Windows_NT') { throw 'Use the Linux Kubernetes installation command on Linux.' }
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npx.cmd -ErrorAction SilentlyContinue)) {
    & node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=12)?0:1)'
    if ($LASTEXITCODE -eq 0) {
        & npx.cmd --yes "oswarm@$SwarmVersion" kubernetes @InstallerArguments
        if ($LASTEXITCODE -ne 0) { throw 'Swarm setup did not finish. Complete any prompts and run the same command again.' }
        return
    }
}
$architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($architecture -ne 'AMD64') { throw 'This Kubernetes setup command currently supports Windows x64.' }
$cache = Join-Path $env:LOCALAPPDATA 'Open Swarm\InstallerRuntime'
if ((Test-Path $cache) -and ((Get-Item $cache).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Installer runtime folder must not be a link.' }
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $cache /inheritance:r /grant:r "${me}:(OI)(CI)F" /grant:r 'SYSTEM:(OI)(CI)F' *> $null
if ($LASTEXITCODE -ne 0) { throw 'Could not make the installer runtime folder private.' }
$runtime = Join-Path $cache "node-v$NodeVersion-win-x64"
if ((Test-Path $runtime) -and ((Get-Item $runtime).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Node runtime folder must not be a link.' }
$node = Join-Path $runtime 'node.exe'
$npx = Join-Path $runtime 'node_modules\npm\bin\npx-cli.js'
if (-not ((Test-Path $node) -and (Test-Path $npx))) {
    if (Test-Path $runtime) { throw 'Cached installer runtime is incomplete. Remove that runtime folder and run this command again.' }
    $stage = Join-Path $cache ('.node-download-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        Write-Host 'Preparing the verified Node runtime for Swarm setup…'
        $archive = Join-Path $stage 'node.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip" -OutFile $archive
        if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne '158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541') { throw 'Node download checksum mismatch; nothing was installed.' }
        Expand-Archive -Path $archive -DestinationPath $stage
        Move-Item (Join-Path $stage "node-v$NodeVersion-win-x64") $runtime
    } finally { Remove-Item -Recurse -Force $stage }
}
if ((& $node --version) -ne "v$NodeVersion") { throw 'The cached Node runtime did not report the expected version.' }
$previousPath = $env:Path
try {
    $env:Path = "$runtime;$previousPath"
    & $node $npx --yes "oswarm@$SwarmVersion" kubernetes @InstallerArguments
    if ($LASTEXITCODE -ne 0) { throw 'Swarm setup did not finish. Complete any prompts and run the same command again.' }
} finally { $env:Path = $previousPath }
