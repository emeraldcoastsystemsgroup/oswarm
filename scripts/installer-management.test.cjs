/**
 * CHANGE LOG
 * -----------------------------------------------------------------------------
 * SEQ                 | AUTHOR                      | DESCRIPTION
 * -----------------------------------------------------------------------------
 * 1 | maintainer@emeraldcoastsystemsgroup.com   | Initial implementation
 * 2 | maintainer@emeraldcoastsystemsgroup.com   | Normalize LF endings and pin Linux OS/ARCH in Bash day-two fixture
 * 3 | maintainer@emeraldcoastsystemsgroup.com   | Execute Bash fixture from file to avoid Windows 8 KiB argv truncation
 */
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const installer = fs.readFileSync(path.join(__dirname, '../install/install.sh'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/\nparse_arguments "\$@"[\s\S]*$/, '');

test('restart keeps the existing installation and reports ready only after the readiness check', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-restart-'));
  const runnerDir = fs.mkdtempSync(path.join(os.tmpdir(), 'oswarm-restart-script-'));
  const bashDir = process.platform === 'win32' ? directory.replace(/\\/g, '/') : directory;
  try {
    fs.writeFileSync(path.join(directory, 'compose.yaml'), '# existing installation\n');
    fs.writeFileSync(path.join(directory, '.env'), 'OSWARM_PORT=39991\n');
    const run = fail => {
      const scriptFile = path.join(runnerDir, fail ? 'fail.sh' : 'pass.sh');
      fs.writeFileSync(scriptFile, installer + `\nOS=Linux; ARCH=amd64\nparse_arguments restart --dir "$1"\nensure_docker() { :; }\ncompose() { printf 'compose:%s\\n' "$*"; ${fail ? 'return 9' : 'return 0'}; }\nwait_ready() { printf 'checked-ready:%s\\n' "$PORT"; }\nday_two\n`);
      const bashScript = process.platform === 'win32' ? scriptFile.replace(/\\/g, '/') : scriptFile;
      return spawnSync('bash', [bashScript, bashDir], { encoding: 'utf8' });
    };
    const result = run(false);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /compose:restart\nchecked-ready:39991\nready: http:\/\/127\.0\.0\.1:39991\/login/);
    assert.equal(fs.readFileSync(path.join(directory, '.env'), 'utf8'), 'OSWARM_PORT=39991\n');
    const failure = run(true);
    assert.notEqual(failure.status, 0);
    assert.doesNotMatch(failure.stdout, /checked-ready|ready: http/);
  } finally {
    fs.rmSync(runnerDir, { recursive: true, force: true });
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
