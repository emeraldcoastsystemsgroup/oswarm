/**
 * CHANGE LOG
 * -----------------------------------------------------------------------------
 * SEQ                 | AUTHOR                      | DESCRIPTION
 * -----------------------------------------------------------------------------
 * 1 | maintainer@emeraldcoastsystemsgroup.com   | Regression guards for one-step installer AppArmor detection, atomic staging, incomplete-install recovery, unbound USER/root handling, public URL port sync, and CLI Windows arg translation
 * 2 | maintainer@emeraldcoastsystemsgroup.com   | Add R1-R4 and P1 regression guards for non-root AppArmor policy/profiles check, early .installing token ordering, project collision refusal, foreign .installing safety, and self-rooted oswarm.sh manager
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
const INSTALL_SH_FULL = fs.readFileSync(path.join(ROOT, 'install/install.sh'), 'utf8')
  .replace(/\r\n/g, '\n');
const INSTALL_SH = INSTALL_SH_FULL.replace(/\nparse_arguments "\$@"[\s\S]*$/, '');

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

function stageBundleFixture(bundleDir) {
  fs.mkdirSync(bundleDir, { recursive: true });
  for (const f of ['compose.yaml', 'seccomp-bwrap.json', 'image-release.env', 'image-loader.sh']) {
    fs.copyFileSync(path.join(ROOT, 'install/docker', f), path.join(bundleDir, f));
  }
  fs.copyFileSync(path.join(ROOT, 'install/docker/.env.example'), path.join(bundleDir, 'env.example'));
  fs.copyFileSync(path.join(ROOT, 'install/install.sh'), path.join(bundleDir, 'oswarm.sh'));
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

test('R1a: non-root re-run with loaded policy/profiles/oshal-bwrap.* and EACCES profiles file never invokes as_root', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-r1a-'));
  try {
    const modDir = path.join(work, 'module');
    const secDir = path.join(work, 'securityfs');
    fs.mkdirSync(path.join(modDir, 'parameters'), { recursive: true });
    fs.mkdirSync(path.join(secDir, 'policy/profiles/oshal-bwrap.47'), { recursive: true });
    fs.writeFileSync(path.join(modDir, 'parameters/enabled'), 'Y\n');
    fs.writeFileSync(path.join(secDir, 'profiles'), 'oshal-bwrap (unconfined)\n', { mode: 0o444 });
    const dest = path.join(work, 'etc/oshal-bwrap');
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const res = runBashFixture(`
OS=Linux
apparmor_profile > "$OSWARM_APPARMOR_DEST"
apparmor_parser() { return 0; }
grep() {
  if [ "\${!#}" = "$OSWARM_APPARMOR_SECURITYFS_DIR/profiles" ]; then
    echo "grep: Permission denied" >&2
    return 2
  fi
  command grep "$@"
}
as_root() { echo "UNEXPECTED_AS_ROOT:$*" >&2; return 99; }
ensure_sandbox_policy
`, {
      OSWARM_APPARMOR_MODULE_DIR: modDir,
      OSWARM_APPARMOR_SECURITYFS_DIR: secDir,
      OSWARM_APPARMOR_DEST: dest,
    });
    assert.equal(res.status, 0, res.stderr);
    assert.doesNotMatch(res.stderr, /UNEXPECTED_AS_ROOT/);
    assert.match(res.stdout, /the oshal-bwrap profile is already installed/);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('R1b: existing profile on disk reloads via as_root when readable policy/profiles lacks oshal-bwrap.*', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-r1b-'));
  try {
    const modDir = path.join(work, 'module');
    const secDir = path.join(work, 'securityfs');
    fs.mkdirSync(path.join(modDir, 'parameters'), { recursive: true });
    fs.mkdirSync(path.join(secDir, 'policy/profiles/other-profile.1'), { recursive: true });
    fs.writeFileSync(path.join(modDir, 'parameters/enabled'), 'Y\n');
    const dest = path.join(work, 'etc/oshal-bwrap');
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const res = runBashFixture(`
OS=Linux
apparmor_profile > "$OSWARM_APPARMOR_DEST"
apparmor_parser() { echo "LOADED:$*"; return 0; }
as_root() { echo "AS_ROOT:$*"; "$@"; }
ensure_sandbox_policy
`, {
      OSWARM_APPARMOR_MODULE_DIR: modDir,
      OSWARM_APPARMOR_SECURITYFS_DIR: secDir,
      OSWARM_APPARMOR_DEST: dest,
    });
    assert.equal(res.status, 0, res.stderr);
    assert.match(res.stdout, /AS_ROOT:apparmor_parser -r -K/);
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
docker() { return 0; }
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

test('R2a: invalid OSWARM_ENGINE_MIRROR is refused upfront in parse_arguments before touching disk', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-r2a-'));
  try {
    const targetDir = path.join(work, 'oswarm-install');
    for (const badMirror of ['{"url_prefix":"http://127.0.0.1:5000"}\t', 'not-json', '["array"]']) {
      const res = runBashFixture(`
OS=Linux; ARCH=x86_64
parse_arguments
`, { OSWARM_DIR: targetDir, OSWARM_ENGINE_MIRROR: badMirror });
      assert.notEqual(res.status, 0, `expected refusal for ${JSON.stringify(badMirror)}`);
      assert.equal(fs.existsSync(targetDir), false);
    }
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('R2b: failure inside write_configuration after runtime.env is written still leaves valid .installing token so retry runs install_product', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-r2b-'));
  try {
    const bundleSrc = path.join(work, 'bundle');
    stageBundleFixture(bundleSrc);
    const targetDir = path.join(work, 'oswarm-install');
    const first = runBashFixture(`
DIR="$OSWARM_DIR"
docker() { echo "2 4294967296"; }
chmod() {
  if [ "$1" = "0755" ]; then return 1; fi
  command chmod "$@"
}
write_configuration "$BUNDLE_SRC"
`, { OSWARM_DIR: targetDir, BUNDLE_SRC: bundleSrc });
    assert.notEqual(first.status, 0);
    assert.equal(fs.existsSync(path.join(targetDir, 'runtime.env')), true);

    const retry = runBashFixture(`
DIR="$OSWARM_DIR"
ensure_tools() { :; }
ensure_docker() { :; }
ensure_sandbox_policy() { :; }
docker() { return 0; }
compose() { printf 'compose:%s\\n' "$*"; }
install_product() { mkdir -p "$DIR"; printf 'ran-install-product\\n'; }
stage_catalog() { :; }
provision_initial_owner() { :; }
print_summary() { :; }
open_browser() { :; }
do_install
`, { OSWARM_DIR: targetDir });
    assert.equal(retry.status, 0, retry.stderr);
    assert.match(retry.stdout, /cleaning up an incomplete earlier installation/);
    assert.match(retry.stdout, /ran-install-product/);
    assert.doesNotMatch(retry.stdout, /already an installation/);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('R3: fresh install refuses before creating DIR when Compose project already has containers or volumes', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-r3-'));
  try {
    const secondDir = path.join(work, 'oswarm-second');
    for (const collisionKind of ['container', 'volume']) {
      const res = runBashFixture(`
DIR="$OSWARM_DIR"
PROJECT="oswarm"
PORT=38796
IMAGE="ghcr.io/emeraldcoastsystemsgroup/oswarm:0.1.0"
IMAGE_SET=1
port_is_free() { return 0; }
docker() {
  if [ "$1" = "ps" ] && [ "$COLLISION" = "container" ]; then echo "abc123def456"; return 0; fi
  if [ "$1" = "volume" ] && [ "$COLLISION" = "volume" ]; then echo "oswarm_postgres_state"; return 0; fi
  return 0
}
compose() { echo "UNEXPECTED_COMPOSE:$*" >&2; return 99; }
install_product
`, { OSWARM_DIR: secondDir, COLLISION: collisionKind });
      assert.notEqual(res.status, 0, `expected refusal on ${collisionKind} collision`);
      assert.match(res.stderr, /OSWARM_PROJECT/);
      assert.doesNotMatch(res.stderr, /UNEXPECTED_COMPOSE/);
      assert.equal(fs.existsSync(secondDir), false);
    }
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('R4: unrelated directory with user files and empty or wrong .installing marker is refused without deleting files', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-r4-'));
  try {
    for (const [name, markerBody, withCompose] of [
      ['empty-marker', '', false],
      ['wrong-token-with-compose', 'foreign-token\n', true],
      ['token-without-compose', 'oswarm-incomplete-install-v1\n', false],
    ]) {
      const userDir = path.join(work, name);
      fs.mkdirSync(userDir, { recursive: true });
      fs.writeFileSync(path.join(userDir, 'notes.txt'), 'keep-me-safe\n');
      fs.writeFileSync(path.join(userDir, '.installing'), markerBody);
      if (withCompose) fs.writeFileSync(path.join(userDir, 'compose.yaml'), '# foreign\n');
      const res = runBashFixture(`
DIR="$OSWARM_DIR"
ensure_tools() { :; }
ensure_docker() { :; }
ensure_sandbox_policy() { :; }
compose() { echo "UNEXPECTED_COMPOSE:$*" >&2; return 99; }
do_install
`, { OSWARM_DIR: userDir });
      assert.notEqual(res.status, 0, `expected refusal for ${name}`);
      assert.match(res.stderr, /exists but is not an oswarm installation/);
      assert.equal(fs.readFileSync(path.join(userDir, 'notes.txt'), 'utf8'), 'keep-me-safe\n');
    }
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('incomplete installation with valid .installing token and compose.yaml is cleaned and re-initialized on retry', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-retry-incomplete-'));
  try {
    const targetDir = path.join(work, 'oswarm-install');
    fs.mkdirSync(targetDir, { recursive: true });
    fs.writeFileSync(path.join(targetDir, 'runtime.env'), 'OSHAL_ADMIN_SUBJECT=admin\n');
    fs.writeFileSync(path.join(targetDir, 'compose.yaml'), '# incomplete\n');
    fs.writeFileSync(path.join(targetDir, '.installing'), 'oswarm-incomplete-install-v1\n');
    const res = runBashFixture(`
DIR="$OSWARM_DIR"
ensure_tools() { :; }
ensure_docker() { :; }
ensure_sandbox_policy() { :; }
docker() { return 0; }
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

test('P1: copied <dir>/oswarm.sh acts on its own directory and saved OSWARM_PROJECT without --dir or env vars', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-p1-'));
  try {
    const fakeBin = path.join(work, 'bin');
    const homeDir = path.join(work, 'home');
    const firstDir = path.join(homeDir, 'oswarm');
    const secondDir = path.join(homeDir, 'second');
    const dockerLog = path.join(work, 'docker.log');
    fs.mkdirSync(fakeBin, { recursive: true });
    fs.mkdirSync(firstDir, { recursive: true });
    fs.mkdirSync(secondDir, { recursive: true });
    fs.writeFileSync(path.join(firstDir, 'compose.yaml'), 'name: ${OSWARM_PROJECT:-oswarm}\n');
    fs.writeFileSync(path.join(firstDir, '.env'), 'OSWARM_PORT=38788\nOSWARM_PROJECT=oswarm\n');
    fs.writeFileSync(path.join(firstDir, 'keep.txt'), 'first-install\n');
    fs.writeFileSync(path.join(secondDir, 'compose.yaml'), 'name: ${OSWARM_PROJECT:-oswarm}\n');
    fs.writeFileSync(path.join(secondDir, '.env'), 'OSWARM_PORT=38796\nOSWARM_PROJECT=second\n');
    const copiedScript = path.join(secondDir, 'oswarm.sh');
    fs.writeFileSync(copiedScript, INSTALL_SH_FULL, { mode: 0o755 });
    const fakeDocker = path.join(fakeBin, 'docker');
    fs.writeFileSync(fakeDocker, `#!/usr/bin/env bash
if [ "$1" = "info" ]; then echo linux; exit 0; fi
if [ "$1" = "compose" ] && [ "$2" = "version" ]; then echo "2.29.0"; exit 0; fi
if [ "$1" = "version" ]; then echo "27.0.0"; exit 0; fi
printf 'PROJECT=%s ARGS=%s\\n' "\${OSWARM_PROJECT:-unset}" "$*" >> "${dockerLog.replace(/\\/g, '/')}"
exit 0
`, { mode: 0o755 });
    const bashCopied = process.platform === 'win32' ? copiedScript.replace(/\\/g, '/') : copiedScript;
    const res = spawnSync('bash', [bashCopied, 'uninstall', '--purge'], {
      encoding: 'utf8',
      env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`, HOME: homeDir, USER: 'tester' },
    });
    assert.equal(res.status, 0, res.stderr);
    assert.equal(fs.existsSync(secondDir), false, 'second installation directory must be removed');
    assert.equal(fs.existsSync(path.join(firstDir, 'keep.txt')), true, 'first installation must remain intact');
    const logText = fs.readFileSync(dockerLog, 'utf8');
    assert.match(logText, /PROJECT=second ARGS=compose --project-directory .*\/second -f .*\/second\/compose\.yaml down --volumes --remove-orphans/);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
});

test('write_configuration aligns OSWARM_PUBLIC_URL with custom OSWARM_PORT unless explicitly overridden', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-port-url-'));
  try {
    const bundleSrc = path.join(work, 'bundle');
    stageBundleFixture(bundleSrc);
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

test('bin/oshal-swarm.cjs translates prepare, --project, and --owner-apps for Windows PowerShell invocation', () => {
  assert.deepEqual(
    translateWindowsArgs(['prepare']),
    ['-Action', 'prepare']
  );
  assert.deepEqual(
    translateWindowsArgs(['install', '--dir', 'C:\\oswarm2', '--project', 'oswarm2', '--port', '38791', '--owner-apps', 'engineering']),
    ['-Action', 'install', '-dir', 'C:\\oswarm2', '-Project', 'oswarm2', '-port', '38791', '-OwnerApps', 'engineering']
  );
  assert.throws(() => translateWindowsArgs(['--owner-apps']), /Supply a value for --owner-apps/);
});
