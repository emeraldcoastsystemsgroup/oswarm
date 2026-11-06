'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { selected, provision } = require('../install/docker/owner-applications.cjs');
test('engineering is a bounded selection and unknown applications are refused', () => {
    assert.deepEqual(selected('scan-to-print,scan-to-print'), ['scan-to-print']);
    assert.equal(selected('engineering').length, 6);
    assert.throws(() => selected('email-summarizer'));
});
function service({ existing = false, rejectPreview = false, heldStatus = 'active' } = {}) {
    const changes = [];
    const requests = [];
    const caller = { id: 'first-owner', subject: 'admin', issuer: 'urn:oshal:local-auth' };
    const transport = async (url, options) => {
        const path = new URL(url).pathname;
        requests.push(path);
        let status = 200;
        let value;
        if (path === '/sessions') {
            status = 201;
            value = { session: 'private-test-session' };
        }
        else {
            assert.equal(options.headers.authorization, 'Bearer private-test-session');
            if (options.method === 'GET')
                value = { administrator: true, caller, revision: 10, assignments: existing ? [{ status: heldStatus, assignment: { id: 'initial-owner-scan-to-print', target: caller, selection: { kind: 'granular', app: 'scan-to-print', role: 'maker' } } }] : [] };
            else {
                const change = JSON.parse(options.body);
                assert.equal(change.target, caller.id, 'only the original owner is assigned');
                assert.deepEqual(change.selection, { kind: 'granular', app: 'scan-to-print', role: 'maker' });
                if (path.endsWith('/preview')) {
                    assert.equal(change.expected_revision, 10);
                    status = rejectPreview ? 409 : 200;
                    value = rejectPreview ? { detail: 'catalog changed' } : { revision: 11, plan_revision: 'current-plan' };
                }
                else {
                    assert.equal(change.expected_revision, 11);
                    assert.equal(change.expected_plan_revision, 'current-plan');
                    changes.push(change);
                    value = { accepted: true };
                }
            }
        }
        return { status, ok: status >= 200 && status < 300, json: async () => value };
    };
    return { transport, changes, requests };
}
const input = { username: 'admin', password: 'initial-test-password', applications: 'scan-to-print' };
test('a selected owner role uses preview authority and current revision, never other people or apps', async () => {
    const api = service();
    assert.deepEqual(await provision(input, api.transport), { applications: ['scan-to-print'] });
    assert.equal(api.changes.length, 1);
    assert.ok(!JSON.stringify(api.changes).includes(input.password));
});
test('an active owner assignment is idempotent and does not get reapproved', async () => {
    const api = service({ existing: true });
    await provision(input, api.transport);
    assert.equal(api.changes.length, 0);
    assert.ok(!api.requests.some(path => path.endsWith('/preview')));
});
test('a failed current catalog preview never sends an apply', async () => {
    const api = service({ rejectPreview: true });
    await assert.rejects(provision(input, api.transport), /scan-to-print:.*catalog changed/);
    assert.equal(api.changes.length, 0);
});

for (const heldStatus of ['revoked', 'contract_changed', 'component_unavailable']) {
  test(`an existing ${heldStatus} owner role is preserved and diagnosed without a new assignment`, async () => {
    const api = service({existing: true, heldStatus});
    await assert.rejects(provision(input, api.transport), new RegExp(`${heldStatus}.*preserved`));
    assert.equal(api.changes.length, 0);
    assert.ok(!api.requests.some(path => path.endsWith('/preview')));
  });
}
