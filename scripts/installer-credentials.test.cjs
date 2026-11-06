/**
 * CHANGE LOG
 * -----------------------------------------------------------------------------
 * SEQ                 | AUTHOR                      | DESCRIPTION
 * -----------------------------------------------------------------------------
 * 1 | maintainer@emeraldcoastsystemsgroup.com   | Initial implementation
 * 2 | maintainer@emeraldcoastsystemsgroup.com   | Normalize LF endings and verify Windows NTFS ACLs alongside POSIX modes
 * 3 | maintainer@emeraldcoastsystemsgroup.com   | Run Bash fixtures via script file and dot-source PowerShell definitions
 */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const installer = fs.readFileSync(path.join(__dirname, '../install/install.sh'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/\nparse_arguments "\$@"[\s\S]*$/, '');
const password = 'A'.repeat(24);

function run(body, directory = '/unused-test-directory') {
  const runnerDir = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-cred-script-'));
  try {
    const scriptFile = path.join(runnerDir, 'installer-credential-test.sh');
    fs.writeFileSync(scriptFile, installer + '\n' + body + '\n');
    const bashScript = process.platform === 'win32' ? scriptFile.replace(/\\/g, '/') : scriptFile;
    const bashDir = process.platform === 'win32' ? directory.replace(/\\/g, '/') : directory;
    return spawnSync('bash', [bashScript, bashDir], {
      encoding: 'utf8',
      env: {PATH: process.env.PATH, HOME: process.env.HOME, USER: process.env.USER},
    });
  } finally {
    fs.rmSync(runnerDir, {recursive: true, force: true});
  }
}

function checkWindowsPrivateConfig(directory) {
  const install = path.join(directory, 'install');
  const scriptRoot = path.join(directory, 'bundle-src');
  fs.cpSync(path.join(__dirname, '../install'), scriptRoot, {recursive: true});
  const raw = fs.readFileSync(path.join(scriptRoot, 'install.ps1'), 'utf8').replace(/\r\n/g, '\n');
  const defs = raw.slice(0, raw.lastIndexOf("\nif ($Action -eq 'prepare')"));
  fs.writeFileSync(path.join(scriptRoot, 'defs.ps1'), defs);
  const psScript = path.join(scriptRoot, 'check-acl.ps1');
  fs.writeFileSync(psScript, `
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'defs.ps1') -Dir '${install.replace(/'/g, "''")}'
function Get-HostLimits { return "OSWARM_KERNEL_CPUS=2\`nOSWARM_KERNEL_MEMORY=2048m\`n" }
Write-Configuration
$acl = [System.IO.Directory]::GetAccessControl($Dir)
$rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])
@{
  protected = [bool]$acl.AreAccessRulesProtected
  identities = @($rules | ForEach-Object { $_.IdentityReference.Value })
  hasRuntime = [bool](Test-Path (Join-Path $Dir 'runtime.env'))
  hasApps = [bool](Test-Path (Join-Path $Dir 'applications'))
} | ConvertTo-Json -Compress
`);
  const env = {...process.env};
  delete env.PSModulePath;
  const out = spawnSync('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', psScript], {encoding: 'utf8', env});
  assert.equal(out.status, 0, out.stderr);
  const parsed = JSON.parse(out.stdout.trim().split(/\r?\n/).at(-1));
  assert.equal(parsed.protected, true);
  assert.equal(parsed.hasRuntime, true);
  assert.equal(parsed.hasApps, true);
  assert.equal(parsed.identities.some(id => /Everyone|BUILTIN\\Users/i.test(id)), false);
}

