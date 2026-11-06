/**
 * CHANGE LOG
 * -----------------------------------------------------------------------------
 * SEQ                 | AUTHOR                      | DESCRIPTION
 * -----------------------------------------------------------------------------
 * 1 | maintainer@emeraldcoastsystemsgroup.com   | Initial implementation
 * 2 | maintainer@emeraldcoastsystemsgroup.com   | Normalize LF endings and stub Linux uname for cross-platform Bash checks
 */
'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawnSync} = require('node:child_process');
const source = fs.readFileSync(path.join(__dirname, '../install/kubernetes-bootstrap.sh'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/\nmain "\$@"\s*$/, '');

test('a corrupt private Node download is refused and its temporary files are removed', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'swarm-node-bootstrap-'));
  const bashDir = process.platform === 'win32' ? directory.replace(/\\/g, '/') : directory;
  try {
    const result = spawnSync('bash', ['-c', source + `
export XDG_DATA_HOME="$1"
uname() { if [ "\${1:-}" = -s ]; then echo Linux; else echo x86_64; fi; }
curl() { printf 'corrupted fixture archive' > "\${!#}"; }
tar() { echo 'unexpected extraction' >&2; return 91; }
prepare_node
`, 'bootstrap-test', bashDir], {encoding: 'utf8'});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /checksum mismatch/);
    assert.doesNotMatch(result.stderr, /unexpected extraction/);
    assert.deepEqual(fs.readdirSync(path.join(directory, 'oshal', 'installer-runtime')), []);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
