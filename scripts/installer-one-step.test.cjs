/**
 * CHANGE LOG
 * -----------------------------------------------------------------------------
 * SEQ                 | AUTHOR                      | DESCRIPTION
 * -----------------------------------------------------------------------------
 * 1 | maintainer@emeraldcoastsystemsgroup.com   | Regression guards for one-step installer AppArmor detection, atomic staging, incomplete-install recovery, unbound USER/root handling, public URL port sync, and CLI Windows arg translation
 */
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { translateWindowsArgs } = require('../bin/oshal-swarm.cjs');

const ROOT = path.join(__dirname, '..');
const INSTALL_SH = fs.readFileSync(path.join(ROOT, 'install/install.sh'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/\nparse_arguments "\$@"[\s\S]*$/, '');

function runBashFixture(body, extraEnv = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-one-step-test-'));
  try {
    const script = path.join(dir, 'fixture.sh');
    fs.writeFileSync(script, INSTALL_SH + '\n' + body + '\n');
    const bashScript = process.platform === 'win32' ? script.replace(/\\/g, '/') : script;
    return spawnSync('bash', [bashScript], {
      encoding: 'utf8',
      env: { PATH: process.env.PATH, HOME: dir, ...extraEnv },
    });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('AppArmor enabled without mounted securityfs falls back to unconfined without failing or writing destination', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-aa-nosecfs-'));
  try {
    const modDir = path.join(work, 'module');
    fs.mkdirSync(path.join(modDir, 'parameters'), { recursive: true });
    fs.writeFileSync(path.join(modDir, 'parameters/enabled'), 'Y\n');
    const dest = path.join(work, 'etc/oshal-bwrap');
    const res = runBashFixture(`
OS=Linux
ensure_sandbox_policy
printf 'PROFILE=%s\\n' "$APPARMOR_PROFILE_DEFAULT"
`, {
      OSWARM_APPARMOR_MODULE_DIR: modDir,
      OSWARM_APPARMOR_SECURITYFS_DIR: path.join(work, 'missing-securityfs'),
      OSWARM_APPARMOR_DEST: dest,
    });
    assert.equal(res.status, 0, res.stderr);
    assert.match(res.stdout, /PROFILE=unconfined/);
    assert.equal(fs.existsSync(dest), false);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('a failed apparmor_parser load never leaves an unloaded profile on disk', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-aa-fail-'));
  try {
    const modDir = path.join(work, 'module');
    const secDir = path.join(work, 'securityfs');
    fs.mkdirSync(path.join(modDir, 'parameters'), { recursive: true });
    fs.mkdirSync(secDir, { recursive: true });
    fs.writeFileSync(path.join(modDir, 'parameters/enabled'), 'Y\n');
    const dest = path.join(work, 'etc/oshal-bwrap');
    const res = runBashFixture(`
OS=Linux
as_root() { "$@"; }
apparmor_parser() {
  if [ "$1" = "-Q" ]; then return 0; fi
  return 1
}
ensure_sandbox_policy
`, {
      OSWARM_APPARMOR_MODULE_DIR: modDir,
      OSWARM_APPARMOR_SECURITYFS_DIR: secDir,
      OSWARM_APPARMOR_DEST: dest,
    });
    assert.notEqual(res.status, 0);
    assert.equal(fs.existsSync(dest), false);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('unset USER env var and root execution without sudo do not fail under set -u', () => {
  const res = runBashFixture(`
OS=Linux
id() { if [ "\${1:-}" = "-u" ]; then echo 0; else echo root; fi; }
docker_works() { return 0; }
docker() { return 0; }
ensure_docker
printf 'CURRENT_USER=%s\\n' "$CURRENT_USER"
`);
  assert.equal(res.status, 0, res.stderr);
  assert.doesNotMatch(res.stderr, /unbound variable/);
});

test('failed bundle download leaves target installation directory untouched so retry is not blocked', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-bundle-404-'));
  try {
    const targetDir = path.join(work, 'oswarm-install');
    const tmpDir = path.join(work, 'tmp');
    fs.mkdirSync(tmpDir);
    const res = runBashFixture(`
DIR="$OSWARM_DIR"
PORT=39871
IMAGE="ghcr.io/emeraldcoastsystemsgroup/oswarm:0.1.0"
IMAGE_SET=1
port_is_free() { return 0; }
curl() { return 22; }
install_product
`, { OSWARM_DIR: targetDir, TMPDIR: tmpDir });
    assert.notEqual(res.status, 0);
    assert.equal(fs.existsSync(targetDir), false);
    assert.deepEqual(fs.readdirSync(tmpDir), []);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('incomplete installation with .installing marker is cleaned and re-initialized on retry instead of skipping init-password', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-retry-incomplete-'));
  try {
    const targetDir = path.join(work, 'oswarm-install');
    fs.mkdirSync(targetDir, { recursive: true });
    fs.writeFileSync(path.join(targetDir, 'runtime.env'), 'OSHAL_ADMIN_SUBJECT=admin\n');
    fs.writeFileSync(path.join(targetDir, 'compose.yaml'), '# stale\n');
    fs.writeFileSync(path.join(targetDir, '.installing'), '');
    const res = runBashFixture(`
DIR="$OSWARM_DIR"
ensure_tools() { :; }
ensure_docker() { :; }
ensure_sandbox_policy() { :; }
compose() { printf 'compose:%s\\n' "$*"; }
install_product() { mkdir -p "$DIR"; printf 'ran-install-product\\n'; }
stage_catalog() { :; }
provision_initial_owner() { :; }
print_summary() { :; }
open_browser() { :; }
do_install
`, { OSWARM_DIR: targetDir });
    assert.equal(res.status, 0, res.stderr);
    assert.match(res.stdout, /cleaning up an incomplete earlier installation/);
    assert.match(res.stdout, /ran-install-product/);
    assert.doesNotMatch(res.stdout, /already an installation/);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('write_configuration aligns OSWARM_PUBLIC_URL with custom OSWARM_PORT unless explicitly overridden', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-port-url-'));
  try {
    const bundleSrc = path.join(work, 'bundle');
    fs.mkdirSync(bundleSrc);
    for (const f of ['compose.yaml', 'seccomp-bwrap.json', 'image-release.env', 'image-loader.sh']) {
      fs.copyFileSync(path.join(ROOT, 'install/docker', f), path.join(bundleSrc, f));
    }
    fs.copyFileSync(path.join(ROOT, 'install/docker/.env.example'), path.join(bundleSrc, 'env.example'));
    fs.copyFileSync(path.join(ROOT, 'install/install.sh'), path.join(bundleSrc, 'oswarm.sh'));
    const targetDir = path.join(work, 'installed');
    const res = runBashFixture(`
DIR="$OSWARM_DIR"
PORT=38791
IMAGE="ghcr.io/emeraldcoastsystemsgroup/oswarm:0.1.0"
APPARMOR_PROFILE_DEFAULT="unconfined"
docker() { echo "4 8589934592"; }
write_configuration "$BUNDLE_SRC"
`, { OSWARM_DIR: targetDir, BUNDLE_SRC: bundleSrc });
    assert.equal(res.status, 0, res.stderr);
    const envContent = fs.readFileSync(path.join(targetDir, '.env'), 'utf8');
    const lines = envContent.trim().split('\n');
    assert.equal(lines.filter(l => l.startsWith('OSWARM_PUBLIC_URL=')).at(-1), 'OSWARM_PUBLIC_URL=http://127.0.0.1:38791');
    assert.equal(lines.filter(l => l.startsWith('OSWARM_APPARMOR_PROFILE=')).at(-1), 'OSWARM_APPARMOR_PROFILE=unconfined');
    const composeYaml = fs.readFileSync(path.join(ROOT, 'install/docker/compose.yaml'), 'utf8');
    assert.match(composeYaml, /OSHAL_PUBLIC_URL:\s*\$\{OSWARM_PUBLIC_URL:-http:\/\/127\.0\.0\.1:\$\{OSWARM_PORT:-38788\}\}/);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('bin/oshal-swarm.cjs translates prepare and --owner-apps for Windows PowerShell invocation', () => {
  assert.deepEqual(
    translateWindowsArgs(['prepare']),
    ['-Action', 'prepare']
  );
  assert.deepEqual(
    translateWindowsArgs(['install', '--dir', 'C:\\oswarm', '--port', '38791', '--owner-apps', 'engineering']),
    ['-Action', 'install', '-dir', 'C:\\oswarm', '-port', '38791', '-OwnerApps', 'engineering']
  );
  assert.throws(() => translateWindowsArgs(['--owner-apps']), /Supply a value for --owner-apps/);
});
