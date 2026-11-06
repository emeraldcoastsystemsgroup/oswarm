# Focused real PowerShell execution of the release image admission; Docker and the network are fixtures.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../install/install.ps1'))
$source = $source.Substring(0, $source.LastIndexOf("`nif (`$Action -eq 'prepare')"))
$env:OSWARM_DIR = Join-Path ([IO.Path]::GetTempPath()) ('unused-swarm-fixture-' + [guid]::NewGuid().ToString('N'))
Invoke-Expression $source
$script:FixtureRevision = 'a' * 40
$script:FixtureImage = $ImageDefault
$script:Pulled = $false
$script:PullCount = 0
$script:SeenRevision = $script:FixtureRevision
$script:ArchiveCalls = 0
function Set-Lock([string]$Format, [string]$Image) {
    $script:FixtureManifest = "FORMAT=$Format`nVERSION=$Version`nIMAGE=$Image`nREVISION=$script:FixtureRevision`nAMD64_MANIFEST=sha256:$('d' * 64)`nARM64_MANIFEST=sha256:$('e' * 64)`n"
}
function Invoke-WebRequest {
    param([switch]$UseBasicParsing,[string]$Uri,[string]$OutFile)
    if ($Uri.EndsWith('image-release.env')) { [IO.File]::WriteAllText($OutFile,$script:FixtureManifest) }
    else { $script:ArchiveCalls++; throw 'Unexpected download' }
}
function docker {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'info') { return 'x86_64' }
    if ($args[0] -eq 'pull') {
        $script:PullCount++
        if ($args[1] -ne $script:FixtureImage) { throw "pulled $($args[1]) instead of the pinned image" }
        $script:Pulled = $true; return
    }
    if ($args[0] -eq 'load' -or $args[0] -eq 'tag') { $script:ArchiveCalls++; return }
    if ($args[0] -eq 'image') {
        if (-not $script:Pulled) { $global:LASTEXITCODE = 1; return }
        return ConvertTo-Json -Compress -Depth 5 -InputObject @(@{ Architecture='amd64'; Config=@{ Labels=@{ 'org.opencontainers.image.revision'=$script:SeenRevision } } })
    }
    throw 'Unexpected Docker fixture operation'
}
function Assert-Refused([string]$Pattern) {
    $refused = $false
    try { Initialize-ReleaseImage } catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; $refused = $true }
    if (-not $refused) { throw "expected a refusal matching $Pattern" }
}
# PSScriptRoot points at scripts/, so the installer downloads the lock (the fixture above).
Set-Lock '1' 'oshal-kernel:swarm-0.7.0'
Assert-Refused 'unsupported image release format'
Set-Lock '2' ('ghcr.io/emeraldcoastsystemsgroup/oswarm:9.9.9@sha256:' + ('c' * 64))
Assert-Refused 'name different images'
if ($script:PullCount -ne 0) { throw 'A refused lock reached docker pull' }
Set-Lock '2' $script:FixtureImage
$script:SeenRevision = 'f' * 40
Assert-Refused 'source revision does not match'
if ($script:PullCount -ne 1) { throw 'The pinned image was not pulled exactly once' }
$script:SeenRevision = $script:FixtureRevision
$script:Image = ''
Initialize-ReleaseImage
if ($script:PullCount -ne 1) { throw 'A present image was pulled again' }
if ($script:Image -ne $script:FixtureImage) { throw 'The admitted image is not the pinned reference' }
if ($script:ArchiveCalls -ne 0) { throw 'An archive download, load or retag was attempted' }
Write-Host 'PASS: PowerShell refuses the archive lock and a foreign image, pulls the pinned digest once, and admits it only with the pinned revision.'