function checkPosixCatalogModes(directory) {
  const source = path.join(directory, 'bundle');
  fs.mkdirSync(path.join(source, 'catalog', 'mode-app'), {recursive: true});
  fs.writeFileSync(path.join(source, 'catalog', 'mode-app', 'oshal-app.yaml'), 'name: mode-app\nversion: 1.0.0\n');
  const archive = path.join(directory, 'catalog.tar.gz');
  assert.equal(spawnSync('tar', ['-czf', archive, '-C', source, 'catalog']).status, 0);
  const install = path.join(directory, 'install');
  fs.mkdirSync(install, {mode: 0o755});
  fs.mkdirSync(path.join(install, 'applications'), {mode: 0o755});
  fs.writeFileSync(path.join(install, 'runtime.env'), 'fixture-only', {mode: 0o600});
  const result = run(`DIR="$1"; umask 077; OSWARM_CATALOG_URL=file://${archive}; CATALOG_COMMIT=${'f'.repeat(40)}; compose() { :; }; wait_ready() { :; }; stage_catalog`, install);
  assert.equal(result.status, 0, result.stderr);
  for (const name of ['applications', 'applications/mode-app']) {
    assert.equal(fs.statSync(path.join(install, name)).mode & 0o777, 0o755);
  }
  assert.equal(fs.statSync(path.join(install, 'applications/mode-app/oshal-app.yaml')).mode & 0o777, 0o644);
  assert.equal(fs.statSync(path.join(install, 'runtime.env')).mode & 0o777, 0o600);
  assert.equal(fs.statSync(install).mode & 0o777, 0o755);
  fs.chmodSync(path.join(install, 'applications/mode-app/oshal-app.yaml'), 0o600);
  const again = run('DIR="$1"; compose() { :; }; wait_ready() { :; }; curl() { return 90; }; stage_catalog', install);
  assert.equal(again.status, 0, again.stderr);
  assert.equal(fs.statSync(path.join(install, 'applications/mode-app/oshal-app.yaml')).mode & 0o777, 0o644);
}

const initialized = `ADMIN=admin; DIR="$1"; INITIAL_OWNER_INITIALIZED=1; GENERATED_PASSWORD=${password}; INITIAL_OWNER_PASSWORD=${password};`;
test('selected-app failure still delivers the generated first-owner password and never says ready', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-credential-test-'));
  try {
    fs.copyFileSync(path.join(__dirname, '../install/docker/owner-applications.cjs'), path.join(directory, 'owner-applications.cjs'));
    const result = run(initialized + ' OWNER_APPS=engineering; compose() { cat >/dev/null; return 1; }; provision_initial_owner', directory);
    assert.equal(result.status, 1);
    assert.match(result.stdout, new RegExp('^Password:        ' + password + '$', 'm'));
    assert.equal((result.stdout.match(/^Password:/gm) || []).length, 1);
    assert.doesNotMatch(result.stdout, /oswarm is ready/);
    assert.match(result.stderr, /selected owner setup failed/);
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});
test('an unexpected post-initialization error also preserves delivery of the generated password', () => {
  const result = run(initialized + ' false');
  assert.equal(result.status, 1);
  assert.match(result.stdout, new RegExp(password));
  assert.match(result.stderr, /failed at line/);
});
test('an existing installation neither provisions again nor prints or resets a password', () => {
  const result = run('INITIAL_OWNER_INITIALIZED=0; GENERATED_PASSWORD=""; INITIAL_OWNER_PASSWORD=""; OWNER_APPS=engineering; compose() { echo unexpected-call; return 2; }; provision_initial_owner');
  assert.equal(result.status, 0);
  assert.match(result.stdout, /owner assignments are unchanged/);
  assert.doesNotMatch(result.stdout + result.stderr, /Password:|unexpected-call|init-password/);
});
test('a supplied password is not echoed by the failure recovery notice', () => {
  const result = run(`INITIAL_OWNER_INITIALIZED=1; GENERATED_PASSWORD=""; INITIAL_OWNER_PASSWORD=${password}; die fixture-failure`);
  assert.equal(result.status, 1);
  assert.doesNotMatch(result.stdout + result.stderr, new RegExp(password));
});
test('a fresh catalog copied under umask077 is readable to the kernel and configuration remains private', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-catalog-mode-test-'));
  try {
    if (process.platform === 'win32') checkWindowsPrivateConfig(directory);
    else checkPosixCatalogModes(directory);
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});
